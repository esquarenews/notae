require "digest"

module Billing
  class FatZebraWebhookProcessor
    SUPPORTED_EVENTS = %w[
      payment_plan:active
      payment_plan:activated
      payment_plan:completed
      payment_plan:suspended
      payment_plan:cancelled
      payment_plan:canceled
      payment_plan_payment:completed
      payment_plan_payment:declined
      payment_plan_payment:error
    ].freeze

    def initialize(raw_body:, headers:, verified:)
      @raw_body = raw_body.to_s
      @headers = headers
      @verified = verified
    end

    def call
      parsed_body = JSON.parse(raw_body)
      event_name = parsed_body.fetch("event").to_s
      payload = parsed_body.fetch("payload")
      provider_object_id = provider_object_id_for(event_name, payload)
      event = persist_event!(event_name: event_name, payload: payload, provider_object_id: provider_object_id)

      return event if event.processed? || event.ignored?

      if SUPPORTED_EVENTS.exclude?(event_name)
        event.update!(status: FatZebraWebhookEvent::STATUS_IGNORED, processed_at: Time.current)
        return event
      end

      process_event!(event, event_name, payload)
      return event if event.ignored?

      event.update!(status: FatZebraWebhookEvent::STATUS_PROCESSED, processed_at: Time.current, processing_error: nil)
      event
    rescue JSON::ParserError, KeyError => error
      persist_malformed_event!(error)
    end

    private

    attr_reader :raw_body, :headers, :verified

    def persist_event!(event_name:, payload:, provider_object_id:)
      FatZebraWebhookEvent.create!(
        event_name: event_name,
        provider_event_id: provider_event_id_for(event_name, payload),
        provider_object_id: provider_object_id,
        provider_object_type: provider_object_type_for(event_name),
        verified: verified,
        raw_body_sha256: raw_body_sha256,
        payload_json: payload,
        headers_json: sanitized_headers
      )
    rescue ActiveRecord::RecordNotUnique
      FatZebraWebhookEvent.find_by!(provider_event_id: provider_event_id_for(event_name, payload))
    rescue ActiveRecord::RecordInvalid => error
      raise unless error.record.errors[:provider_event_id].present?

      FatZebraWebhookEvent.find_by!(provider_event_id: provider_event_id_for(event_name, payload))
    end

    def persist_malformed_event!(error)
      FatZebraWebhookEvent.create!(
        event_name: "malformed",
        provider_event_id: "malformed:#{raw_body_sha256}",
        verified: verified,
        raw_body_sha256: raw_body_sha256,
        payload_json: {},
        headers_json: sanitized_headers,
        status: FatZebraWebhookEvent::STATUS_FAILED,
        processing_error: error.message,
        processed_at: Time.current
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      FatZebraWebhookEvent.find_by!(provider_event_id: "malformed:#{raw_body_sha256}")
    ensure
      raise error
    end

    def process_event!(event, event_name, payload)
      case event_name
      when /^payment_plan:/
        reconcile_payment_plan!(event, event_name, payload)
      when /^payment_plan_payment:/
        reconcile_payment_plan_payment!(event, event_name, payload)
      end
    end

    def reconcile_payment_plan!(event, event_name, payload)
      subscription = subscription_for_payment_plan(payload["id"], payload["customer"])
      return event.update!(status: FatZebraWebhookEvent::STATUS_IGNORED, processed_at: Time.current) unless subscription

      subscription.update!(
        status: subscription_status_for(event_name, payload["status"]),
        provider_customer_id: payload["customer"].presence || subscription.provider_customer_id,
        provider_subscription_id: payload["id"].presence || subscription.provider_subscription_id,
        current_period_ends_at: current_period_end_for(payload),
        metadata_json: subscription.metadata_json.to_h.merge("last_fat_zebra_event" => compact_payload_summary(event_name, payload))
      )
      record_admin_audit!(subscription, event, event_name, payload)
    end

    def reconcile_payment_plan_payment!(event, event_name, payload)
      subscription = subscription_for_payment_plan(payload["payment_plan"], nil)
      return event.update!(status: FatZebraWebhookEvent::STATUS_IGNORED, processed_at: Time.current) unless subscription

      subscription.update!(
        status: subscription_status_for(event_name, payload["status"]),
        current_period_ends_at: parse_date(payload["scheduled_date"]) || subscription.current_period_ends_at,
        metadata_json: subscription.metadata_json.to_h.merge("last_fat_zebra_payment_event" => compact_payload_summary(event_name, payload))
      )
      record_admin_audit!(subscription, event, event_name, payload)
    end

    def subscription_for_payment_plan(payment_plan_id, customer_id)
      relation = WorkspaceSubscription.where(billing_provider: WorkspaceSubscription::PROVIDER_FAT_ZEBRA)
      relation.find_by(provider_subscription_id: payment_plan_id) ||
        relation.find_by(provider_customer_id: customer_id)
    end

    def subscription_status_for(event_name, payload_status)
      normalized_status = payload_status.to_s.downcase

      case event_name
      when "payment_plan:active", "payment_plan:activated", "payment_plan_payment:completed"
        WorkspaceSubscription::STATUS_ACTIVE
      when "payment_plan:suspended", "payment_plan_payment:declined", "payment_plan_payment:error"
        WorkspaceSubscription::STATUS_PAST_DUE
      when "payment_plan:completed", "payment_plan:cancelled", "payment_plan:canceled"
        WorkspaceSubscription::STATUS_CANCELED
      else
        normalized_status == "active" ? WorkspaceSubscription::STATUS_ACTIVE : WorkspaceSubscription::STATUS_PAST_DUE
      end
    end

    def current_period_end_for(payload)
      next_scheduled_payment = Array(payload["payments"]).find { |payment| payment["scheduled_date"].present? }

      parse_date(next_scheduled_payment&.dig("scheduled_date")) || parse_date(payload["end_date"])
    end

    def parse_date(raw_value)
      return nil if raw_value.blank?

      Time.zone.parse(raw_value.to_s)
    rescue ArgumentError
      nil
    end

    def record_admin_audit!(subscription, event, event_name, payload)
      AdminAuditEvent.create!(
        actor: system_actor(subscription),
        workspace: subscription.workspace,
        target: subscription,
        action: "fat_zebra_webhook_processed",
        metadata_json: {
          fat_zebra_webhook_event_id: event.id,
          event: event_name,
          provider_object_id: event.provider_object_id,
          provider_status: payload["status"]
        }
      )
    end

    def system_actor(subscription)
      User.where(super_admin: true).order(:created_at).first ||
        subscription.workspace.memberships.includes(:user).order(:created_at).first&.user ||
        User.order(:created_at).first
    end

    def provider_event_id_for(event_name, payload)
      payload_digest_source = {
        event: event_name,
        object_id: provider_object_id_for(event_name, payload),
        raw_body_sha256: raw_body_sha256
      }.to_json

      Digest::SHA256.hexdigest(payload_digest_source)
    end

    def provider_object_id_for(event_name, payload)
      return nil unless payload.is_a?(Hash)

      if event_name.start_with?("payment_plan_payment:")
        payload["id"].presence || payload["payment_plan"].presence
      else
        payload["id"].presence
      end
    end

    def provider_object_type_for(event_name)
      event_name.to_s.split(":").first
    end

    def compact_payload_summary(event_name, payload)
      {
        "event" => event_name,
        "id" => payload["id"],
        "customer" => payload["customer"],
        "payment_plan" => payload["payment_plan"],
        "reference" => payload["reference"],
        "status" => payload["status"],
        "result" => payload["result"],
        "processed_at" => Time.current.iso8601
      }.compact
    end

    def raw_body_sha256
      @raw_body_sha256 ||= Digest::SHA256.hexdigest(raw_body)
    end

    def sanitized_headers
      headers.each_with_object({}) do |(key, value), result|
        next unless key.to_s.start_with?("HTTP_") || %w[CONTENT_TYPE CONTENT_LENGTH].include?(key.to_s)

        result[key.to_s] = key.to_s.match?(/AUTHORIZATION|TOKEN|SECRET|SIGNATURE/) ? "[FILTERED]" : value.to_s
      end
    end
  end
end
