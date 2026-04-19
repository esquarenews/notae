# frozen_string_literal: true

module Notae
  module SessionStatePruner
    LAST_PAGE_VISIT_LIMIT = 6
    WORKSPACE_SESSION_LIMIT = 8
    WORKSPACE_SCOPED_LIMITS = {
      "notae_last_page_visits" => LAST_PAGE_VISIT_LIMIT,
      "kalendarium_calendar_selection" => WORKSPACE_SESSION_LIMIT,
      "kalendarium_project_visibility" => WORKSPACE_SESSION_LIMIT,
      "kalendarium_last_calendar_view" => WORKSPACE_SESSION_LIMIT
    }.freeze

    module_function

    def prune!(session)
      WORKSPACE_SCOPED_LIMITS.each do |session_key, limit|
        prune_workspace_scoped_hash!(session, session_key, limit:)
      end
    end

    def normalized_workspace_scoped_hash(raw_store, limit:)
      normalized =
        if raw_store.is_a?(Hash)
          raw_store.to_h.stringify_keys
        else
          {}
        end

      normalized.to_a.last(limit).to_h
    end

    def prune_workspace_scoped_hash!(session, session_key, limit:)
      raw_store = session[session_key]
      pruned_store = normalized_workspace_scoped_hash(raw_store, limit:)
      session[session_key] = pruned_store if raw_store != pruned_store
      pruned_store
    end
  end
end
