# frozen_string_literal: true

require Rails.root.join("lib/notae/solid_cache_support")

# iOS standalone PWAs do not reliably preserve browser-session cookies across
# app relaunches, so make the auth session explicit and persistent.
# Use a server-side session store when Solid Cache is available. If the cache
# table has not been migrated yet, fall back to cookie_store so the app stays
# up during deploy ordering mistakes.
Rails.application.config.session_store(
  Notae::SolidCacheSupport.session_store,
  key: "_notae_session",
  expire_after: 30.days,
  same_site: :lax,
  secure: Rails.env.production?,
  httponly: true
)
