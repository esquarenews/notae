module Webhooks
  class FatZebraController < ActionController::API
    def create
      return head :service_unavailable if authentication_missing?
      return head :unauthorized unless authenticated?

      event = Billing::FatZebraWebhookProcessor.new(
        raw_body: request.raw_post,
        headers: request.headers.env,
        verified: authentication_configured?
      ).call

      render json: { status: event.status }, status: :ok
    rescue JSON::ParserError, KeyError
      render json: { error: "invalid_payload" }, status: :bad_request
    end

    private

    def authentication_missing?
      Billing::FatZebraGateway.webhook_authentication_required? && !authentication_configured?
    end

    def authenticated?
      return true unless authentication_configured?

      secure_compare(webhook_token, configured_secret)
    end

    def authentication_configured?
      configured_secret.present?
    end

    def configured_secret
      @configured_secret ||= Billing::FatZebraGateway.webhook_secret
    end

    def webhook_token
      params[:token].to_s.presence ||
        request.headers["X-Fat-Zebra-Webhook-Token"].to_s.presence ||
        request.authorization.to_s.delete_prefix("Bearer ").presence
    end

    def secure_compare(candidate, expected)
      return false if candidate.blank? || expected.blank?
      return false unless candidate.bytesize == expected.bytesize

      ActiveSupport::SecurityUtils.secure_compare(candidate, expected)
    end
  end
end
