module Admin
  class UsersController < BaseController
    before_action :set_user, only: %i[show update archive resend_confirmation suspend remove reinstate]

    def index
      @user_filter = Admin::UserAccountFilter.normalize(params[:filter])
      @users = Admin::UserAccountFilter.new(filter: @user_filter).call
               .includes(memberships: { workspace: :workspace_subscription })
               .order(created_at: :desc)
               .limit(100)
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

    def archive
      if @user == current_user
        return redirect_to archive_redirect_path, alert: "You cannot archive your own admin account."
      end
      if @user.platform_admin?
        return redirect_to archive_redirect_path, alert: "Platform admin accounts cannot be archived from the list."
      end

      @user.remove_account!

      record_admin_audit!(
        action: "user_archived",
        target: @user,
        metadata: { removed_at: @user.removed_at&.iso8601 }
      )

      redirect_to archive_redirect_path, notice: "User archived and deactivated."
    end

    def resend_confirmation
      if @user.confirmed?
        return redirect_to user_action_redirect_path, alert: "This user has already confirmed their email address."
      end

      @user.resend_confirmation_instructions

      record_admin_audit!(
        action: "user_confirmation_resent",
        target: @user,
        metadata: { confirmation_sent_at: @user.confirmation_sent_at&.iso8601 }
      )

      redirect_to user_action_redirect_path, notice: "Confirmation email resent."
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

    def archive_redirect_path
      user_action_redirect_path
    end

    def user_action_redirect_path
      filter = Admin::UserAccountFilter.normalize(params[:filter])
      return admin_root_path(filter: filter) if params[:return_to] == "dashboard"

      admin_users_path(filter: filter)
    end

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
