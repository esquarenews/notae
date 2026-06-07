module TenantLimits
  class Enforcer
    FEATURES = {
      members: :members,
      integrations: :integrations,
      exports: :exports_per_month,
      storage: :storage_mb,
      ai: :ai_requests_per_month
    }.freeze

    Result = Struct.new(:allowed?, :message, :feature, keyword_init: true)

    class << self
      def allowed?(workspace:, feature:)
        new(workspace: workspace).allowed?(feature)
      end

      def enforce!(workspace:, feature:)
        result = allowed?(workspace: workspace, feature: feature)
        return true if result.allowed?

        raise LimitExceeded, result.message
      end
    end

    class LimitExceeded < StandardError; end

    def initialize(workspace:)
      @workspace = workspace
    end

    def allowed?(feature)
      feature = feature.to_sym
      subscription = workspace.workspace_subscription
      return Result.new(allowed?: true, feature: feature, message: nil) if subscription.blank? || subscription.plan_key == WorkspaceSubscription::PLAN_FREE

      snapshot = Snapshot.new(workspace: workspace).call
      limit_key = FEATURES.fetch(feature)
      exceeded = snapshot.fetch(:exceeded)
      limits = snapshot.fetch(:limits)
      usage = snapshot.fetch(:usage)

      if feature == :ai
        return denial(feature, "AI usage has reached this plan's monthly cost allowance.") if exceeded.fetch(:ai_monthly_budget_usd)
        return denial(feature, message_for(feature)) if usage.fetch(:ai_requests_this_month) >= limits.fetch(:ai_requests_per_month)
      end

      return denial(feature, message_for(feature)) if incrementing_feature_at_limit?(feature, limits, usage)
      return denial(feature, message_for(feature)) if exceeded.fetch(limit_key)

      Result.new(allowed?: true, feature: feature, message: nil)
    end

    private

    attr_reader :workspace

    def denial(feature, message)
      Result.new(allowed?: false, feature: feature, message: message)
    end

    def message_for(feature)
      case feature
      when :members
        "This plan has reached its workspace member limit."
      when :integrations
        "This plan has reached its integration limit."
      when :exports
        "This plan has reached its monthly export limit."
      when :storage
        "This plan has reached its storage limit."
      when :ai
        "AI usage has reached this plan's monthly request limit."
      else
        "This plan limit has been reached."
      end
    end

    def incrementing_feature_at_limit?(feature, limits, usage)
      case feature
      when :members
        usage.fetch(:members) >= limits.fetch(:members)
      when :integrations
        usage.fetch(:integrations) >= limits.fetch(:integrations)
      when :exports
        usage.fetch(:exports_this_month) >= limits.fetch(:exports_per_month)
      when :storage
        usage.fetch(:storage_mb) >= limits.fetch(:storage_mb)
      else
        false
      end
    end
  end
end
