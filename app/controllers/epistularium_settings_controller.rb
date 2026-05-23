class EpistulariumSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?

    @accounts = policy_scope(EpistulariumAccount).visible_in_workspace(@workspace).order(created_at: :desc)
    Epistularium::DueSyncScheduler.new(accounts: @accounts).call
    @google_oauth_label = next_available_google_label
    @google_oauth_configured = Epistularium::GoogleOauthService.configured?
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def next_available_google_label
    base = "Gmail mailbox"
    existing_labels = @accounts.select { |account| account.provider == "gmail" }.map { |account| account.label.to_s }
    return base unless existing_labels.include?(base)

    index = 2
    loop do
      candidate = "#{base} #{index}"
      return candidate unless existing_labels.include?(candidate)

      index += 1
    end
  end
end
