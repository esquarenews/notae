module Openai
  class CostEstimator
    class << self
      def estimate(model:, prompt_tokens:, completion_tokens:)
        input_rate, output_rate = rates_for(model)
        prompt_total = (prompt_tokens.to_i / 1000.0) * input_rate
        completion_total = (completion_tokens.to_i / 1000.0) * output_rate

        (prompt_total + completion_total).round(6)
      end

      private

      def rates_for(model)
        case model.to_s
        when "text-embedding-3-small"
          [
            Rails.application.config.x.ai_pricing.embedding_3_small_input_per_1k.to_f,
            0.0
          ]
        when "gpt-4o-mini"
          [
            Rails.application.config.x.ai_pricing.gpt_4o_mini_input_per_1k.to_f,
            Rails.application.config.x.ai_pricing.gpt_4o_mini_output_per_1k.to_f
          ]
        when "gpt-4.1-mini"
          [
            Rails.application.config.x.ai_pricing.gpt_4_1_mini_input_per_1k.to_f,
            Rails.application.config.x.ai_pricing.gpt_4_1_mini_output_per_1k.to_f
          ]
        else
          [ 0.0, 0.0 ]
        end
      end
    end
  end
end
