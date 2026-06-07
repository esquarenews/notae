module Billing
  class PlanCatalog
    PLANS = {
      WorkspaceSubscription::PLAN_FREE => {
        name: "Free",
        monthly_price_aud_cents: 0,
        stripe_price_env: nil,
        limits: {
          members: 1,
          storage_mb: 100,
          ai_requests_per_month: 25,
          ai_monthly_budget_usd: 1.0,
          integrations: 1,
          exports_per_month: 3
        }
      },
      WorkspaceSubscription::PLAN_STARTER => {
        name: "Starter",
        monthly_price_aud_cents: 1900,
        stripe_price_env: "STRIPE_PRICE_STARTER",
        limits: {
          members: 3,
          storage_mb: 1_024,
          ai_requests_per_month: 300,
          ai_monthly_budget_usd: 2.0,
          integrations: 2,
          exports_per_month: 25
        }
      },
      WorkspaceSubscription::PLAN_TEAM => {
        name: "Team",
        monthly_price_aud_cents: 4900,
        stripe_price_env: "STRIPE_PRICE_TEAM",
        limits: {
          members: 10,
          storage_mb: 10_240,
          ai_requests_per_month: 2_000,
          ai_monthly_budget_usd: 8.0,
          integrations: 6,
          exports_per_month: 150
        }
      },
      WorkspaceSubscription::PLAN_BUSINESS => {
        name: "Business",
        monthly_price_aud_cents: 12900,
        stripe_price_env: "STRIPE_PRICE_BUSINESS",
        limits: {
          members: 35,
          storage_mb: 51_200,
          ai_requests_per_month: 8_000,
          ai_monthly_budget_usd: 30.0,
          integrations: 20,
          exports_per_month: 750
        }
      }
    }.freeze

    def self.plan_for(plan_key)
      PLANS.fetch(plan_key.to_s, PLANS.fetch(WorkspaceSubscription::PLAN_FREE))
    end

    def self.limits_for(plan_key)
      plan_for(plan_key).fetch(:limits)
    end

    def self.name_for(plan_key)
      plan_for(plan_key).fetch(:name)
    end

    def self.public_plan_keys
      [ WorkspaceSubscription::PLAN_STARTER, WorkspaceSubscription::PLAN_TEAM, WorkspaceSubscription::PLAN_BUSINESS ]
    end

    def self.admin_grantable_plan_keys
      WorkspaceSubscription::PLAN_KEYS
    end

    def self.monthly_price_aud_cents_for(plan_key)
      plan_for(plan_key).fetch(:monthly_price_aud_cents)
    end

    def self.monthly_price_label_for(plan_key)
      cents = monthly_price_aud_cents_for(plan_key)
      return "Free" if cents.zero?

      "$#{cents / 100}/mo"
    end

    def self.stripe_price_env_for(plan_key)
      plan_for(plan_key)[:stripe_price_env]
    end

    def self.stripe_price_id_for(plan_key)
      env_key = stripe_price_env_for(plan_key)
      return nil if env_key.blank?

      ENV[env_key].to_s.strip.presence
    end
  end
end
