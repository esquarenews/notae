module Billing
  class StripeWebhookProcessor
    SUPPORTED_EVENTS = %w[
      checkout.session.completed
      customer.subscription.created
      customer.subscription.updated
      customer.subscription.deleted
      invoice.paid
      invoice.payment_succeeded
      invoice.payment_failed
    ].freeze

    def initialize(stripe_event:)
      @stripe_event = stripe_event
    end

    def call
      event = persist_event!
      return event if event.processed?
      return ignore!(event) unless SUPPORTED_EVENTS.include?(event.event_name)

      process!(event)
      event.update!(status: StripeWebhookEvent::STATUS_PROCESSED, processed_at: Time.current, processing_error: nil)
      event
    rescue ActiveRecord::RecordNotUnique
      StripeWebhookEvent.find_by!(provider_event_id: provider_event_id)
    rescue StandardError => error
      event = StripeWebhookEvent.find_by(provider_event_id: provider_event_id)
      event&.update!(status: StripeWebhookEvent::STATUS_FAILED, processing_error: error.message)
      raise
    end

    private

    attr_reader :stripe_event

    def persist_event!
      StripeWebhookEvent.create!(
        provider_event_id: provider_event_id,
        event_name: event_name,
        provider_object_type: object_payload["object"].to_s.presence,
        provider_object_id: object_payload["id"].to_s.presence,
        payload_json: stripe_event.as_json,
        status: StripeWebhookEvent::STATUS_RECEIVED
      )
    rescue ActiveRecord::RecordInvalid
      StripeWebhookEvent.find_by!(provider_event_id: provider_event_id)
    end

    def ignore!(event)
      event.update!(status: StripeWebhookEvent::STATUS_IGNORED, processed_at: Time.current)
      event
    end

    def process!(event)
      case event.event_name
      when "checkout.session.completed"
        process_checkout_completed!(event)
      when "customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted"
        process_subscription_event!(event, object_payload)
      when "invoice.paid", "invoice.payment_succeeded"
        process_invoice_event!(event, WorkspaceSubscription::STATUS_ACTIVE)
      when "invoice.payment_failed"
        process_invoice_event!(event, WorkspaceSubscription::STATUS_PAST_DUE)
      end
    end

    def process_checkout_completed!(event)
      session = object_payload
      subscription = subscription_from_metadata(session) ||
        WorkspaceSubscription.find_by(provider_subscription_id: session["subscription"].to_s)
      return ignore!(event) if subscription.blank?

      stripe_subscription = retrieve_subscription(session["subscription"])
      apply_subscription_payload!(
        event: event,
        subscription: subscription,
        stripe_subscription: stripe_subscription,
        customer_id: session["customer"].to_s.presence,
        subscription_id: session["subscription"].to_s.presence
      )
    end

    def process_subscription_event!(event, stripe_subscription)
      subscription = subscription_from_metadata(stripe_subscription) ||
        WorkspaceSubscription.find_by(provider_subscription_id: stripe_subscription["id"].to_s)
      return ignore!(event) if subscription.blank?

      apply_subscription_payload!(
        event: event,
        subscription: subscription,
        stripe_subscription: stripe_subscription,
        customer_id: stripe_subscription["customer"].to_s.presence,
        subscription_id: stripe_subscription["id"].to_s.presence
      )
    end

    def process_invoice_event!(event, status)
      invoice = object_payload
      stripe_subscription_id = invoice["subscription"].to_s.presence ||
        invoice.dig("parent", "subscription_details", "subscription").to_s.presence
      subscription = WorkspaceSubscription.find_by(provider_subscription_id: stripe_subscription_id)
      return ignore!(event) if subscription.blank?

      subscription.update!(
        status: status,
        metadata_json: subscription.metadata_json.to_h.merge("last_stripe_invoice_event" => compact_summary(event))
      )
      record_admin_audit!(event, subscription)
    end

    def apply_subscription_payload!(event:, subscription:, stripe_subscription:, customer_id:, subscription_id:)
      subscription.update!(
        billing_provider: WorkspaceSubscription::PROVIDER_STRIPE,
        provider_customer_id: customer_id.presence || subscription.provider_customer_id,
        provider_subscription_id: subscription_id.presence || subscription.provider_subscription_id,
        status: status_for(stripe_subscription["status"]),
        trial_ends_at: timestamp_to_time(stripe_subscription["trial_end"]) || subscription.trial_ends_at,
        current_period_ends_at: timestamp_to_time(stripe_subscription["current_period_end"]) || subscription.current_period_ends_at,
        metadata_json: subscription.metadata_json.to_h.merge("last_stripe_event" => compact_summary(event))
      )
      record_admin_audit!(event, subscription)
    end

    def retrieve_subscription(subscription_id)
      return {} if subscription_id.blank?

      Stripe::Subscription.retrieve(subscription_id).as_json
    rescue StandardError
      {}
    end

    def subscription_from_metadata(payload)
      id = payload.dig("metadata", "workspace_subscription_id").to_s.presence
      WorkspaceSubscription.find_by(id: id)
    end

    def record_admin_audit!(event, subscription)
      actor = subscription.workspace.memberships.where(role: Membership.roles[:owner]).includes(:user).first&.user || User.first
      return if actor.blank?

      AdminAuditEvent.create!(
        actor: actor,
        workspace: subscription.workspace,
        target: subscription,
        action: "stripe_webhook_processed",
        metadata_json: {
          stripe_webhook_event_id: event.id,
          event_name: event.event_name,
          provider_object_id: event.provider_object_id
        }
      )
    end

    def status_for(stripe_status)
      case stripe_status.to_s
      when "trialing"
        WorkspaceSubscription::STATUS_TRIALING
      when "active"
        WorkspaceSubscription::STATUS_ACTIVE
      when "past_due", "unpaid"
        WorkspaceSubscription::STATUS_PAST_DUE
      when "canceled", "incomplete_expired"
        WorkspaceSubscription::STATUS_CANCELED
      when "paused"
        WorkspaceSubscription::STATUS_SUSPENDED
      else
        WorkspaceSubscription::STATUS_INCOMPLETE
      end
    end

    def timestamp_to_time(value)
      integer = value.to_i
      return nil unless integer.positive?

      Time.zone.at(integer)
    end

    def compact_summary(event)
      {
        "event_id" => event.provider_event_id,
        "event_name" => event.event_name,
        "provider_object_id" => event.provider_object_id,
        "processed_at" => Time.current.iso8601
      }
    end

    def object_payload
      @object_payload ||= stripe_event.dig("data", "object").to_h
    end

    def event_name
      stripe_event["type"].to_s
    end

    def provider_event_id
      stripe_event["id"].to_s.presence || "stripe-event-#{Digest::SHA256.hexdigest(stripe_event.to_json)}"
    end
  end
end
