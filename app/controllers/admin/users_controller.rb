module Admin
  class UsersController < BaseController
    def index
      @users = User.includes(:memberships).order(created_at: :desc).limit(100)
    end

    def show
      @user = User.includes(memberships: :workspace).find(params[:id])
      @usage_summary = Admin::UserUsageSummary.new(users: [ @user ]).call.fetch(@user)
      @api_tokens = @user.api_tokens.order(created_at: :desc).limit(12)
      @recent_admin_events = AdminAuditEvent.where(actor: @user).recent_first.limit(12)
    end

    def update
      @user = User.find(params[:id])
      @user.assign_attributes(user_params)
      @user.save!

      record_admin_audit!(
        action: "user_limits_updated",
        target: @user,
        metadata: user_params.to_h
      )

      redirect_to admin_user_path(@user), notice: "User plan and limits updated."
    end

    private

    def user_params
      permitted = params.require(:user).permit(
        :saas_plan_key,
        :workspace_limit_override,
        :ai_search_daily_budget_usd,
        :ai_search_semantic_rate_limit_per_minute,
        :ai_search_answer_rate_limit_per_minute
      )
      permitted[:workspace_limit_override] = nil if permitted[:workspace_limit_override].blank?
      permitted
    end
  end
end
