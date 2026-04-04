# frozen_string_literal: true

# iOS standalone PWAs do not reliably preserve browser-session cookies across
# app relaunches, so make the auth session explicit and persistent.
Rails.application.config.session_store(
  :cookie_store,
  key: "_notae_session",
  expire_after: 30.days,
  same_site: :lax,
  secure: Rails.env.production?,
  httponly: true
)
