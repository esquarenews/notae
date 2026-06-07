if defined?(Stripe)
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"].to_s.presence
  Stripe.api_version = "2026-02-25.clover"
end
