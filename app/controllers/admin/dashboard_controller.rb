module Admin
  class DashboardController < BaseController
    def show
      @workspace_count = Workspace.count
      @active_workspace_count = Workspace.where(suspended_at: nil).count
      @suspended_workspace_count = Workspace.where.not(suspended_at: nil).count
      @user_count = User.count
      @subscription_counts = WorkspaceSubscription.group(:status).count
      @recent_workspaces = Workspace.includes(:workspace_subscription).order(updated_at: :desc).limit(8)
      @recent_admin_events = AdminAuditEvent.recent_first.includes(:actor, :workspace).limit(12)
      @billing_provider_ready = Billing::FatZebraGateway.configured?
      @fat_zebra_webhook_path = fat_zebra_webhook_path
      @fat_zebra_webhook_auth_ready = Billing::FatZebraGateway.webhook_secret.present?
    end
  end
end
