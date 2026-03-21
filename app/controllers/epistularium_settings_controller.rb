class EpistulariumSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?

    @accounts = policy_scope(EpistulariumAccount).for_workspace(@workspace).order(created_at: :desc)
    @latest_message_sync_at_by_account = resolve_latest_message_sync_times(@accounts)
    Epistularium::DueSyncScheduler.new(accounts: @accounts).call
    @google_oauth_configured = Epistularium::GoogleOauthService.configured?
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def resolve_latest_message_sync_times(accounts)
    return {} if accounts.empty?

    policy_scope(EpistulariumMessage)
      .for_workspace(@workspace)
      .where(epistularium_account_id: accounts.map(&:id))
      .group(:epistularium_account_id)
      .maximum(Arel.sql("COALESCE(epistularium_messages.last_synced_at, epistularium_messages.created_at)"))
  end
end
