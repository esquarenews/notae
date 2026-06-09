module Admin
  class UsersController < BaseController
    USER_FILTERS = %w[all trial paid suspended archived].freeze

    before_action :set_user, only: %i[show update archive suspend remove reinstate]

    def index
      @user_filter = normalized_user_filter
      @users = filtered_users_scope
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
        return redirect_to admin_users_path(filter: params[:filter].presence || "all"), alert: "You cannot archive your own admin account."
      end
      if @user.platform_admin?
        return redirect_to admin_users_path(filter: params[:filter].presence || "all"), alert: "Platform admin accounts cannot be archived from the list."
      end

      @user.remove_account!

      record_admin_audit!(
        action: "user_archived",
        target: @user,
        metadata: { removed_at: @user.removed_at&.iso8601 }
      )

      redirect_to admin_users_path(filter: params[:filter].presence || "all"), notice: "User archived and deactivated."
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

    def normalized_user_filter
      requested = params[:filter].to_s
      USER_FILTERS.include?(requested) ? requested : "all"
    end

    def filtered_users_scope
      scope = User.all

      case @user_filter
      when "trial"
        unarchived_users(scope).where(id: trial_user_ids)
      when "paid"
        unarchived_scope = unarchived_users(scope)
        unarchived_scope
          .where(saas_plan_key: paid_plan_keys)
          .or(unarchived_scope.where(id: paid_user_ids))
      when "suspended"
        unarchived_scope = unarchived_users(scope)
        unarchived_scope
          .where("admin_suspended_until > ?", Time.current)
          .or(unarchived_scope.where(id: workspace_suspended_user_ids))
      when "archived"
        scope.where.not(removed_at: nil).or(scope.where(id: canceled_user_ids))
      else
        unarchived_users(scope)
      end
    end

    def unarchived_users(scope)
      scope.where(removed_at: nil).where.not(id: canceled_user_ids)
    end

    def trial_user_ids
      user_ids_for_subscription_statuses([ WorkspaceSubscription::STATUS_TRIALING ])
    end

    def paid_user_ids
      user_ids_for_subscription_statuses([ WorkspaceSubscription::STATUS_ACTIVE ], paid_only: true)
    end

    def paid_plan_keys
      [ User::SAAS_PLAN_STARTER, User::SAAS_PLAN_TEAM, User::SAAS_PLAN_BUSINESS ]
    end

    def workspace_suspended_user_ids
      user_ids_for_subscription_statuses([ WorkspaceSubscription::STATUS_SUSPENDED ])
    end

    def canceled_user_ids
      user_ids_for_subscription_statuses([ WorkspaceSubscription::STATUS_CANCELED ])
    end

    def user_ids_for_subscription_statuses(statuses, paid_only: false)
      scope = Membership.joins(workspace: :workspace_subscription)
                        .where(workspace_subscriptions: { status: statuses })
      if paid_only
        scope = scope.where(workspace_subscriptions: {
          plan_key: [
            WorkspaceSubscription::PLAN_STARTER,
            WorkspaceSubscription::PLAN_TEAM,
            WorkspaceSubscription::PLAN_BUSINESS
          ]
        })
      end

      scope.select(:user_id)
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
