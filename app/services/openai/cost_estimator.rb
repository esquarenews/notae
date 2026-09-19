module Openai
  class CostEstimator
    class << self
      def estimate(
        model:,
        prompt_tokens:,
        completion_tokens:,
        cached_prompt_tokens: 0,
        cache_write_tokens: 0,
        web_search_calls: 0,
        audio_minutes: 0,
        service_tier: nil
      )
        normalized_prompt_tokens = prompt_tokens.to_i.clamp(0, Float::INFINITY)
        normalized_cached_tokens = cached_prompt_tokens.to_i.clamp(0, normalized_prompt_tokens)
        remaining_prompt_tokens = normalized_prompt_tokens - normalized_cached_tokens
        normalized_cache_write_tokens = cache_write_tokens.to_i.clamp(0, remaining_prompt_tokens)
        uncached_prompt_tokens = remaining_prompt_tokens - normalized_cache_write_tokens
        input_rate, cached_input_rate, output_rate = rates_for(model)
        multiplier = service_tier_multiplier(model: model, service_tier: service_tier)
        input_context_multiplier, output_context_multiplier = context_multipliers(
          model: model,
          prompt_tokens: normalized_prompt_tokens
        )

        prompt_total = (uncached_prompt_tokens / 1000.0) * input_rate * multiplier * input_context_multiplier
        cached_total = (normalized_cached_tokens / 1000.0) * cached_input_rate * multiplier * input_context_multiplier
        cache_write_total = (normalized_cache_write_tokens / 1000.0) * input_rate * 1.25 * multiplier * input_context_multiplier
        completion_total = (completion_tokens.to_i / 1000.0) * output_rate * multiplier * output_context_multiplier
        tool_total = web_search_calls.to_i.clamp(0, Float::INFINITY) * pricing.web_search_per_call.to_f
        audio_total = audio_fallback_cost(
          model: model,
          prompt_tokens: normalized_prompt_tokens,
          completion_tokens: completion_tokens,
          audio_minutes: audio_minutes
        )

        (prompt_total + cached_total + cache_write_total + completion_total + tool_total + audio_total).round(6)
      end

      private

      def rates_for(model)
        case model.to_s
        when "text-embedding-3-small"
          [
            pricing.embedding_3_small_input_per_1k.to_f,
            pricing.embedding_3_small_input_per_1k.to_f,
            0.0
          ]
        when "gpt-4o-mini"
          [
            pricing.gpt_4o_mini_input_per_1k.to_f,
            pricing.gpt_4o_mini_cached_input_per_1k.to_f,
            pricing.gpt_4o_mini_output_per_1k.to_f
          ]
        when "gpt-4.1-mini"
          [
            pricing.gpt_4_1_mini_input_per_1k.to_f,
            pricing.gpt_4_1_mini_cached_input_per_1k.to_f,
            pricing.gpt_4_1_mini_output_per_1k.to_f
          ]
        when "gpt-4.1"
          [
            pricing.gpt_4_1_input_per_1k.to_f,
            pricing.gpt_4_1_cached_input_per_1k.to_f,
            pricing.gpt_4_1_output_per_1k.to_f
          ]
        when "gpt-5.6", "gpt-5.6-sol"
          [
            pricing.gpt_5_6_sol_input_per_1k.to_f,
            pricing.gpt_5_6_sol_cached_input_per_1k.to_f,
            pricing.gpt_5_6_sol_output_per_1k.to_f
          ]
        when "gpt-5.6-terra"
          [
            pricing.gpt_5_6_terra_input_per_1k.to_f,
            pricing.gpt_5_6_terra_cached_input_per_1k.to_f,
            pricing.gpt_5_6_terra_output_per_1k.to_f
          ]
        when "gpt-5.6-luna"
          [
            pricing.gpt_5_6_luna_input_per_1k.to_f,
            pricing.gpt_5_6_luna_cached_input_per_1k.to_f,
            pricing.gpt_5_6_luna_output_per_1k.to_f
          ]
        when "gpt-4o-transcribe", "gpt-4o-transcribe-diarize"
          [
            pricing.gpt_4o_transcribe_input_per_1k.to_f,
            pricing.gpt_4o_transcribe_input_per_1k.to_f,
            pricing.gpt_4o_transcribe_output_per_1k.to_f
          ]
        when "gpt-4o-mini-transcribe"
          [
            pricing.gpt_4o_mini_transcribe_input_per_1k.to_f,
            pricing.gpt_4o_mini_transcribe_input_per_1k.to_f,
            pricing.gpt_4o_mini_transcribe_output_per_1k.to_f
          ]
        else
          [ 0.0, 0.0, 0.0 ]
        end
      end

      def service_tier_multiplier(model:, service_tier:)
        return 1.0 unless model.to_s.start_with?("gpt-5.6")

        case service_tier.to_s
        when "flex" then 0.5
        when "fast", "priority" then 2.0
        else 1.0
        end
      end

      def context_multipliers(model:, prompt_tokens:)
        return [ 1.0, 1.0 ] unless model.to_s.start_with?("gpt-5.6")
        return [ 1.0, 1.0 ] unless prompt_tokens.to_i > 272_000

        [ 2.0, 1.5 ]
      end

      def audio_fallback_cost(model:, prompt_tokens:, completion_tokens:, audio_minutes:)
        return 0.0 if prompt_tokens.positive? || completion_tokens.to_i.positive?

        minutes = audio_minutes.to_f
        return 0.0 unless minutes.positive?

        rate =
          case model.to_s
          when "gpt-transcribe" then pricing.gpt_transcribe_per_minute.to_f
          when "gpt-4o-transcribe", "gpt-4o-transcribe-diarize" then pricing.gpt_4o_transcribe_per_minute.to_f
          when "gpt-4o-mini-transcribe" then pricing.gpt_4o_mini_transcribe_per_minute.to_f
          when "whisper-1" then pricing.whisper_per_minute.to_f
          else 0.0
          end

        minutes * rate
      end

      def pricing
        Rails.application.config.x.ai_pricing
      end
    end
  end
end
