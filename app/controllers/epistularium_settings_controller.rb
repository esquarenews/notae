class EpistulariumSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?

    @accounts = policy_scope(EpistulariumAccount).for_workspace(@workspace).order(created_at: :desc)
    Epistularium::DueSyncScheduler.new(accounts: @accounts).call
    @google_oauth_configured = Epistularium::GoogleOauthService.configured?
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end
end
