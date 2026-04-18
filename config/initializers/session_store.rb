# frozen_string_literal: true

require Rails.root.join("lib/notae/solid_cache_support")

# iOS standalone PWAs do not reliably preserve browser-session cookies across
# app relaunches, so make the auth session explicit and persistent.
# Default auth sessions to cookie_store so cache eviction cannot silently sign
# users out. Server-side sessions remain available as an explicit opt-in via
# NOTAE_SERVER_SIDE_SESSIONS=true when Solid Cache is provisioned and intended
# to carry authentication state.
Rails.application.config.session_store(
  Notae::SolidCacheSupport.session_store,
  key: "_notae_session",
  expire_after: 30.days,
  same_site: :lax,
  secure: Rails.env.production?,
  httponly: true
)
