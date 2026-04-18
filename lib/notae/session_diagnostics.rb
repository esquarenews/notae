# frozen_string_literal: true

require "json"

module Notae
  module SessionDiagnostics
    EVENT_NAME = "notae.session.diagnostic"
    COOKIE_WARNING_BYTES = 3_000
    MAX_SESSION_KEYS = 12
    MAX_USER_AGENT_LENGTH = 180
    MAX_REFERER_LENGTH = 180

    module_function

    def cookie_store?
      Rails.application.config.session_options[:key].present? &&
        Rails.application.config.session_store == ActionDispatch::Session::CookieStore
    rescue StandardError
      false
    end

    def warning_threshold_bytes
      raw_value = ENV["NOTAE_SESSION_WARNING_BYTES"].to_s
      parsed = raw_value.to_i
      parsed.positive? ? parsed : COOKIE_WARNING_BYTES
    end

    def approximate_payload_bytes(session)
      JSON.generate(normalized_session_payload(session)).bytesize
    rescue JSON::GeneratorError, Encoding::UndefinedConversionError, TypeError
      0
    end

    def event_payload(request:, session:, current_user:, reason:, error: nil)
      payload = normalized_session_payload(session)

      {
        reason: reason.to_s,
        session_store: session_store_name,
        session_key: Rails.application.config.session_options[:key].to_s,
        approximate_session_bytes: approximate_payload_bytes(payload),
        session_key_count: payload.keys.size,
        session_keys: payload.keys.first(MAX_SESSION_KEYS),
        user_id: current_user&.id&.to_s,
        request_id: request.request_id.to_s,
        request_method: request.request_method.to_s,
        path: request.fullpath.to_s,
        referer: truncate(request.referer, MAX_REFERER_LENGTH),
        user_agent: truncate(request.user_agent, MAX_USER_AGENT_LENGTH),
        remote_ip: request.remote_ip.to_s.presence,
        error_class: error&.class&.name,
        error_message: truncate(error&.message, 220)
      }.compact
    end

    def normalized_session_payload(session)
      raw_hash =
        if session.respond_to?(:to_hash)
          session.to_hash
        elsif session.is_a?(Hash)
          session
        else
          {}
        end

      raw_hash.each_with_object({}) do |(key, value), normalized|
        next if key.to_s.start_with?("warden.user.")

        normalized[key.to_s] = summarize_value(value)
      end
    end

    def instrument!(payload)
      ActiveSupport::Notifications.instrument(EVENT_NAME, payload)
    end

    def session_store_name
      Rails.application.config.session_store.name.demodulize.underscore
    rescue StandardError
      Rails.application.config.session_store.to_s
    end

    def summarize_value(value)
      case value
      when String
        "string(#{value.bytesize})"
      when Numeric, TrueClass, FalseClass, NilClass
        value
      when Hash
        value.transform_keys(&:to_s).keys.first(MAX_SESSION_KEYS)
      when Array
        "array(#{value.size})"
      else
        value.class.name
      end
    end
    private_class_method :summarize_value

    def truncate(value, limit)
      text = value.to_s
      return if text.blank?
      return text if text.length <= limit

      "#{text.first(limit - 1)}…"
    end
    private_class_method :truncate
  end
end
