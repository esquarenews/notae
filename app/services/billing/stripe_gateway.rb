module Billing
  class StripeGateway
    class ConfigurationError < StandardError; end

    TRIAL_PERIOD_DAYS = 7

    class << self
      def display_name
        "Stripe"
      end

      def configured?
        secret_key.present? && public_plan_price_ids_configured?
      end

      def configuration_status
        missing = []
        missing << "STRIPE_SECRET_KEY" if secret_key.blank?
        PlanCatalog.public_plan_keys.each do |plan_key|
          env_key = PlanCatalog.stripe_price_env_for(plan_key)
          missing << env_key if env_key.present? && PlanCatalog.stripe_price_id_for(plan_key).blank?
        end

        {
          configured: missing.empty?,
          missing: missing,
          message: missing.empty? ? "Stripe is configured." : "Stripe billing setup is incomplete. Ask a platform admin to finish configuring Stripe before using self-serve billing."
        }
      rescue StandardError => error
        {
          configured: false,
          missing: [],
          message: "Stripe configuration could not be checked: #{error.message}"
        }
      end

      def secret_key
        ENV["STRIPE_SECRET_KEY"].to_s.strip
      end

      def publishable_key
        ENV["STRIPE_PUBLISHABLE_KEY"].to_s.strip
      end

      def webhook_secret
        ENV["STRIPE_WEBHOOK_SECRET"].to_s.strip
      end

      def webhook_configured?
        webhook_secret.present?
      end

      def price_id_for!(plan_key)
        plan_key = plan_key.to_s
        raise ConfigurationError, "Free plans do not use Stripe Checkout." unless PlanCatalog.public_plan_keys.include?(plan_key)

        price_id = PlanCatalog.stripe_price_id_for(plan_key)
        return price_id if price_id.present?

        env_key = PlanCatalog.stripe_price_env_for(plan_key)
        raise ConfigurationError, "#{env_key} is not configured."
      end

      def public_plan_price_ids_configured?
        PlanCatalog.public_plan_keys.all? { |plan_key| PlanCatalog.stripe_price_id_for(plan_key).present? }
      end
    end

    def initialize(subscription:, user:)
      @subscription = subscription
      @workspace = subscription.workspace
      @user = user
    end

    def create_checkout_session!(success_url:, cancel_url:)
      require_configured!

      Stripe::Checkout::Session.create(
        mode: "subscription",
        customer_email: user.email,
        client_reference_id: workspace.id,
        payment_method_collection: "always",
        success_url: success_url,
        cancel_url: cancel_url,
        line_items: [
          {
            price: self.class.price_id_for!(subscription.plan_key),
            quantity: 1
          }
        ],
        subscription_data: {
          trial_period_days: TRIAL_PERIOD_DAYS,
          metadata: metadata
        },
        metadata: metadata
      )
    end

    def create_portal_session!(return_url:)
      require_secret_key!
      raise ConfigurationError, "This workspace does not have a Stripe customer yet." if subscription.provider_customer_id.blank?

      Stripe::BillingPortal::Session.create(
        customer: subscription.provider_customer_id,
        return_url: return_url
      )
    end

    def cancel_at_period_end!
      require_secret_key!
      raise ConfigurationError, "This workspace does not have a Stripe subscription yet." if subscription.provider_subscription_id.blank?

      Stripe::Subscription.update(subscription.provider_subscription_id, cancel_at_period_end: true)
    end

    private

    attr_reader :subscription, :workspace, :user

    def require_configured!
      require_secret_key!
      self.class.price_id_for!(subscription.plan_key)
    end

    def require_secret_key!
      return if self.class.secret_key.present?

      raise ConfigurationError, "STRIPE_SECRET_KEY is not configured."
    end

    def metadata
      {
        workspace_id: workspace.id,
        workspace_slug: workspace.slug,
        workspace_subscription_id: subscription.id,
        user_id: user.id,
        plan_key: subscription.plan_key
      }
    end
  end
end
