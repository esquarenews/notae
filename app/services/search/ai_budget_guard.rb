module Search
  class AiBudgetGuard
    class << self
      def within_daily_budget?(user:, workspace:)
        new(user: user, workspace: workspace).within_daily_budget?
      end
    end

    def initialize(user:, workspace:)
      @user = user
      @workspace = workspace
    end

    def within_daily_budget?
      return true if daily_budget_usd <= 0

      spent_today < daily_budget_usd
    end

    private

    attr_reader :user, :workspace

    def daily_budget_usd
      user.resolved_ai_search_daily_budget_usd
    end

    def spent_today
      now = Time.current
      start = now.beginning_of_day

      AiUsageLog.for_user_and_workspace(user: user, workspace: workspace)
               .for_day(start, now)
               .sum(:estimated_cost_usd)
               .to_f
    end
  end
end
