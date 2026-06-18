# frozen_string_literal: true

module Notae
  module SessionStatePruner
    LAST_PAGE_VISIT_LIMIT = 6
    WORKSPACE_SESSION_LIMIT = 8
    MAX_VISIBILITY_IDS_IN_COOKIE = 24
    VISIBILITY_SESSION_KEYS = %w[
      kalendarium_calendar_selection
      kalendarium_project_visibility
    ].freeze
    WORKSPACE_SCOPED_LIMITS = {
      "notae_last_page_visits" => LAST_PAGE_VISIT_LIMIT,
      "kalendarium_calendar_selection" => WORKSPACE_SESSION_LIMIT,
      "kalendarium_project_visibility" => WORKSPACE_SESSION_LIMIT,
      "kalendarium_last_calendar_view" => WORKSPACE_SESSION_LIMIT,
      "kalendarium_planning_view" => WORKSPACE_SESSION_LIMIT
    }.freeze

    module_function

    def prune!(session)
      WORKSPACE_SCOPED_LIMITS.each do |session_key, limit|
        prune_workspace_scoped_hash!(session, session_key, limit:)
      end
    end

    def normalized_workspace_scoped_hash(raw_store, limit:, session_key: nil)
      normalized =
        if raw_store.is_a?(Hash)
          raw_store.to_h.stringify_keys
        else
          {}
        end

      normalized.to_a.last(limit).to_h do |workspace_key, value|
        [ workspace_key, normalized_workspace_value(session_key, value) ]
      end
    end

    def prune_workspace_scoped_hash!(session, session_key, limit:)
      raw_store = session[session_key]
      pruned_store = normalized_workspace_scoped_hash(raw_store, limit:, session_key:)
      session[session_key] = pruned_store if raw_store != pruned_store
      pruned_store
    end

    def normalized_workspace_value(session_key, value)
      return value unless VISIBILITY_SESSION_KEYS.include?(session_key)

      compact_visibility_payload(value)
    end

    def compact_visibility_payload(value)
      raw = value.is_a?(Hash) ? value.to_h.stringify_keys : {}
      mode = raw["mode"].to_s

      if %w[all none selected all_except].include?(mode)
        ids = normalized_ids(raw["ids"])
        return { "mode" => mode } if %w[all none].include?(mode) || ids.empty?
        return { "mode" => "all" } if ids.size > MAX_VISIBILITY_IDS_IN_COOKIE

        { "mode" => mode, "ids" => ids }
      else
        compact_legacy_visibility_payload(raw)
      end
    end

    def compact_legacy_visibility_payload(raw)
      selected = normalized_ids(raw["selected_ids"])
      available = normalized_ids(raw["available_ids"])

      if available.any?
        selected &= available
        return { "mode" => "none" } if selected.empty?
        return { "mode" => "all" } if selected.sort == available.sort

        deselected = available - selected
        if deselected.any? && deselected.size < selected.size
          return { "mode" => "all" } if deselected.size > MAX_VISIBILITY_IDS_IN_COOKIE

          return { "mode" => "all_except", "ids" => deselected }
        end
      end

      return { "mode" => "all" } if selected.size > MAX_VISIBILITY_IDS_IN_COOKIE

      selected.any? ? { "mode" => "selected", "ids" => selected } : { "mode" => "none" }
    end

    def normalized_ids(raw_ids)
      Array(raw_ids).map(&:to_s).reject(&:blank?).uniq
    end
  end
end
