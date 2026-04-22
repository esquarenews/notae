module Billing
  class PlanCatalog
    PLANS = {
      WorkspaceSubscription::PLAN_FREE => {
        name: "Free",
        monthly_price_aud_cents: 0,
        limits: {
          members: 1,
          storage_mb: 250,
          ai_requests_per_month: 100,
          integrations: 1,
          exports_per_month: 10
        }
      },
      WorkspaceSubscription::PLAN_STARTER => {
        name: "Starter",
        monthly_price_aud_cents: 1900,
        limits: {
          members: 3,
          storage_mb: 2_048,
          ai_requests_per_month: 1_000,
          integrations: 3,
          exports_per_month: 100
        }
      },
      WorkspaceSubscription::PLAN_TEAM => {
        name: "Team",
        monthly_price_aud_cents: 4900,
        limits: {
          members: 10,
          storage_mb: 10_240,
          ai_requests_per_month: 5_000,
          integrations: 10,
          exports_per_month: 500
        }
      },
      WorkspaceSubscription::PLAN_BUSINESS => {
        name: "Business",
        monthly_price_aud_cents: 12900,
        limits: {
          members: 50,
          storage_mb: 102_400,
          ai_requests_per_month: 25_000,
          integrations: 50,
          exports_per_month: 2_500
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
  end
end
