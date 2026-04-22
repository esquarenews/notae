module Admin
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :require_platform_admin!
    skip_after_action :verify_pundit_authorization

    layout "application"

    private

    def require_platform_admin!
      return if current_user&.platform_admin?

      redirect_to root_path, alert: "You are not authorized to access the admin dashboard."
    end

    def record_admin_audit!(action:, workspace: nil, target: nil, metadata: {})
      AdminAuditEvent.create!(
        actor: current_user,
        workspace: workspace,
        target: target,
        action: action,
        metadata_json: metadata
      )
    end
  end
end
