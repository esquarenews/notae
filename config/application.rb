require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Notae
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])
    config.autoload_paths << Rails.root.join("app/services")
    config.autoload_paths << Rails.root.join("app/channels")
    config.eager_load_paths << Rails.root.join("app/services")
    config.eager_load_paths << Rails.root.join("app/channels")
    config.x.api.rate_limit_per_minute = ENV.fetch("API_RATE_LIMIT_PER_MINUTE", "120").to_i
    config.x.api.rate_limit_window_seconds = ENV.fetch("API_RATE_LIMIT_WINDOW_SECONDS", "60").to_i
    config.x.ai_search.semantic_rate_limit_per_minute = ENV.fetch("AI_SEARCH_SEMANTIC_RATE_LIMIT_PER_MINUTE", "24").to_i
    config.x.ai_search.answer_rate_limit_per_minute = ENV.fetch("AI_SEARCH_ANSWER_RATE_LIMIT_PER_MINUTE", "12").to_i
    config.x.ai_search.rate_limit_window_seconds = ENV.fetch("AI_SEARCH_RATE_LIMIT_WINDOW_SECONDS", "60").to_i
    config.x.ai_search.daily_budget_usd = ENV.fetch("AI_SEARCH_DAILY_BUDGET_USD", "1.50").to_f
    config.x.ai_pricing.embedding_3_small_input_per_1k = ENV.fetch("OPENAI_PRICE_TEXT_EMBEDDING_3_SMALL_INPUT_PER_1K", "0.00002").to_f
    config.x.ai_pricing.gpt_4o_mini_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_4O_MINI_INPUT_PER_1K", "0.00015").to_f
    config.x.ai_pricing.gpt_4o_mini_cached_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_4O_MINI_CACHED_INPUT_PER_1K", "0.000075").to_f
    config.x.ai_pricing.gpt_4o_mini_output_per_1k = ENV.fetch("OPENAI_PRICE_GPT_4O_MINI_OUTPUT_PER_1K", "0.00060").to_f
    config.x.ai_pricing.gpt_4_1_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_4_1_INPUT_PER_1K", "0.00200").to_f
    config.x.ai_pricing.gpt_4_1_cached_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_4_1_CACHED_INPUT_PER_1K", "0.00050").to_f
    config.x.ai_pricing.gpt_4_1_output_per_1k = ENV.fetch("OPENAI_PRICE_GPT_4_1_OUTPUT_PER_1K", "0.00800").to_f
    config.x.ai_pricing.gpt_4_1_mini_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_4_1_MINI_INPUT_PER_1K", "0.00040").to_f
    config.x.ai_pricing.gpt_4_1_mini_cached_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_4_1_MINI_CACHED_INPUT_PER_1K", "0.00010").to_f
    config.x.ai_pricing.gpt_4_1_mini_output_per_1k = ENV.fetch("OPENAI_PRICE_GPT_4_1_MINI_OUTPUT_PER_1K", "0.00160").to_f
    config.x.ai_pricing.gpt_5_6_sol_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_5_6_SOL_INPUT_PER_1K", "0.00500").to_f
    config.x.ai_pricing.gpt_5_6_sol_cached_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_5_6_SOL_CACHED_INPUT_PER_1K", "0.00050").to_f
    config.x.ai_pricing.gpt_5_6_sol_output_per_1k = ENV.fetch("OPENAI_PRICE_GPT_5_6_SOL_OUTPUT_PER_1K", "0.03000").to_f
    config.x.ai_pricing.gpt_5_6_terra_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_5_6_TERRA_INPUT_PER_1K", "0.00200").to_f
    config.x.ai_pricing.gpt_5_6_terra_cached_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_5_6_TERRA_CACHED_INPUT_PER_1K", "0.00020").to_f
    config.x.ai_pricing.gpt_5_6_terra_output_per_1k = ENV.fetch("OPENAI_PRICE_GPT_5_6_TERRA_OUTPUT_PER_1K", "0.01200").to_f
    config.x.ai_pricing.gpt_5_6_luna_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_5_6_LUNA_INPUT_PER_1K", "0.00020").to_f
    config.x.ai_pricing.gpt_5_6_luna_cached_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_5_6_LUNA_CACHED_INPUT_PER_1K", "0.00002").to_f
    config.x.ai_pricing.gpt_5_6_luna_output_per_1k = ENV.fetch("OPENAI_PRICE_GPT_5_6_LUNA_OUTPUT_PER_1K", "0.00120").to_f
    config.x.ai_pricing.web_search_per_call = ENV.fetch("OPENAI_PRICE_WEB_SEARCH_PER_CALL", "0.01000").to_f
    config.x.ai_pricing.gpt_4o_transcribe_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_4O_TRANSCRIBE_INPUT_PER_1K", "0.00250").to_f
    config.x.ai_pricing.gpt_4o_transcribe_output_per_1k = ENV.fetch("OPENAI_PRICE_GPT_4O_TRANSCRIBE_OUTPUT_PER_1K", "0.01000").to_f
    config.x.ai_pricing.gpt_4o_mini_transcribe_input_per_1k = ENV.fetch("OPENAI_PRICE_GPT_4O_MINI_TRANSCRIBE_INPUT_PER_1K", "0.00125").to_f
    config.x.ai_pricing.gpt_4o_mini_transcribe_output_per_1k = ENV.fetch("OPENAI_PRICE_GPT_4O_MINI_TRANSCRIBE_OUTPUT_PER_1K", "0.00500").to_f
    config.x.ai_pricing.gpt_transcribe_per_minute = ENV.fetch("OPENAI_PRICE_GPT_TRANSCRIBE_PER_MINUTE", "0.00450").to_f
    config.x.ai_pricing.gpt_4o_transcribe_per_minute = ENV.fetch("OPENAI_PRICE_GPT_4O_TRANSCRIBE_PER_MINUTE", "0.00600").to_f
    config.x.ai_pricing.gpt_4o_mini_transcribe_per_minute = ENV.fetch("OPENAI_PRICE_GPT_4O_MINI_TRANSCRIBE_PER_MINUTE", "0.00300").to_f
    config.x.ai_pricing.whisper_per_minute = ENV.fetch("OPENAI_PRICE_WHISPER_PER_MINUTE", "0.00600").to_f
    config.action_dispatch.default_headers.merge!(
      "X-Frame-Options" => "SAMEORIGIN",
      "X-Content-Type-Options" => "nosniff",
      "Referrer-Policy" => "strict-origin-when-cross-origin",
      "Permissions-Policy" => "accelerometer=(), ambient-light-sensor=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(self), payment=(), usb=()",
      "X-Permitted-Cross-Domain-Policies" => "none",
      "Cross-Origin-Opener-Policy" => "same-origin",
      "Cross-Origin-Resource-Policy" => "same-origin"
    )

    config.generators do |generate|
      generate.orm :active_record, primary_key_type: :uuid
      generate.test_framework :rspec, fixture: false
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
