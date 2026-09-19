module Search
  class AiUsageLogger
    class << self
      def log!(user:, workspace:, operation:, model:, usage:, metadata: {})
        return if usage.blank?

        prompt_tokens = usage.fetch(:prompt_tokens, 0).to_i
        completion_tokens = usage.fetch(:completion_tokens, 0).to_i
        total_tokens = usage.fetch(:total_tokens, prompt_tokens + completion_tokens).to_i
        cached_prompt_tokens = usage.fetch(:cached_prompt_tokens, 0).to_i
        cache_write_tokens = usage.fetch(:cache_write_tokens, 0).to_i
        web_search_calls = usage.fetch(:web_search_calls, 0).to_i
        audio_minutes = usage.fetch(:audio_minutes, 0).to_f
        service_tier = usage[:service_tier].to_s.presence
        estimated_cost_usd = Openai::CostEstimator.estimate(
          model: model,
          prompt_tokens: prompt_tokens,
          completion_tokens: completion_tokens,
          cached_prompt_tokens: cached_prompt_tokens,
          cache_write_tokens: cache_write_tokens,
          web_search_calls: web_search_calls,
          audio_minutes: audio_minutes,
          service_tier: service_tier
        )
        enriched_metadata = (metadata || {}).to_h.merge(
          usage_details: {
            cached_prompt_tokens: cached_prompt_tokens,
            cache_write_tokens: cache_write_tokens,
            web_search_calls: web_search_calls,
            audio_minutes: audio_minutes,
            service_tier: service_tier
          }.compact
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
          metadata: enriched_metadata
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
