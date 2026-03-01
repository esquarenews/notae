class KalendariumConnectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace, except: :google_callback
  before_action :set_connection, only: %i[update destroy sync]
  GOOGLE_STATE_VERIFIER_KEY = "kalendarium_google_oauth_state".freeze

  def create
    owner = resolve_owner
    connection = KalendariumConnection.new(connection_params.merge(
      workspace: @workspace,
      owner: owner,
      created_by: current_user,
      status: "disconnected"
    ))
    authorize connection

    if connection.save
      flash_type, message = sync_connection_if_requested(connection, success_message: "Calendar connection added and synced.")
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), flash_type => message
    else
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: connection.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @connection

    if @connection.update(connection_params)
      flash_type, message = sync_connection_if_requested(@connection, success_message: "Connection updated and synced.", fallback_message: "Connection updated.")
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), flash_type => message
    else
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: @connection.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @connection
    @connection.destroy!
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "Connection removed."
  end

  def sync
    authorize @connection, :sync?
    Kalendarium::SyncConnectionJob.perform_later(@connection.id)
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "Sync queued."
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
    connection = upsert_google_connection_from_oauth!(oauth_payload: oauth_payload, token_data: token_data)
    flash_type, message = sync_connection_now(connection)
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
    params.require(:kalendarium_connection).permit(
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

  def resolve_owner
    owner_scope = params.dig(:kalendarium_connection, :owner_scope).to_s
    return @workspace if owner_scope == "workspace"

    current_user
  end

  def sync_connection_if_requested(connection, success_message:, fallback_message: "Calendar connection added.")
    return [ :notice, fallback_message ] unless params[:sync_now].to_s == "1"

    Kalendarium::ConnectionSyncService.new(connection: connection).call
    [ :notice, success_message ]
  rescue StandardError => error
    [ :alert, "Connection saved but sync failed: #{error.message}" ]
  end

  def sync_connection_now(connection)
    Kalendarium::ConnectionSyncService.new(connection: connection).call
    [ :notice, "Google calendar connected and synced." ]
  rescue StandardError => error
    [ :alert, "Google connected but sync failed: #{error.message}" ]
  end

  def build_google_oauth_state_payload
    connection = nil
    connection_id = params[:connection_id].to_s.presence
    if connection_id.present?
      connection = policy_scope(KalendariumConnection).for_workspace(@workspace).find(connection_id)
      authorize connection, :update?
    end

    owner_scope = params[:owner_scope].to_s == "workspace" ? "workspace" : "user"
    label = params[:label].to_s.strip.presence || "Google calendar"

    if connection.nil?
      owner = owner_scope == "workspace" ? @workspace : current_user
      policy_probe = KalendariumConnection.new(
        workspace: @workspace,
        owner: owner,
        created_by: current_user,
        provider: "google",
        label: label,
        access_token: "oauth-pending"
      )
      authorize policy_probe, :create?
    end

    {
      "workspace_id" => @workspace.id,
      "user_id" => current_user.id,
      "connection_id" => connection&.id,
      "owner_scope" => owner_scope,
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

  def upsert_google_connection_from_oauth!(oauth_payload:, token_data:)
    connection = nil
    connection_id = oauth_payload["connection_id"].to_s.presence
    if connection_id.present?
      connection = policy_scope(KalendariumConnection).for_workspace(@workspace).find(connection_id)
      authorize connection, :update?
    else
      owner = oauth_payload["owner_scope"].to_s == "workspace" ? @workspace : current_user
      label = oauth_payload["label"].to_s.presence || "Google calendar"
      connection = policy_scope(KalendariumConnection).for_workspace(@workspace).find_by(
        owner: owner,
        provider: "google",
        label: label
      )
      if connection.present?
        authorize connection, :update?
      else
        connection = KalendariumConnection.new(
          workspace: @workspace,
          owner: owner,
          created_by: current_user,
          provider: "google",
          label: label,
          enabled: true,
          status: "disconnected"
        )
        authorize connection, :create?
      end
    end

    connection.access_token = token_data[:access_token]
    if token_data[:refresh_token].present?
      connection.refresh_token = token_data[:refresh_token]
    end

    scopes = token_data[:scope].to_s.split(/\s+/).reject(&:blank?)
    connection.scopes_json = scopes if scopes.any?
    connection.settings_json = connection.settings_json.to_h.merge(
      "google_token_type" => token_data[:token_type].to_s.presence,
      "google_access_token_expires_at" => token_data[:expires_in].to_i.positive? ? (Time.current + token_data[:expires_in].to_i.seconds).iso8601 : nil
    ).compact
    connection.save!
    connection
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
