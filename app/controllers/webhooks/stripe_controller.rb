module Webhooks
  class StripeController < ActionController::API
    def create
      event = build_event
      processed_event = Billing::StripeWebhookProcessor.new(stripe_event: event).call
      render json: { status: processed_event.status }
    rescue JSON::ParserError, Stripe::SignatureVerificationError => error
      render json: { error: error.message }, status: :bad_request
    rescue StandardError => error
      Rails.logger.error("[StripeWebhook] #{error.class}: #{error.message}")
      render json: { error: "webhook_processing_failed" }, status: :unprocessable_entity
    end

    private

    def build_event
      raw_body = request.raw_post
      webhook_secret = Billing::StripeGateway.webhook_secret
      return JSON.parse(raw_body) if webhook_secret.blank?

      Stripe::Webhook.construct_event(
        raw_body,
        request.headers["Stripe-Signature"],
        webhook_secret
      )
    end
  end
end
