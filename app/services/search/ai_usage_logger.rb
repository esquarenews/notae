module Search
  class AiUsageLogger
    class << self
      def log!(user:, workspace:, operation:, model:, usage:, metadata: {})
        return if usage.blank?

        prompt_tokens = usage.fetch(:prompt_tokens, 0).to_i
        completion_tokens = usage.fetch(:completion_tokens, 0).to_i
        total_tokens = usage.fetch(:total_tokens, prompt_tokens + completion_tokens).to_i
        estimated_cost_usd = Openai::CostEstimator.estimate(
          model: model,
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens
        )

        create_log!(
          user: user,
          workspace: workspace,
          operation: operation,
          model: model,
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens,
          total_tokens: total_tokens,
          estimated_cost_usd: estimated_cost_usd,
          metadata: metadata || {}
        )
      end

      def log_outcome!(user:, workspace:, operation:, model:, metadata: {})
        create_log!(
          user: user,
          workspace: workspace,
          operation: operation,
          model: model,
          prompt_tokens: 0,
          completion_tokens: 0,
          total_tokens: 0,
          estimated_cost_usd: 0,
          metadata: metadata || {}
        )
      end

      private

      def create_log!(user:, workspace:, operation:, model:, prompt_tokens:, completion_tokens:, total_tokens:, estimated_cost_usd:, metadata:)
        AiUsageLog.create!(
          user: user,
          workspace: workspace,
          operation: operation,
          model: model,
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens,
          total_tokens: total_tokens,
          estimated_cost_usd: estimated_cost_usd,
          metadata: metadata
        )
      end
    end
  end
end
