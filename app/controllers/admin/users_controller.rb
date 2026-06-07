module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[show update suspend remove reinstate]

    def index
      @users = User.includes(:memberships).order(created_at: :desc).limit(100)
    end

    def show
      @usage_summary = Admin::UserUsageSummary.new(users: [ @user ]).call.fetch(@user)
      @api_tokens = @user.api_tokens.order(created_at: :desc).limit(12)
      @recent_admin_events = AdminAuditEvent.where(actor: @user).recent_first.limit(12)
    end

    def update
      @user.assign_attributes(user_params)
      @user.save!

      record_admin_audit!(
        action: "user_limits_updated",
        target: @user,
        metadata: user_params.to_h
      )

      redirect_to admin_user_path(@user), notice: "User plan and limits updated."
    end

    def suspend
      @user.suspend_for_week!

      record_admin_audit!(
        action: "user_suspended",
        target: @user,
        metadata: { suspended_until: @user.admin_suspended_until&.iso8601 }
      )

      redirect_to admin_user_path(@user), notice: "User suspended for one week."
    end

    def remove
      @user.remove_account!

      record_admin_audit!(
        action: "user_removed",
        target: @user,
        metadata: { removed_at: @user.removed_at&.iso8601 }
      )

      redirect_to admin_user_path(@user), notice: "User account cancelled. Data has been retained."
    end

    def reinstate
      unless @user.removed?
        return redirect_to admin_user_path(@user), alert: "Only removed users can be reinstated."
      end

      @user.reinstate_free_tier_for_week!

      record_admin_audit!(
        action: "user_reinstated",
        target: @user,
        metadata: {
          saas_plan_key: @user.saas_plan_key,
          free_tier_ends_at: @user.admin_free_tier_ends_at&.iso8601
        }
      )

      redirect_to admin_user_path(@user), notice: "User reinstated on the Free tier for one week."
    end

    private

    def set_user
      @user = User.includes(memberships: :workspace).find(params[:id])
    end

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
