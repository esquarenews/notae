module Admin
  class UsersController < BaseController
    def index
      @users = User.includes(:memberships).order(created_at: :desc).limit(100)
    end

    def show
      @user = User.includes(memberships: :workspace).find(params[:id])
      @api_tokens = @user.api_tokens.order(created_at: :desc).limit(12)
      @recent_admin_events = AdminAuditEvent.where(actor: @user).recent_first.limit(12)
    end
  end
end
