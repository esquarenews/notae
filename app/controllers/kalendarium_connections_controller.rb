class KalendariumConnectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace, except: :google_callback
  before_action :set_connection, only: %i[update destroy sync]
  GOOGLE_STATE_VERIFIER_KEY = "kalendarium_google_oauth_state".freeze

  def create
    connections = if source_connection_id.present?
      create_connections_from_source!
    else
      create_connections_from_form!
    end

    workspace_count = connections.size
    fallback_message = workspace_count > 1 ? "Calendar connections saved for #{workspace_count} workspaces." : "Calendar connection added."
    success_message = workspace_count > 1 ? "Calendar connections saved and synced for #{workspace_count} workspaces." : "Calendar connection added and synced."
    flash_type, message = sync_connections_if_requested(
      connections,
      success_message: success_message,
      fallback_message: fallback_message
    )
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), flash_type => message
  rescue ActiveRecord::RecordInvalid => error
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: error.record.errors.full_messages.to_sentence
  rescue ActiveRecord::RecordNotFound => error
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: error.message
  end

  def update
    authorize @connection

    if @connection.update(connection_params)
      flash_type, message = sync_connections_if_requested(
        [ @connection ],
        success_message: "Connection updated and synced.",
        fallback_message: "Connection updated."
      )
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), flash_type => message
    else
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: @connection.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @connection
    Kalendarium::ConnectionDestroyService.new(connection: @connection).call
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "Connection removed."
  end

  def sync
    authorize @connection, :sync?
    Kalendarium::ConnectionSyncService.new(connection: @connection).call
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "Sync completed."
  rescue StandardError => error
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: "Sync failed: #{error.message}"
  end

  def google_authorize
    authorize @workspace, :show?

    payload = build_google_oauth_state_payload
    state = google_state_verifier.generate(payload, expires_in: 20.minutes)
    oauth_url = google_oauth_service.authorization_url(
      redirect_uri: google_callback_redirect_uri,
      state: state
    )
    redirect_to oauth_url, allow_other_host: true
  rescue ActiveRecord::RecordNotFound
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: "Google connection not found."
  rescue Kalendarium::GoogleOauthService::Error => error
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: error.message
  end

  def google_callback
    if params[:error].present?
      message = params[:error_description].to_s.presence || params[:error].to_s
      return redirect_for_google_callback_failure!("Google authorization failed: #{message}")
    end

    oauth_payload = verified_google_oauth_state!(params[:state].to_s)
    @workspace = policy_scope(Workspace).find(oauth_payload["workspace_id"])
    authorize @workspace, :show?

    token_data = google_oauth_service.exchange_code!(
      code: params[:code],
      redirect_uri: google_callback_redirect_uri
    )
    connections = upsert_google_connections_from_oauth!(oauth_payload: oauth_payload, token_data: token_data)
    flash_type, message = queue_or_sync_google_connections(connections)
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), flash_type => message
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_for_google_callback_failure!("Google authorization state is invalid or expired. Please try again.")
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, Kalendarium::GoogleOauthService::Error => error
    redirect_for_google_callback_failure!(error.message)
  end

  def icloud_callback
    authorize @workspace, :show?
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "iCloud callback captured. Save credentials in connection settings to complete setup."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_connection
    @connection = policy_scope(KalendariumConnection).for_workspace(@workspace).find(params[:id])
  end

  def connection_params
    params.fetch(:kalendarium_connection, {}).permit(
      :provider,
      :label,
      :enabled,
      :remote_account_id,
      :access_token,
      :refresh_token,
      :provider_username,
      :provider_password,
      :ics_url
    )
  end

  def create_connections_from_form!
    owner_scope = requested_owner_scope
    params_hash = connection_params.to_h
    metadata = { "workspace_scope" => requested_workspace_scope }

    target_workspaces_for(owner_scope: owner_scope).map do |workspace|
      upsert_connection_for_workspace!(
        workspace: workspace,
        owner_scope: owner_scope,
        attributes: params_hash,
        metadata: metadata
      )
    end
  end

  def create_connections_from_source!
    source = policy_scope(KalendariumConnection).find(source_connection_id)
    authorize source, :show?
    owner_scope = explicit_owner_scope.presence || (source.shared_connection? ? "workspace" : "user")
    metadata = {
      "workspace_scope" => requested_workspace_scope,
      "source_workspace_id" => source.workspace_id,
      "source_connection_id" => source.id
    }

    target_workspaces_for(owner_scope: owner_scope).map do |workspace|
      upsert_connection_for_workspace!(
        workspace: workspace,
        owner_scope: owner_scope,
        attributes: source_connection_attributes(source),
        metadata: metadata
      )
    end
  end

  def source_connection_attributes(source)
    {
      provider: source.provider,
      label: source.label,
      enabled: source.enabled,
      remote_account_id: source.remote_account_id,
      access_token: source.access_token,
      refresh_token: source.refresh_token,
      provider_username: source.provider_username,
      provider_password: source.provider_password,
      ics_url: source.ics_url,
      oauth_client_id: source.oauth_client_id,
      oauth_client_secret: source.oauth_client_secret,
      scopes_json: source.scopes_json
    }.compact
  end

  def upsert_connection_for_workspace!(workspace:, owner_scope:, attributes:, metadata:)
    owner = owner_for_scope(workspace: workspace, owner_scope: owner_scope)
    provider = attributes.fetch("provider", attributes[:provider]).to_s
    label = attributes.fetch("label", attributes[:label]).to_s
    connection = policy_scope(KalendariumConnection).for_workspace(workspace).find_by(
      owner: owner,
      provider: provider,
      label: label
    )

    if connection.present?
      authorize connection, :update?
    else
      connection = KalendariumConnection.new(
        workspace: workspace,
        owner: owner,
        created_by: current_user,
        provider: provider,
        label: label,
        status: "disconnected"
      )
      authorize connection, :create?
    end

    connection.assign_attributes(attributes)
    connection.workspace = workspace
    connection.owner = owner
    connection.created_by ||= current_user
    connection.status ||= "disconnected"
    connection.settings_json = connection.settings_json.to_h.merge(metadata).compact
    connection.save!
    connection
  end

  def owner_for_scope(workspace:, owner_scope:)
    owner_scope == "workspace" ? workspace : current_user
  end

  def sync_connections_if_requested(connections, success_message:, fallback_message:, force: false)
    return [ :notice, fallback_message ] if !force && !sync_requested?

    failures = []
    connections.each do |connection|
      Kalendarium::ConnectionSyncService.new(connection: connection).call
    rescue StandardError => error
      failures << "#{connection.label} (#{connection.workspace.name}): #{error.message}"
    end

    if failures.any?
      if failures.size == connections.size
        [ :alert, "Connection saved but sync failed: #{failures.join(' | ')}" ]
      else
        synced_count = connections.size - failures.size
        [ :alert, "Synced #{synced_count}/#{connections.size} connections. #{failures.join(' | ')}" ]
      end
    else
      [ :notice, success_message ]
    end
  end

  def queue_or_sync_google_connections(connections)
    success_message = if connections.size > 1
      "Google calendar connected and synced for #{connections.size} workspaces."
    else
      "Google calendar connected and synced."
    end

    sync_connections_if_requested(
      connections,
      success_message: success_message,
      fallback_message: "Google calendar connected.",
      force: true
    )
  end

  def build_google_oauth_state_payload
    connection = nil
    connection_id = params[:connection_id].to_s.presence
    if connection_id.present?
      connection = policy_scope(KalendariumConnection).for_workspace(@workspace).find(connection_id)
      authorize connection, :update?
    end

    owner_scope = explicit_owner_scope.presence || "user"
    workspace_scope = requested_workspace_scope
    label = params[:label].to_s.strip.presence || "Google calendar"

    if connection.nil?
      target_workspaces_for(owner_scope: owner_scope, workspace_scope: workspace_scope).each do |workspace|
        owner = owner_for_scope(workspace: workspace, owner_scope: owner_scope)
        policy_probe = KalendariumConnection.new(
          workspace: workspace,
          owner: owner,
          created_by: current_user,
          provider: "google",
          label: label,
          access_token: "oauth-pending"
        )
        authorize policy_probe, :create?
      end
    end

    {
      "workspace_id" => @workspace.id,
      "user_id" => current_user.id,
      "connection_id" => connection&.id,
      "owner_scope" => owner_scope,
      "workspace_scope" => workspace_scope,
      "label" => label
    }
  end

  def verified_google_oauth_state!(raw_state)
    payload = google_state_verifier.verify(raw_state)
    user_id = payload["user_id"].to_s
    workspace_id = payload["workspace_id"].to_s
    workspace_mismatch = @workspace.present? && workspace_id != @workspace.id.to_s
    unless user_id == current_user.id.to_s && workspace_id.present? && !workspace_mismatch
      raise ActiveSupport::MessageVerifier::InvalidSignature
    end

    payload
  end

  def upsert_google_connections_from_oauth!(oauth_payload:, token_data:)
    connection_id = oauth_payload["connection_id"].to_s.presence
    if connection_id.present?
      connection = policy_scope(KalendariumConnection).for_workspace(@workspace).find(connection_id)
      authorize connection, :update?
      apply_google_token_data!(connection: connection, token_data: token_data, workspace_scope: oauth_payload["workspace_scope"])
      return [ connection ]
    end

    owner_scope = oauth_payload["owner_scope"].to_s == "workspace" ? "workspace" : "user"
    workspace_scope = oauth_payload["workspace_scope"].to_s == "all_workspaces" ? "all_workspaces" : "this_workspace"
    label = oauth_payload["label"].to_s.presence || "Google calendar"

    target_workspaces_for(owner_scope: owner_scope, workspace_scope: workspace_scope).map do |workspace|
      owner = owner_for_scope(workspace: workspace, owner_scope: owner_scope)
      connection = policy_scope(KalendariumConnection).for_workspace(workspace).find_by(
        owner: owner,
        provider: "google",
        label: label
      )

      if connection.present?
        authorize connection, :update?
      else
        connection = KalendariumConnection.new(
          workspace: workspace,
          owner: owner,
          created_by: current_user,
          provider: "google",
          label: label,
          enabled: true,
          status: "disconnected"
        )
        authorize connection, :create?
      end

      apply_google_token_data!(connection: connection, token_data: token_data, workspace_scope: workspace_scope)
      connection
    end
  end

  def apply_google_token_data!(connection:, token_data:, workspace_scope:)
    connection.access_token = token_data[:access_token]
    connection.refresh_token = token_data[:refresh_token] if token_data[:refresh_token].present?

    scopes = token_data[:scope].to_s.split(/\s+/).reject(&:blank?)
    connection.scopes_json = scopes if scopes.any?
    connection.settings_json = connection.settings_json.to_h.merge(
      "workspace_scope" => workspace_scope.to_s == "all_workspaces" ? "all_workspaces" : "this_workspace",
      "google_token_type" => token_data[:token_type].to_s.presence,
      "google_access_token_expires_at" => token_data[:expires_in].to_i.positive? ? (Time.current + token_data[:expires_in].to_i.seconds).iso8601 : nil
    ).compact
    connection.oauth_client_id = Kalendarium::GoogleOauthService.resolved_client_id.to_s.strip.presence
    connection.oauth_client_secret = Kalendarium::GoogleOauthService.resolved_client_secret.to_s.strip.presence
    connection.enabled = true
    connection.status = "connected"
    connection.last_error = nil
    connection.save!
  end

  def target_workspaces_for(owner_scope:, workspace_scope: requested_workspace_scope)
    candidates = if workspace_scope == "all_workspaces"
      policy_scope(Workspace).order(:name).to_a
    else
      [ @workspace ]
    end

    permitted = candidates.select do |workspace|
      owner = owner_for_scope(workspace: workspace, owner_scope: owner_scope)
      policy_probe = KalendariumConnection.new(
        workspace: workspace,
        owner: owner,
        created_by: current_user,
        provider: "ics",
        label: "scope-probe",
        ics_url: "https://example.com/scope-probe.ics"
      )
      policy(policy_probe).create?
    end

    permitted.presence || [ @workspace ]
  end

  def explicit_owner_scope
    raw = params[:owner_scope].to_s.presence || params.dig(:kalendarium_connection, :owner_scope).to_s.presence
    return "workspace" if raw == "workspace"
    return "user" if raw == "user"

    nil
  end

  def requested_owner_scope
    explicit_owner_scope || "user"
  end

  def requested_workspace_scope
    raw = params[:workspace_scope].to_s.presence || params.dig(:kalendarium_connection, :workspace_scope).to_s.presence
    raw == "all_workspaces" ? "all_workspaces" : "this_workspace"
  end

  def source_connection_id
    params[:source_connection_id].to_s.presence
  end

  def sync_requested?
    params[:sync_now].to_s == "1"
  end

  def google_oauth_service
    @google_oauth_service ||= Kalendarium::GoogleOauthService.new
  end

  def google_state_verifier
    @google_state_verifier ||= Rails.application.message_verifier(GOOGLE_STATE_VERIFIER_KEY)
  end

  def google_callback_redirect_uri
    "#{request.base_url}#{kalendarium_google_callback_path}"
  end

  def redirect_for_google_callback_failure!(message)
    if @workspace.present?
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: message
    else
      redirect_to root_path, alert: message
    end
  end
end
