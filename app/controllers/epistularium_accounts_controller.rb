class EpistulariumAccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace, except: :google_callback
  before_action :set_account, only: %i[update destroy sync]

  GOOGLE_STATE_VERIFIER_KEY = "epistularium_google_oauth_state".freeze

  def create
    account = EpistulariumAccount.new(new_account_attributes)
    authorize account
    account.save!
    if sync_requested?
      start_sync!(account)
    else
      redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), notice: "Epistulum added."
    end
  rescue ActiveRecord::RecordInvalid => error
    redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), alert: error.record.errors.full_messages.to_sentence
  end

  def update
    authorize @account

    @account.assign_attributes(update_account_attributes)
    @account.save!
    if sync_requested?
      start_sync!(@account)
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: settings_flash_stream("notice", "Epistulum updated.") }
        format.html { redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), notice: "Epistulum updated." }
      end
    end
  rescue ActiveRecord::RecordInvalid => error
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: settings_flash_stream("alert", error.record.errors.full_messages.to_sentence),
               status: :unprocessable_entity
      end
      format.html { redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), alert: error.record.errors.full_messages.to_sentence }
    end
  end

  def destroy
    authorize @account
    Epistularium::ConnectionDestroyService.new(account: @account).call
    redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), notice: "Epistulum removed."
  end

  def sync
    authorize @account, :sync?
    start_sync!(@account)
  end

  def google_authorize
    authorize @workspace, :show?

    state = google_state_verifier.generate(build_google_oauth_state_payload, expires_in: 20.minutes)
    oauth_url = google_oauth_service.authorization_url(
      redirect_uri: google_callback_redirect_uri,
      state: state
    )
    redirect_to oauth_url, allow_other_host: true
  rescue ActiveRecord::RecordNotFound
    redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), alert: "Google account not found."
  rescue Epistularium::GoogleOauthService::Error => error
    redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), alert: error.message
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
    account = upsert_google_account_from_oauth!(oauth_payload: oauth_payload, token_data: token_data)
    if run_initial_bootstrap_inline?(account)
      Epistularium::SyncConnectionJob.perform_now(account.id, mode: "bootstrap")
      redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), notice: "Google account connected. Recent mail refreshed. Full backfill will continue in the background."
    else
      Epistularium::SyncEnqueueService.new(
        account: account,
        mode: Epistularium::SyncEnqueueService.fresh_mode_for(account)
      ).call
      redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), notice: "Google account connected. Recent mail sync queued. Full backfill will continue in the background."
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_for_google_callback_failure!("Google authorization state is invalid or expired. Please try again.")
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, Epistularium::GoogleOauthService::Error => error
    redirect_for_google_callback_failure!(error.message)
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_account
    @account = policy_scope(EpistulariumAccount).visible_in_workspace(@workspace).find(params[:id])
  end

  def account_params
    params.fetch(:epistularium_account, {}).permit(
      :provider,
      :label,
      :enabled,
      :remote_account_id,
      :provider_username,
      :provider_password,
      :owner_scope,
      :workspace_scope,
      :account_color,
      :imap_host,
      :imap_port,
      :imap_ssl,
      :sent_mailbox
    )
  end

  def new_account_attributes
    owner_scope = requested_owner_scope
    owner = owner_scope == "workspace" ? @workspace : current_user
    attributes = account_attributes_hash

    {
      workspace: @workspace,
      owner: owner,
      created_by: current_user,
      provider: attributes.fetch(:provider),
      label: attributes.fetch(:label),
      enabled: attributes.fetch(:enabled),
      status: "disconnected",
      remote_account_id: attributes[:remote_account_id],
      provider_username: attributes[:provider_username],
      provider_password: attributes[:provider_password],
      settings_json: imap_settings_from(attributes)
        .merge(
          "workspace_scope" => requested_workspace_scope,
          "account_color" => attributes[:account_color]
        ).compact
    }
  end

  def update_account_attributes
    attributes = account_attributes_hash
    update_hash = {
      label: attributes.fetch(:label),
      enabled: attributes.fetch(:enabled),
      remote_account_id: attributes[:remote_account_id],
      settings_json: @account.settings_json.to_h.merge(
        "workspace_scope" => requested_workspace_scope,
        "account_color" => attributes[:account_color]
      ).compact
    }

    if %w[imap amazon_workmail].include?(@account.provider)
      update_hash[:provider_username] = attributes[:provider_username] if attributes.key?(:provider_username)
      update_hash[:provider_password] = attributes[:provider_password] if attributes[:provider_password].present?
      update_hash[:settings_json] = update_hash[:settings_json].merge(imap_settings_from(attributes)).compact
    end

    update_hash
  end

  def account_attributes_hash
    raw = account_params.to_h.symbolize_keys
    {
      provider: raw.fetch(:provider, @account&.provider).to_s,
      label: raw.fetch(:label, @account&.label).to_s.strip.presence || default_label_for_provider(raw.fetch(:provider, @account&.provider)),
      enabled: raw.key?(:enabled) ? ActiveModel::Type::Boolean.new.cast(raw[:enabled]) : (@account&.enabled.nil? ? true : @account.enabled),
      remote_account_id: raw[:remote_account_id].to_s.strip.presence,
      provider_username: raw[:provider_username].to_s.strip.presence,
      provider_password: raw[:provider_password].to_s.strip.presence,
      account_color: raw[:account_color].to_s.strip.presence,
      imap_host: raw[:imap_host].to_s.strip.presence,
      imap_port: raw[:imap_port].to_i.positive? ? raw[:imap_port].to_i : nil,
      imap_ssl: raw[:imap_ssl].nil? ? true : ActiveModel::Type::Boolean.new.cast(raw[:imap_ssl]),
      sent_mailbox: raw[:sent_mailbox].to_s.strip.presence
    }
  end

  def imap_settings_from(attributes)
    {
      "imap_host" => attributes[:imap_host],
      "imap_port" => attributes[:imap_port],
      "imap_ssl" => attributes[:imap_ssl],
      "sent_mailbox" => attributes[:sent_mailbox]
    }.compact
  end

  def default_label_for_provider(provider)
    case provider.to_s
    when "amazon_workmail"
      "Amazon WorkMail"
    when "imap"
      "IMAP mailbox"
    else
      "Gmail mailbox"
    end
  end

  def requested_owner_scope
    account_params[:owner_scope].to_s == "workspace" ? "workspace" : "user"
  end

  def requested_workspace_scope
    account_params[:workspace_scope].to_s == "all_workspaces" ? "all_workspaces" : "this_workspace"
  end

  def sync_requested?
    params[:sync_now].to_s == "1"
  end

  def start_sync!(account)
    mode = preferred_sync_mode_for(account)
    if run_initial_bootstrap_inline?(account)
      Epistularium::SyncConnectionJob.perform_now(account.id, mode: "bootstrap")
      notice = account.reload.full_backfill_pending? ? "Recent mail refreshed. Full backfill will continue in the background." : "Recent mail refreshed."
      return redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), notice: notice
    end

    if Epistularium::SyncRecoveryService.new(account: account).call
      notice = account.reload.full_backfill_pending? ? "Recent mail refreshed. Full backfill will continue in the background." : "Recent mail refreshed."
      return redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), notice: notice
    end

    result = Epistularium::SyncEnqueueService.new(account: account, mode: mode, throttle: 0).call
    notice =
      case result
      when Epistularium::SyncEnqueueService::ENQUEUE_RESULTS[:enqueued]
        account.full_backfill_pending? ? "Recent mail sync queued. Full backfill will continue in the background." : "Recent mail sync queued."
      when Epistularium::SyncEnqueueService::ENQUEUE_RESULTS[:already_running]
        "Sync is already in progress."
      else
        "Sync already queued."
      end
    redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), notice: notice
  rescue StandardError => error
    redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), alert: "Sync could not be queued: #{error.message}"
  end

  def preferred_sync_mode_for(account)
    Epistularium::SyncEnqueueService.fresh_mode_for(account)
  end

  def run_initial_bootstrap_inline?(account)
    preferred_sync_mode_for(account) == "bootstrap" && !account.sync_active?
  end

  def build_google_oauth_state_payload
    account = nil
    account_id = params[:account_id].to_s.presence
    if account_id.present?
      account = policy_scope(EpistulariumAccount).visible_in_workspace(@workspace).find(account_id)
      authorize account, :update?
    else
      policy_probe = EpistulariumAccount.new(
        workspace: @workspace,
        owner: requested_owner_scope == "workspace" ? @workspace : current_user,
        created_by: current_user,
        provider: "gmail",
        label: params[:label].to_s.strip.presence || "Gmail mailbox",
        access_token: "oauth-pending"
      )
      authorize policy_probe, :create?
    end

    {
      "workspace_id" => @workspace.id,
      "user_id" => current_user.id,
      "account_id" => account&.id,
      "owner_scope" => requested_owner_scope,
      "workspace_scope" => requested_workspace_scope,
      "label" => params[:label].to_s.strip.presence || "Gmail mailbox",
      "account_color" => account_params[:account_color].to_s.strip.presence
    }
  end

  def verified_google_oauth_state!(raw_state)
    payload = google_state_verifier.verify(raw_state)
    unless payload["user_id"].to_s == current_user.id.to_s && payload["workspace_id"].present?
      raise ActiveSupport::MessageVerifier::InvalidSignature
    end

    payload
  end

  def upsert_google_account_from_oauth!(oauth_payload:, token_data:)
    account_id = oauth_payload["account_id"].to_s.presence
    if account_id.present?
      account = policy_scope(EpistulariumAccount).visible_in_workspace(@workspace).find(account_id)
      authorize account, :update?
    else
      owner = oauth_payload["owner_scope"].to_s == "workspace" ? @workspace : current_user
      account = policy_scope(EpistulariumAccount).where(workspace_id: @workspace.id).find_or_initialize_by(
        owner: owner,
        provider: "gmail",
        label: oauth_payload["label"].to_s.presence || "Gmail mailbox"
      )
      if account.new_record?
        account.workspace = @workspace
        account.owner = owner
        account.created_by = current_user
        account.status = "disconnected"
        authorize account, :create?
      else
        authorize account, :update?
      end
    end

    apply_google_token_data!(
      account: account,
      token_data: token_data,
      workspace_scope: oauth_payload["workspace_scope"],
      account_color: oauth_payload["account_color"]
    )
    account
  end

  def apply_google_token_data!(account:, token_data:, workspace_scope:, account_color: nil)
    account.access_token = token_data[:access_token]
    account.refresh_token = token_data[:refresh_token] if token_data[:refresh_token].present?
    account.scopes_json = token_data[:scope].to_s.split(/\s+/).reject(&:blank?)
    account.oauth_client_id = Epistularium::GoogleOauthService.resolved_client_id.to_s.strip.presence
    account.oauth_client_secret = Epistularium::GoogleOauthService.resolved_client_secret.to_s.strip.presence
    account.enabled = true
    account.status = "connected"
    account.last_error = nil
    account.settings_json = account.settings_json.to_h.merge(
      "workspace_scope" => workspace_scope.to_s == "all_workspaces" ? "all_workspaces" : "this_workspace",
      "account_color" => account_color_for_google_account(account, requested_color: account_color),
      "google_token_type" => token_data[:token_type].to_s.presence,
      "google_access_token_expires_at" => (
        token_data[:expires_in].to_i.positive? ? (Time.current + token_data[:expires_in].to_i.seconds).iso8601 : nil
      )
    ).compact
    account.save!
  end

  def account_color_for_google_account(account, requested_color: nil)
    requested_color.to_s.strip.presence ||
      account_params[:account_color].to_s.strip.presence ||
      account.settings_json.to_h["account_color"].to_s.strip.presence ||
      nil
  end

  def google_oauth_service
    @google_oauth_service ||= Epistularium::GoogleOauthService.new
  end

  def google_state_verifier
    @google_state_verifier ||= Rails.application.message_verifier(GOOGLE_STATE_VERIFIER_KEY)
  end

  def google_callback_redirect_uri
    "#{external_app_base_url}#{epistularium_google_callback_path}"
  end

  def redirect_for_google_callback_failure!(message)
    if @workspace.present?
      redirect_to workspace_epistularium_settings_path(workspace_slug: @workspace.slug), alert: message
    else
      redirect_to root_path, alert: message
    end
  end
end
