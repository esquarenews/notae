module Billing
  class CheckoutController < ApplicationController
    before_action :authenticate_user!
    skip_after_action :verify_pundit_authorization

    def success
      session_id = params[:session_id].to_s
      return redirect_to root_path, alert: "Stripe checkout session is missing." if session_id.blank?

      stripe_session = Stripe::Checkout::Session.retrieve(session_id)
      event_payload = {
        "id" => "checkout-success:#{stripe_session.id}",
        "type" => "checkout.session.completed",
        "data" => { "object" => stripe_session.as_json }
      }
      event = Billing::StripeWebhookProcessor.new(stripe_event: event_payload).call
      subscription = subscription_from_event(event) || subscription_from_session(stripe_session)

      if subscription&.workspace&.users&.exists?(current_user.id)
        redirect_to workspace_path(subscription.workspace.slug), notice: "Your Notae trial is ready."
      else
        redirect_to root_path, notice: "Checkout completed. Your workspace will be available shortly."
      end
    rescue Billing::StripeGateway::ConfigurationError => error
      redirect_to root_path, alert: error.message
    rescue Stripe::StripeError => error
      redirect_to root_path, alert: "Stripe checkout could not be verified: #{error.message}"
    end

    def cancel
      redirect_to new_workspace_path(plan: params[:plan]), alert: "Checkout was cancelled. Choose a plan to start your trial."
    end

    private

    def subscription_from_event(event)
      return nil if event.blank?

      WorkspaceSubscription.find_by(id: event.payload_json.dig("data", "object", "metadata", "workspace_subscription_id").to_s)
    end

    def subscription_from_session(stripe_session)
      WorkspaceSubscription.find_by(id: stripe_session.as_json.dig("metadata", "workspace_subscription_id").to_s)
    end
  end
end
