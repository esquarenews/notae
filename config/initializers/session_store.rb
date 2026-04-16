# frozen_string_literal: true

# iOS standalone PWAs do not reliably preserve browser-session cookies across
# app relaunches, so make the auth session explicit and persistent.
# Use a server-side session store outside test to avoid cookie-overflow 500s
# when the UI writes flash state or other session data.
Rails.application.config.session_store(
  Rails.env.test? ? :cookie_store : :cache_store,
  key: "_notae_session",
  expire_after: 30.days,
  same_site: :lax,
  secure: Rails.env.production?,
  httponly: true
)
