module Search
  class AssistantQueryService
    Response = Struct.new(:answer, :sources, :scope, :intent, :auto_insert, :model, :agent_action, keyword_init: true)

    SCOPE_AUTO = "auto"
    SCOPE_DOCUMENT = "document"
    SCOPE_WORKSPACE = "workspace"
    SCOPE_ACCOUNT = "account"
    SCOPE_OPTIONS = [
      [ "Auto", SCOPE_AUTO ],
      [ "This document only", SCOPE_DOCUMENT ],
      [ "This workspace only", SCOPE_WORKSPACE ],
      [ "Whole app", SCOPE_ACCOUNT ]
    ].freeze

    INTENT_SEARCH = "search"
    INTENT_COMPOSE = "compose"
    INTENT_SUGGEST_EDITS = "suggest_edits"
    INTENT_DRAFT_ACTION = "draft_action"
    INTENT_ASK_AI = "ask_ai"
    INTENT_OPTIONS = [
      INTENT_SEARCH,
      INTENT_COMPOSE,
      INTENT_SUGGEST_EDITS,
      INTENT_DRAFT_ACTION,
      INTENT_ASK_AI
    ].freeze

    SUPPORTED_DRAFT_TARGETS = AgentAction::TARGET_SYSTEM_OPTIONS.freeze
    SEARCH_MODEL = "gpt-4o-mini"
    WRITING_MODEL = "gpt-4.1-mini"
    GENERAL_MODEL = "gpt-4.1-mini"
    WEB_SEARCH_TOOL_TYPE = "web_search".freeze
    CALENDAR_DIRECT_MODEL = "calendar-direct-v1"
    MAX_CONTEXT_ITEMS = 12
    CALENDAR_EVENT_LIMIT = 40
    QUERY_TERM_STOPWORDS = %w[
      a
      an
      and
      are
      but
      can
      could
      did
      do
      does
      for
      from
      had
      has
      have
      how
      in
      into
      is
      it
      its
      mentioned
      no
      nota
      notae
      of
      on
      or
      our
      page
      search
      specific
      term
      that
      the
      their
      there
      this
      what
      where
      which
      who
      why
      will
      with
      within
      workspace
    ].freeze
    WEEKDAY_INDEX_BY_NAME = {
      "sunday" => 0,
      "monday" => 1,
      "tuesday" => 2,
      "wednesday" => 3,
      "thursday" => 4,
      "friday" => 5,
      "saturday" => 6
    }.freeze

    attr_reader :unavailable_reason

    def initialize(user:, workspace:, prompt:, scope:, current_page_id: nil, intent: nil, target_block: nil)
      @user = user
      @workspace = workspace
      @prompt = prompt.to_s.strip
      @scope = scope.to_s
      @current_page_id = current_page_id
      @intent = intent.to_s
      @target_block = target_block
      @unavailable_reason = nil
    end

    def call
      return unavailable(:missing_prompt) if prompt.blank?
      return unavailable(:missing_api_key) unless Openai::CredentialResolver.configured?(user: user)
      return unavailable(:budget_exceeded) unless Search::AiBudgetGuard.within_daily_budget?(user: user, workspace: workspace)
      return unavailable(:rate_limited) unless Search::AiRateLimiter.allowed?(user: user, workspace: workspace, operation: "answer_generation")

      resolved_scope = resolve_scope
      resolved_intent = resolve_intent
      if draft_action_intent?(resolved_intent)
        return generate_draft_action_response(resolved_scope: resolved_scope, resolved_intent: resolved_intent)
      end
      if writing_intent?(resolved_intent)
        return generate_writing_response(resolved_scope: resolved_scope, resolved_intent: resolved_intent)
      end

      calendar_response = calendar_agenda_response(resolved_scope: resolved_scope, resolved_intent: resolved_intent)
      return calendar_response if calendar_response.present?

      context_entries = build_context_entries(resolved_scope)
      if use_general_knowledge_response?(resolved_scope: resolved_scope, context_entries: context_entries)
        return generate_general_knowledge_response(resolved_scope: resolved_scope, resolved_intent: resolved_intent)
      end
      return unavailable(:no_context) if context_entries.empty?

      response = Openai::ResponsesClient.generate_text_with_usage(
        prompt: prompt_for(context_entries, resolved_scope),
        api_key: assistant_api_key,
        model: SEARCH_MODEL,
        max_output_tokens: 420
      )
      answer_text = response[:text].to_s.strip
      return unavailable(:empty_response) if answer_text.blank?

      normalized_text, used_indices = normalize_citations(answer_text, context_entries.length)
      used_sources = used_indices.map { |index| context_entries[index - 1].slice(:index, :title, :kind, :url, :workspace_name) }

      Search::AiUsageLogger.log!(
        user: user,
        workspace: workspace,
        operation: AiUsageLog::OP_ASSISTANT_QUERY,
        model: SEARCH_MODEL,
        usage: response[:usage],
        metadata: {
          scope: resolved_scope,
          context_items: context_entries.length,
          prompt_length: prompt.length
        }
      )

      Response.new(
        answer: normalized_text,
        sources: used_sources,
        scope: resolved_scope,
        intent: resolved_intent,
        auto_insert: false,
        model: SEARCH_MODEL
      )
    rescue Openai::ResponsesClient::Error => e
      Rails.logger.warn("AI assistant query failed for workspace=#{workspace.id}: #{e.message}")
      unavailable(:provider_error)
    end

    private

    attr_reader :user, :workspace, :prompt, :scope, :current_page_id, :intent, :target_block

    def resolve_scope
      return SCOPE_DOCUMENT if scope == SCOPE_AUTO && current_page_id.present?
      return SCOPE_WORKSPACE if scope == SCOPE_AUTO

      [ SCOPE_DOCUMENT, SCOPE_WORKSPACE, SCOPE_ACCOUNT ].include?(scope) ? scope : SCOPE_WORKSPACE
    end

    def resolve_intent
      return INTENT_COMPOSE if intent == INTENT_ASK_AI
      return intent if INTENT_OPTIONS.include?(intent)
      return INTENT_DRAFT_ACTION if prompt_requests_draft_action?
      return INTENT_COMPOSE if prompt_requests_writing?

      INTENT_SEARCH
    end

    def draft_action_intent?(resolved_intent)
      resolved_intent == INTENT_DRAFT_ACTION
    end

    def writing_intent?(resolved_intent)
      [ INTENT_COMPOSE, INTENT_SUGGEST_EDITS ].include?(resolved_intent)
    end

    def prompt_requests_draft_action?
      normalized = prompt.downcase
      return false if normalized.blank?

      patterns = [
        /\b(draft|write|compose|prepare|create)\b.*\b(email|e-mail|mail|reply)\b/,
        /\b(draft|write|compose|prepare|create)\b.*\b(github|pull request|pull-request|pr|issue)\b.*\b(comment|reply|response)\b/,
        /\b(draft|create|prepare)\b.*\b(ticket|task|todo|to-do|action item|handoff)\b/,
        /\b(draft|create|prepare|schedule|book|reserve)\b.*\b(calendar|meeting|invite|hold|time slot|timeslot)\b/,
        /\b(draft|create|prepare|write|save)\b.*\b(nota|note|page|brief)\b/
      ]

      patterns.any? { |pattern| normalized.match?(pattern) }
    end

    def prompt_requests_writing?
      normalized = prompt.downcase
      patterns = [
        /\b(write|draft|compose|generate|rewrite|reword|rephrase|expand|continue)\b/,
        /\b(improve|polish|tighten)\b.*\b(text|copy|paragraph|sentence|writing|block)\b/,
        /\b(fix|correct)\b.*\b(grammar|spelling|typos?|punctuation)\b/,
        /\bsuggest edits?\b/
      ]

      patterns.any? { |pattern| normalized.match?(pattern) }
    end

    def generate_draft_action_response(resolved_scope:, resolved_intent:)
      requested_draft = draft_request_for_prompt
      return unavailable(:unsupported_draft_request) if requested_draft.blank?

      context_entries = build_context_entries(resolved_scope)
      response = Openai::ResponsesClient.generate_text_with_usage(
        prompt: draft_action_prompt_for(
          resolved_scope: resolved_scope,
          requested_draft: requested_draft,
          context_entries: context_entries
        ),
        api_key: assistant_api_key,
        model: WRITING_MODEL,
        max_output_tokens: 720
      )

      parsed = parse_json_object(response[:text])
      source_indices = normalized_source_indices(parsed["used_source_indices"], context_entries)
      payload = normalize_ai_draft_payload(
        payload: parsed.fetch("payload", {}),
        requested_draft: requested_draft,
        parsed_title: parsed["title"]
      )
      agent_action = AgentActions::DraftCreator.new(
        workspace: workspace,
        actor: user,
        attributes: {
          title: draft_title_for(parsed: parsed, payload: payload, requested_draft: requested_draft),
          proposed_by: "ai_assistant",
          target_system: requested_draft.fetch(:target_system),
          draft_type: requested_draft.fetch(:draft_type),
          payload_json: payload,
          metadata_json: {
            "origin_prompt" => prompt,
            "resolved_scope" => resolved_scope,
            "source_indices" => source_indices,
            "source_snapshot" => source_snapshot_for_indices(source_indices, context_entries),
            "model" => WRITING_MODEL
          }
        }
      ).call

      Search::AiUsageLogger.log!(
        user: user,
        workspace: workspace,
        operation: AiUsageLog::OP_ASSISTANT_WRITE,
        model: WRITING_MODEL,
        usage: response[:usage],
        metadata: {
          scope: resolved_scope,
          intent: resolved_intent,
          prompt_length: prompt.length,
          draft_type: requested_draft.fetch(:draft_type),
          target_system: requested_draft.fetch(:target_system),
          context_items: context_entries.length
        }
      )

      used_sources = source_indices.map { |index| context_entries[index - 1].slice(:index, :title, :kind, :url, :workspace_name) }
      used_sources << review_source_for(agent_action)

      Response.new(
        answer: parsed["summary"].to_s.strip.presence || default_draft_summary_for(requested_draft: requested_draft, agent_action: agent_action),
        sources: used_sources,
        scope: resolved_scope,
        intent: resolved_intent,
        auto_insert: false,
        model: WRITING_MODEL,
        agent_action: agent_action
      )
    rescue JSON::ParserError, KeyError
      unavailable(:draft_generation_failed)
    rescue AgentActions::DraftCreator::Error => e
      Rails.logger.warn("AI assistant draft creation failed for workspace=#{workspace.id}: #{e.message}")
      unavailable(:draft_validation_failed)
    end

    def generate_writing_response(resolved_scope:, resolved_intent:)
      if resolved_intent == INTENT_SUGGEST_EDITS && target_block_text.blank?
        return unavailable(:no_context)
      end

      response = Openai::ResponsesClient.generate_text_with_usage(
        prompt: writing_prompt_for(resolved_scope: resolved_scope, resolved_intent: resolved_intent),
        api_key: assistant_api_key,
        model: WRITING_MODEL,
        max_output_tokens: 520
      )

      answer_text = response[:text].to_s.strip
      return unavailable(:empty_response) if answer_text.blank?

      Search::AiUsageLogger.log!(
        user: user,
        workspace: workspace,
        operation: AiUsageLog::OP_ASSISTANT_WRITE,
        model: WRITING_MODEL,
        usage: response[:usage],
        metadata: {
          scope: resolved_scope,
          intent: resolved_intent,
          prompt_length: prompt.length,
          target_block_id: target_block&.id
        }
      )

      Response.new(
        answer: answer_text,
        sources: [],
        scope: resolved_scope,
        intent: resolved_intent,
        auto_insert: resolved_intent == INTENT_COMPOSE,
        model: WRITING_MODEL
      )
    end

    def calendar_agenda_response(resolved_scope:, resolved_intent:)
      return nil unless resolved_intent == INTENT_SEARCH

      normalized_prompt = prompt.downcase
      return nil unless calendar_schedule_request?(normalized_prompt)

      window = calendar_query_window(normalized_prompt)
      events = calendar_events_for_window(resolved_scope: resolved_scope, window: window)
      if events.empty?
        return Response.new(
          answer: "No appointments found for #{window[:label]}.",
          sources: [],
          scope: resolved_scope,
          intent: resolved_intent,
          auto_insert: false,
          model: CALENDAR_DIRECT_MODEL
        )
      end

      context_entries = events.first(MAX_CONTEXT_ITEMS).each_with_index.map do |event, index|
        calendar_context_entry_for_event(event: event, index: index + 1, resolved_scope: resolved_scope)
      end
      answer_lines = context_entries.map { |entry| "- #{entry[:excerpt]} [#{entry[:index]}]" }
      answer_text = [ "Appointments for #{window[:label]}:", *answer_lines ].join("\n")
      used_sources = context_entries.map { |entry| entry.slice(:index, :title, :kind, :url, :workspace_name) }

      Response.new(
        answer: answer_text,
        sources: used_sources,
        scope: resolved_scope,
        intent: resolved_intent,
        auto_insert: false,
        model: CALENDAR_DIRECT_MODEL
      )
    end

    def calendar_schedule_request?(normalized_prompt)
      return false if normalized_prompt.blank?

      schedule_keyword = /\b(appointment|appointments|meeting|meetings|event|events|schedule|scheduled|agenda|calendar|activity|activities)\b/
      request_patterns = [
        /\bwhat do i have\b/,
        /\bwhat(?:'s| is) on\b/,
        /\bwhat (appointments|meetings|events)\b/,
        /\bshow (me )?(my )?(appointments|meetings|events|schedule|calendar|agenda)\b/,
        /\blist (my )?(appointments|meetings|events|schedule|calendar|agenda)\b/,
        /\bdo i have (any )?(appointments|meetings|events)\b/,
        /\bwhich (appointments|meetings|events)\b/
      ]
      request_keyword = /\b(what|which|show|list|tell|any)\b/

      request_patterns.any? { |pattern| normalized_prompt.match?(pattern) } ||
        (normalized_prompt.match?(schedule_keyword) && normalized_prompt.match?(request_keyword))
    end

    def calendar_query_window(normalized_prompt)
      today = Time.current.in_time_zone(user_time_zone).to_date
      if normalized_prompt.match?(/\btomorrow\b/)
        date = today + 1
        return day_window_for(date: date, label: "tomorrow (#{format_calendar_date(date)})")
      end
      if normalized_prompt.match?(/\btoday\b|\btonight\b/)
        return day_window_for(date: today, label: "today (#{format_calendar_date(today)})")
      end
      if normalized_prompt.match?(/\bthis week\b/)
        start_date = today.beginning_of_week(calendar_week_start_day)
        end_date = start_date + 6
        return range_window_for(
          start_date: start_date,
          end_date_exclusive: start_date + 7,
          label: "this week (#{format_calendar_date_range(start_date, end_date)})"
        )
      end
      if normalized_prompt.match?(/\bnext week\b/)
        start_date = today.beginning_of_week(calendar_week_start_day) + 7
        end_date = start_date + 6
        return range_window_for(
          start_date: start_date,
          end_date_exclusive: start_date + 7,
          label: "next week (#{format_calendar_date_range(start_date, end_date)})"
        )
      end
      if normalized_prompt.match?(/\bthis month\b/)
        start_date = today.beginning_of_month
        end_date_exclusive = start_date.next_month
        return range_window_for(
          start_date: start_date,
          end_date_exclusive: end_date_exclusive,
          label: "this month (#{start_date.strftime('%B %Y')})"
        )
      end
      if normalized_prompt.match?(/\bnext month\b/)
        start_date = today.beginning_of_month.next_month
        end_date_exclusive = start_date.next_month
        return range_window_for(
          start_date: start_date,
          end_date_exclusive: end_date_exclusive,
          label: "next month (#{start_date.strftime('%B %Y')})"
        )
      end

      explicit_date = explicit_date_from_prompt(normalized_prompt, today: today)
      return day_window_for(date: explicit_date, label: format_calendar_date(explicit_date)) if explicit_date.present?

      weekday_date = weekday_date_from_prompt(normalized_prompt, today: today)
      return day_window_for(date: weekday_date, label: format_calendar_date(weekday_date)) if weekday_date.present?

      upcoming_start_date = today
      upcoming_end_date = upcoming_start_date + 6
      range_window_for(
        start_date: upcoming_start_date,
        end_date_exclusive: upcoming_start_date + 7,
        label: "the next 7 days (#{format_calendar_date_range(upcoming_start_date, upcoming_end_date)})"
      )
    end

    def day_window_for(date:, label:)
      range_window_for(start_date: date, end_date_exclusive: date + 1, label: label)
    end

    def range_window_for(start_date:, end_date_exclusive:, label:)
      start_local = user_time_zone.local(start_date.year, start_date.month, start_date.day)
      end_local = user_time_zone.local(end_date_exclusive.year, end_date_exclusive.month, end_date_exclusive.day)

      {
        range_start_utc: start_local.utc,
        range_end_utc: end_local.utc,
        label: label
      }
    end

    def explicit_date_from_prompt(normalized_prompt, today:)
      if (iso_match = normalized_prompt.match(/\b(\d{4})-(\d{1,2})-(\d{1,2})\b/))
        return Date.new(iso_match[1].to_i, iso_match[2].to_i, iso_match[3].to_i)
      end

      date_match = normalized_prompt.match(/\b(\d{1,2})[\/\-](\d{1,2})(?:[\/\-](\d{2,4}))?\b/)
      return nil unless date_match

      first = date_match[1].to_i
      second = date_match[2].to_i
      year = normalized_year(value: date_match[3], fallback: today.year)

      candidates = []
      candidates << safe_build_date(year: year, month: second, day: first)
      candidates << safe_build_date(year: year, month: first, day: second)
      candidates.compact!
      return nil if candidates.empty?

      candidates.sort_by { |candidate| [ candidate < today ? 1 : 0, (candidate - today).abs ] }.first
    end

    def safe_build_date(year:, month:, day:)
      Date.new(year, month, day)
    rescue Date::Error
      nil
    end

    def normalized_year(value:, fallback:)
      return fallback if value.blank?

      year = value.to_i
      return year + 2000 if value.to_s.length == 2

      year
    end

    def weekday_date_from_prompt(normalized_prompt, today:)
      day_name = WEEKDAY_INDEX_BY_NAME.keys.find { |name| normalized_prompt.match?(/\b(?:this|next)?\s*#{name}\b/) }
      return nil if day_name.blank?

      target_wday = WEEKDAY_INDEX_BY_NAME.fetch(day_name)
      if normalized_prompt.match?(/\bthis #{day_name}\b/)
        start_of_week = today.beginning_of_week(calendar_week_start_day)
        candidate = start_of_week + ((target_wday - start_of_week.wday) % 7)
        return candidate >= today ? candidate : candidate + 7
      end

      days_ahead = (target_wday - today.wday) % 7
      days_ahead = 7 if days_ahead.zero?
      candidate = today + days_ahead
      candidate += 7 if normalized_prompt.match?(/\bnext #{day_name}\b/)
      candidate
    end

    def calendar_events_for_window(resolved_scope:, window:)
      scope = accessible_kalendarium_events_scope.includes(:workspace, :kalendarium_calendar).where.not(status: "cancelled")
      scope = scope.where(workspace_id: workspace.id) unless resolved_scope == SCOPE_ACCOUNT

      scope.for_range(window[:range_start_utc], window[:range_end_utc])
           .order(:starts_at_utc)
           .limit(CALENDAR_EVENT_LIMIT)
    end

    def calendar_context_entry_for_event(event:, index:, resolved_scope:)
      {
        index: index,
        kind: "Kalendarium event",
        title: event.title,
        excerpt: calendar_event_excerpt(event: event, resolved_scope: resolved_scope),
        workspace_name: event.workspace.name,
        url: Rails.application.routes.url_helpers.kalendarium_path(
          workspace_slug: event.workspace.slug,
          view: "day",
          date: event.starts_at_utc.in_time_zone(user_time_zone).to_date.iso8601,
          anchor: "kalendarium_event_#{event.id}"
        )
      }
    end

    def calendar_event_excerpt(event:, resolved_scope:)
      starts_at_local = event.starts_at_utc.in_time_zone(user_time_zone)
      ends_at_local = event.ends_at_utc.in_time_zone(user_time_zone)
      time_label =
        if event.all_day?
          "All day"
        elsif starts_at_local.to_date == ends_at_local.to_date
          "#{starts_at_local.strftime('%a %-d %b %Y %H:%M')} to #{ends_at_local.strftime('%H:%M')}"
        else
          "#{starts_at_local.strftime('%a %-d %b %Y %H:%M')} to #{ends_at_local.strftime('%a %-d %b %Y %H:%M')}"
        end

      details = []
      details << "Calendar: #{event.kalendarium_calendar.name}" if event.kalendarium_calendar&.name.present?
      details << "Location: #{event.location}" if event.location.present?
      details << "Status: #{event.status.titleize}" if event.status.present? && event.status != "confirmed"
      if resolved_scope == SCOPE_ACCOUNT && event.workspace_id != workspace.id
        details << "Workspace: #{event.workspace.name}"
      end

      [ "#{time_label} - #{event.title}", details.join("; ").presence ].compact.join(" (") + (details.present? ? ")" : "")
    end

    def format_calendar_date(date)
      date.strftime("%A %-d %B %Y")
    end

    def format_calendar_date_range(start_date, end_date)
      "#{format_calendar_date(start_date)} to #{format_calendar_date(end_date)}"
    end

    def calendar_week_start_day
      user.start_week_on_monday? ? :monday : :sunday
    end

    def user_time_zone
      @user_time_zone ||= ActiveSupport::TimeZone[user.time_zone] || Time.zone || ActiveSupport::TimeZone["UTC"]
    end

    def use_general_knowledge_response?(resolved_scope:, context_entries:)
      return true if live_web_prompt?
      return true if general_knowledge_prompt?
      return false if resolved_scope == SCOPE_DOCUMENT

      context_entries.empty?
    end

    def live_web_prompt?
      normalized = prompt.downcase.strip
      return false if normalized.blank?
      return false if context_bound_prompt?(normalized)

      live_patterns = [
        /\bweather\b/,
        /\bforecast\b/,
        /\btemperature\b/,
        /\brain(?:ing)?\b/,
        /\bhumidity\b/,
        /\bwind(?:y|s)?\b/,
        /\bnews\b/,
        /\bheadline(?:s)?\b/,
        /\blatest\b/,
        /\bcurrent\b/,
        /\bright now\b/,
        /\btoday\b/,
        /\btomorrow\b/,
        /\bstock price\b/,
        /\bprice of\b/,
        /\bexchange rate\b/,
        /\bwho won\b/,
        /\bscore(?:s)?\b/
      ]

      live_patterns.any? { |pattern| normalized.match?(pattern) }
    end

    def general_knowledge_prompt?
      normalized = prompt.downcase.strip
      return false if normalized.blank?
      return false if context_bound_prompt?(normalized)

      dictionary_like_patterns = [
        /\bdefinition of\b/,
        /\bdefine\b/,
        /\bwhat does .+ mean\b/,
        /\bmeaning of\b/,
        /\bsynonym(?:s)? (?:for|of)\b/,
        /\balternative word(?:s)? (?:for|to)\b/,
        /\banother word(?:s)? (?:for|to)\b/
      ]
      return true if dictionary_like_patterns.any? { |pattern| normalized.match?(pattern) }

      normalized.start_with?("what is ") && normalized.split.size <= 7
    end

    def context_bound_prompt?(normalized_prompt)
      context_patterns = [
        /\b(this|current|our)\s+(document|nota|page|workspace|grid|row|account)\b/,
        /\b(in|from|within)\s+(this|the)\s+(document|nota|page|workspace|grid)\b/,
        /\bmentioned\b/,
        /\bsummari[sz]e\b/
      ]

      context_patterns.any? { |pattern| normalized_prompt.match?(pattern) }
    end

    def generate_general_knowledge_response(resolved_scope:, resolved_intent:)
      return generate_live_web_response(resolved_scope: resolved_scope, resolved_intent: resolved_intent) if live_web_prompt?

      response = Openai::ResponsesClient.generate_text_with_usage(
        prompt: general_prompt_for(resolved_scope: resolved_scope),
        api_key: assistant_api_key,
        model: GENERAL_MODEL,
        max_output_tokens: 420
      )
      answer_text = response[:text].to_s.strip
      return unavailable(:empty_response) if answer_text.blank?

      Search::AiUsageLogger.log!(
        user: user,
        workspace: workspace,
        operation: AiUsageLog::OP_ASSISTANT_QUERY,
        model: GENERAL_MODEL,
        usage: response[:usage],
        metadata: {
          scope: resolved_scope,
          answer_mode: "general_knowledge",
          prompt_length: prompt.length
        }
      )

      Response.new(
        answer: answer_text,
        sources: [],
        scope: resolved_scope,
        intent: resolved_intent,
        auto_insert: false,
        model: GENERAL_MODEL
      )
    end

    def generate_live_web_response(resolved_scope:, resolved_intent:)
      response = Openai::ResponsesClient.generate_text_with_usage(
        prompt: live_web_prompt_for(resolved_scope: resolved_scope),
        api_key: assistant_api_key,
        model: GENERAL_MODEL,
        max_output_tokens: 420,
        tools: [ web_search_tool ],
        include: [ "web_search_call.action.sources" ]
      )
      answer_text = response[:text].to_s.strip
      return unavailable(:empty_response) if answer_text.blank?

      sources = Array(response[:sources]).first(6).map.with_index do |source, index|
        {
          index: index + 1,
          title: source[:title],
          kind: "Web source",
          url: source[:url],
          workspace_name: nil
        }
      end

      Search::AiUsageLogger.log!(
        user: user,
        workspace: workspace,
        operation: AiUsageLog::OP_ASSISTANT_QUERY,
        model: GENERAL_MODEL,
        usage: response[:usage],
        metadata: {
          scope: resolved_scope,
          answer_mode: "live_web",
          prompt_length: prompt.length,
          source_count: sources.length
        }
      )

      Response.new(
        answer: answer_text,
        sources: sources,
        scope: resolved_scope,
        intent: resolved_intent,
        auto_insert: false,
        model: GENERAL_MODEL
      )
    end

    def build_context_entries(resolved_scope)
      case resolved_scope
      when SCOPE_DOCUMENT
        document_context_entries
      when SCOPE_ACCOUNT
        finalize_context_entries(chunk_context_entry_candidates(scope: account_chunks_scope, resolved_scope: resolved_scope))
      else
        finalize_context_entries(chunk_context_entry_candidates(scope: workspace_chunks_scope, resolved_scope: resolved_scope))
      end
    end

    def document_context_entries
      page = current_workspace_pages_scope.find_by(id: current_page_id)
      return [] if page.blank?

      text = [ page.title, page.blocks.active.ordered.pluck(:search_text).join("\n") ].join("\n").squish
      chunks = Search::TextChunker.call(text, target_words: 150, overlap_words: 25)
      selected_chunks = select_top_text_chunks(chunks)

      selected_chunks.map.with_index do |chunk_text, index|
        {
          index: index + 1,
          kind: "Page",
          title: page.title,
          excerpt: chunk_text,
          workspace_name: page.workspace.name,
          url: Rails.application.routes.url_helpers.page_path(workspace_slug: page.workspace.slug, id: page.id)
        }
      end
    end

    def chunk_context_entry_candidates(scope:, resolved_scope:)
      chunk_entries = select_top_chunks(scope).filter_map { |chunk| context_entry_candidate_for_chunk(chunk) }
      live_entries = live_context_entry_candidates(resolved_scope: resolved_scope)

      rank_context_entry_candidates(chunk_entries + live_entries)
    end

    def select_top_chunks(scope)
      terms = query_terms
      records = scope.includes(SearchChunk.context_preload_associations).order(updated_at: :desc).limit(220).to_a
      return records.first(MAX_CONTEXT_ITEMS) if terms.empty?

      ranked_records = records.sort_by do |chunk|
        [ -text_match_score(chunk.text), -chunk.updated_at.to_i ]
      end
      return records.first(MAX_CONTEXT_ITEMS) if ranked_records.first && text_match_score(ranked_records.first.text).zero?

      ranked_records.first(MAX_CONTEXT_ITEMS)
    end

    def query_terms
      @query_terms ||= prompt.downcase
                             .scan(/[a-z0-9]{2,}/)
                             .uniq
                             .reject { |term| QUERY_TERM_STOPWORDS.include?(term) }
                             .first(10)
    end

    def workspace_chunks_scope
      accessible_chunks_base.where(workspace_id: workspace.id)
    end

    def account_chunks_scope
      accessible_chunks_base
    end

    def accessible_chunks_base
      workspace_ids = Pundit.policy_scope!(user, Workspace).select(:id)
      page_ids = accessible_pages_scope.select(:id)
      row_ids = accessible_rows_scope.select(:id)
      event_ids = accessible_kalendarium_events_scope.select(:id)
      meeting_ids = accessible_meeting_sessions_scope.select(:id)
      message_ids = accessible_epistularium_messages_scope.select(:id)
      base = SearchChunk.where(workspace_id: workspace_ids)

      SearchChunk.accessible_scope_from(
        base: base,
        page_ids: page_ids,
        row_ids: row_ids,
        event_ids: event_ids,
        meeting_ids: meeting_ids,
        message_ids: message_ids
      )
    end

    def accessible_pages_scope
      Pundit.policy_scope!(user, Page).active
    end

    def accessible_rows_scope
      Pundit.policy_scope!(user, DbRow).active
    end

    def accessible_kalendarium_events_scope
      Pundit.policy_scope!(user, KalendariumEvent)
    end

    def accessible_meeting_sessions_scope
      Pundit.policy_scope!(user, MeetingSession)
    end

    def accessible_epistularium_messages_scope
      return EpistulariumMessage.none unless ActiveRecord::Base.connection.data_source_exists?("epistularium_messages")

      Pundit.policy_scope!(user, EpistulariumMessage)
    end

    def context_entry_candidate_for_chunk(chunk)
      if chunk.page.present?
        {
          kind: "Page",
          title: chunk.page.title,
          excerpt: chunk.text,
          workspace_name: chunk.workspace.name,
          url: Rails.application.routes.url_helpers.page_path(workspace_slug: chunk.workspace.slug, id: chunk.page_id)
        }
      elsif chunk.db_row.present?
        database = chunk.database || chunk.db_row.database
        {
          kind: "Row",
          title: chunk.db_row.title.presence || database&.name || "Row",
          excerpt: chunk.text,
          workspace_name: chunk.workspace.name,
          url: Rails.application.routes.url_helpers.database_path(workspace_slug: chunk.workspace.slug, id: chunk.database_id, anchor: "row_#{chunk.db_row_id}")
        }
      elsif SearchChunk.reference_column_available?(:kalendarium_event_id) && chunk.kalendarium_event.present?
        event = chunk.kalendarium_event
        {
          kind: "Kalendarium event",
          title: event.title,
          excerpt: chunk.text,
          workspace_name: chunk.workspace.name,
          url: Rails.application.routes.url_helpers.kalendarium_path(
            workspace_slug: chunk.workspace.slug,
            view: "day",
            date: event.starts_at_utc.to_date.iso8601,
            anchor: "kalendarium_event_#{event.id}"
          )
        }
      elsif SearchChunk.reference_column_available?(:meeting_session_id) && chunk.meeting_session.present?
        session = chunk.meeting_session
        {
          kind: "Meeting session",
          title: session.title,
          excerpt: chunk.text,
          workspace_name: chunk.workspace.name,
          url: Rails.application.routes.url_helpers.workspace_meetings_path(
            workspace_slug: chunk.workspace.slug,
            anchor: "meeting_session_#{session.id}"
          )
        }
      elsif SearchChunk.reference_column_available?(:epistularium_message_id) && chunk.epistularium_message.present?
        message = chunk.epistularium_message
        {
          kind: "Email",
          title: message.display_subject,
          excerpt: chunk.text,
          workspace_name: chunk.workspace.name,
          url: Rails.application.routes.url_helpers.workspace_epistularium_message_path(
            workspace_slug: chunk.workspace.slug,
            id: message.id
          )
        }
      end
    end

    def finalize_context_entries(candidates)
      candidates.first(MAX_CONTEXT_ITEMS).map.with_index do |entry, index|
        entry.merge(index: index + 1)
      end
    end

    def select_top_text_chunks(chunks)
      return chunks.first(MAX_CONTEXT_ITEMS) if query_terms.empty?

      ranked_chunks = chunks.each_with_index.sort_by do |chunk_text, original_index|
        [ -text_match_score(chunk_text), original_index ]
      end
      return chunks.first(MAX_CONTEXT_ITEMS) if ranked_chunks.first && text_match_score(ranked_chunks.first.first).zero?

      ranked_chunks.first(MAX_CONTEXT_ITEMS)
                   .sort_by { |_chunk_text, original_index| original_index }
                   .map(&:first)
    end

    def rank_context_entry_candidates(entries)
      unique_entries = entries.uniq { |entry| [ entry[:kind], entry[:title], entry[:url], entry[:excerpt] ] }
      return unique_entries if query_terms.empty?

      ranked_entries = unique_entries.each_with_index.sort_by do |entry, original_index|
        [ -context_entry_match_score(entry), original_index ]
      end
      return unique_entries if ranked_entries.first && context_entry_match_score(ranked_entries.first.first).zero?

      ranked_entries.map(&:first)
    end

    def context_entry_match_score(entry)
      (text_match_score(entry[:title]) * 3) + (text_match_score(entry[:excerpt]) * 2)
    end

    def text_match_score(text)
      normalized_text = text.to_s.downcase
      return 0 if normalized_text.blank? || query_terms.empty?

      query_terms.sum { |term| normalized_text.scan(Regexp.new(Regexp.escape(term))).length }
    end

    def live_context_entry_candidates(resolved_scope:)
      return [] if query_terms.empty?

      entries = []
      entries.concat(live_page_context_entries(resolved_scope: resolved_scope))
      entries.concat(live_block_context_entries(resolved_scope: resolved_scope))
      entries.concat(live_db_row_context_entries(resolved_scope: resolved_scope))
      entries.concat(live_kalendarium_event_context_entries(resolved_scope: resolved_scope))
      entries.concat(live_meeting_session_context_entries(resolved_scope: resolved_scope))
      entries.concat(live_epistularium_message_context_entries(resolved_scope: resolved_scope))
      entries
    end

    def live_page_context_entries(resolved_scope:)
      scoped_pages_for(resolved_scope)
        .search_full_text(query_terms.join(" "))
        .distinct(false)
        .limit(4)
        .preload(:workspace)
        .map do |page|
          {
            kind: "Page",
            title: page.title,
            excerpt: relevant_excerpt(page.search_source_text),
            workspace_name: page.workspace.name,
            url: Rails.application.routes.url_helpers.page_path(workspace_slug: page.workspace.slug, id: page.id)
          }
        end
    end

    def live_block_context_entries(resolved_scope:)
      scoped_blocks_for(resolved_scope)
        .search_full_text(query_terms.join(" "))
        .distinct(false)
        .limit(8)
        .preload(:page, :workspace)
        .map do |block|
          {
            kind: "Block",
            title: block.page.title,
            excerpt: relevant_excerpt(block.search_text),
            workspace_name: block.workspace.name,
            url: "#{Rails.application.routes.url_helpers.page_path(workspace_slug: block.workspace.slug, id: block.page_id)}#block_#{block.id}"
          }
        end
    end

    def live_db_row_context_entries(resolved_scope:)
      scoped_rows_for(resolved_scope)
        .search_full_text(query_terms.join(" "))
        .distinct(false)
        .limit(4)
        .preload(:database, :workspace)
        .map do |row|
          {
            kind: "Row",
            title: row.title.presence || row.database.name,
            excerpt: relevant_excerpt(row.search_text),
            workspace_name: row.workspace.name,
            url: Rails.application.routes.url_helpers.database_path(workspace_slug: row.workspace.slug, id: row.database_id, anchor: "row_#{row.id}")
          }
        end
    end

    def live_kalendarium_event_context_entries(resolved_scope:)
      scoped_kalendarium_events_for(resolved_scope)
        .search_full_text(query_terms.join(" "))
        .distinct(false)
        .limit(4)
        .preload(:workspace)
        .map do |event|
          {
            kind: "Kalendarium event",
            title: event.title,
            excerpt: relevant_excerpt(event.search_source_text),
            workspace_name: event.workspace.name,
            url: Rails.application.routes.url_helpers.kalendarium_path(
              workspace_slug: event.workspace.slug,
              view: "day",
              date: event.starts_at_utc.to_date.iso8601,
              anchor: "kalendarium_event_#{event.id}"
            )
          }
        end
    end

    def live_meeting_session_context_entries(resolved_scope:)
      scoped_meeting_sessions_for(resolved_scope)
        .search_full_text(query_terms.join(" "))
        .distinct(false)
        .limit(4)
        .preload(:workspace)
        .map do |session|
          {
            kind: "Meeting session",
            title: session.title,
            excerpt: relevant_excerpt(session.search_source_text),
            workspace_name: session.workspace.name,
            url: Rails.application.routes.url_helpers.workspace_meetings_path(
              workspace_slug: session.workspace.slug,
              anchor: "meeting_session_#{session.id}"
            )
          }
        end
    end

    def scoped_pages_for(resolved_scope)
      scope = accessible_pages_scope
      return scope if resolved_scope == SCOPE_ACCOUNT

      scope.where(workspace_id: workspace.id)
    end

    def scoped_blocks_for(resolved_scope)
      scope = Pundit.policy_scope!(user, Block).active
      return scope if resolved_scope == SCOPE_ACCOUNT

      scope.where(workspace_id: workspace.id)
    end

    def scoped_rows_for(resolved_scope)
      scope = accessible_rows_scope
      return scope if resolved_scope == SCOPE_ACCOUNT

      scope.where(workspace_id: workspace.id)
    end

    def scoped_kalendarium_events_for(resolved_scope)
      scope = accessible_kalendarium_events_scope
      return scope if resolved_scope == SCOPE_ACCOUNT

      scope.where(workspace_id: workspace.id)
    end

    def scoped_meeting_sessions_for(resolved_scope)
      scope = accessible_meeting_sessions_scope
      return scope if resolved_scope == SCOPE_ACCOUNT

      scope.where(workspace_id: workspace.id)
    end

    def scoped_epistularium_messages_for(resolved_scope)
      scope = accessible_epistularium_messages_scope
      return scope if resolved_scope == SCOPE_ACCOUNT

      scope.where(workspace_id: workspace.id)
    end

    def live_epistularium_message_context_entries(resolved_scope:)
      scoped_epistularium_messages_for(resolved_scope)
        .search_full_text(query_terms.join(" "))
        .distinct(false)
        .limit(4)
        .preload(:workspace, :epistularium_account)
        .map do |message|
          {
            kind: "Email",
            title: message.display_subject,
            excerpt: relevant_excerpt(message.search_source_text),
            workspace_name: message.workspace.name,
            url: Rails.application.routes.url_helpers.workspace_epistularium_message_path(
              workspace_slug: message.workspace.slug,
              id: message.id
            )
          }
        end
    end

    def relevant_excerpt(text, max_words: 80)
      normalized = text.to_s.squish
      return "" if normalized.blank?

      words = normalized.split(/\s+/)
      return normalized if words.length <= max_words

      query_terms.each do |term|
        match_index = words.index { |word| word.downcase.include?(term) }
        next unless match_index

        start_index = [ match_index - (max_words / 3), 0 ].max
        excerpt_words = words[start_index, max_words]
        excerpt = excerpt_words.join(" ")
        excerpt = "... #{excerpt}" if start_index.positive?
        excerpt = "#{excerpt} ..." if (start_index + max_words) < words.length
        return excerpt
      end

      "#{words.first(max_words).join(' ')} ..."
    end

    def prompt_for(context_entries, resolved_scope)
      context_lines = context_entries.map do |entry|
        "[#{entry[:index]}] Workspace=#{entry[:workspace_name]}; Kind=#{entry[:kind]}; Title=#{entry[:title]}; Excerpt=#{entry[:excerpt]}"
      end

      <<~PROMPT
        You are Notae AI. Answer only from provided context snippets.
        Supported question types:
        - Search check questions (example: "is Mac mentioned in this document?"): answer yes/no then explain briefly.
        - Summary requests: provide concise bullet points.
        If the context is insufficient, say what is missing.
        Always include citations like [n] that map to context entries.
        Keep responses concise and factual.

        Scope: #{resolved_scope}
        Question: #{prompt}

        Context:
        #{context_lines.join("\n")}
      PROMPT
    end

    def draft_request_for_prompt
      normalized = prompt.downcase
      if normalized.match?(/\b(email|e-mail|mail|reply)\b/)
        return { draft_type: "email_draft", target_system: "email" }
      end
      if normalized.match?(/\b(github|pull request|pull-request|pr|issue)\b/) && normalized.match?(/\b(comment|reply|response)\b/)
        return { draft_type: "github_comment_draft", target_system: "github" }
      end
      if normalized.match?(/\b(calendar|meeting|invite|hold|time slot|timeslot)\b/) &&
         normalized.match?(/\b(draft|create|prepare|schedule|book|reserve|hold)\b/)
        return { draft_type: "calendar_hold", target_system: "calendar" }
      end
      if normalized.match?(/\b(nota|note|page|brief)\b/) &&
         normalized.match?(/\b(draft|create|prepare|write|save)\b/)
        return { draft_type: "nota_draft", target_system: "notae" }
      end
      return nil unless normalized.match?(/\b(ticket|task|todo|to-do|action item|handoff)\b/)

      {
        draft_type: "task_ticket",
        target_system: task_ticket_target_system_for_prompt(normalized)
      }
    end

    def task_ticket_target_system_for_prompt(normalized_prompt)
      return "github" if normalized_prompt.match?(/\bgithub\b|\brepo\b|\bissue\b|\bpr\b|\bpull request\b/)
      return "slack" if normalized_prompt.match?(/\bslack\b|\bchannel\b|\bthread\b/)

      "crm"
    end

    def draft_action_prompt_for(resolved_scope:, requested_draft:, context_entries:)
      context_lines = context_entries.map do |entry|
        "[#{entry[:index]}] Workspace=#{entry[:workspace_name]}; Kind=#{entry[:kind]}; Title=#{entry[:title]}; Excerpt=#{entry[:excerpt]}"
      end

      <<~PROMPT
        You are Notae AI creating a non-destructive draft action for human review.
        Return valid JSON only with these top-level keys:
        - title: short review title
        - summary: one concise sentence describing the created draft
        - payload: object that matches the requested draft schema
        - used_source_indices: array of integer context entry ids you relied on

        Requested target system: #{requested_draft.fetch(:target_system)}
        Requested draft type: #{requested_draft.fetch(:draft_type)}
        Scope: #{resolved_scope}

        Draft schema requirements:
        - email_draft payload: to (array), cc (array), subject (string), body (string)
        - github_comment_draft payload: repository (string), target_reference (string), body (string)
        - task_ticket payload: project (string), title (string), body (string), assignee (string optional), due_at (string optional)
        - calendar_hold payload: title (string), starts_at (ISO-like datetime string), ends_at (ISO-like datetime string), attendees (array), body (string optional)
        - nota_draft payload: title (string), body (string)

        Rules:
        - Use workspace context when it helps.
        - Keep payload practical and editable.
        - Do not invent citations inside summary text.
        - If context is thin, still generate the best safe draft from the user's request.
        - Do not include markdown fences or prose outside JSON.

        User request:
        #{prompt}

        Context:
        #{context_lines.join("\n")}
      PROMPT
    end

    def parse_json_object(raw_text)
      text = raw_text.to_s.strip
      return {} if text.blank?

      JSON.parse(text)
    rescue JSON::ParserError
      match = text.match(/\{.*\}/m)
      raise unless match

      JSON.parse(match[0])
    end

    def normalize_ai_draft_payload(payload:, requested_draft:, parsed_title:)
      normalized_payload = payload.respond_to?(:to_h) ? payload.to_h.stringify_keys : {}
      case requested_draft.fetch(:draft_type)
      when "email_draft"
        {
          "to" => normalize_string_array(normalized_payload["to"] || normalized_payload["recipients"]),
          "cc" => normalize_string_array(normalized_payload["cc"]),
          "subject" => normalized_payload["subject"].to_s.strip,
          "body" => normalized_payload["body"].to_s
        }
      when "github_comment_draft"
        {
          "repository" => normalized_payload["repository"].to_s.strip,
          "target_reference" => normalized_payload["target_reference"].presence || normalized_payload["issue"].presence || normalized_payload["pull_request"].presence,
          "body" => normalized_payload["body"].to_s
        }.transform_values { |value| value.is_a?(String) ? value.strip : value }
      when "calendar_hold"
        {
          "title" => normalized_payload["title"].presence || parsed_title.to_s.strip,
          "starts_at" => normalized_payload["starts_at"].to_s.strip,
          "ends_at" => normalized_payload["ends_at"].to_s.strip,
          "attendees" => normalize_string_array(normalized_payload["attendees"]),
          "body" => normalized_payload["body"].to_s
        }
      when "nota_draft"
        {
          "title" => normalized_payload["title"].presence || parsed_title.to_s.strip,
          "body" => normalized_payload["body"].to_s
        }
      else
        {
          "project" => normalized_payload["project"].to_s.strip,
          "title" => normalized_payload["title"].presence || parsed_title.to_s.strip,
          "body" => normalized_payload["body"].to_s,
          "assignee" => normalized_payload["assignee"].to_s.strip,
          "due_at" => normalized_payload["due_at"].to_s.strip
        }
      end
    end

    def normalize_string_array(value)
      Array(value).flat_map { |entry| entry.to_s.split(/\r?\n|,/) }.map(&:strip).reject(&:blank?).uniq
    end

    def normalized_source_indices(raw_indices, context_entries)
      Array(raw_indices).map(&:to_i).select { |index| index.between?(1, context_entries.length) }.uniq
    end

    def source_snapshot_for_indices(source_indices, context_entries)
      source_indices.map do |index|
        context_entries[index - 1].slice(:index, :title, :kind, :url, :workspace_name)
      end
    end

    def draft_title_for(parsed:, payload:, requested_draft:)
      parsed["title"].to_s.strip.presence ||
        payload["title"].to_s.strip.presence ||
        payload["subject"].to_s.strip.presence ||
        "#{requested_draft.fetch(:draft_type).humanize} review"
    end

    def default_draft_summary_for(requested_draft:, agent_action:)
      case requested_draft.fetch(:draft_type)
      when "email_draft"
        "Created an email draft for review: #{agent_action.title}."
      when "github_comment_draft"
        "Created a GitHub comment draft for review: #{agent_action.title}."
      when "calendar_hold"
        "Created a calendar hold draft for review: #{agent_action.title}."
      when "nota_draft"
        "Created a Nota draft for review: #{agent_action.title}."
      else
        "Created a task draft for review: #{agent_action.title}."
      end
    end

    def review_source_for(agent_action)
      {
        index: nil,
        title: "Review draft action",
        kind: "Draft action",
        url: Rails.application.routes.url_helpers.agent_action_path(
          workspace_slug: agent_action.workspace.slug,
          id: agent_action.id
        ),
        workspace_name: agent_action.workspace.name
      }
    end

    def general_prompt_for(resolved_scope:)
      <<~PROMPT
        You are Notae AI.
        Answer the user directly using general knowledge.
        Keep the answer concise and practical.
        If the request asks for a definition, provide a short definition first.
        If the request asks for alternative words or synonyms, provide a short list.
        Do not include citation markers like [1].

        Scope: #{resolved_scope}
        Question: #{prompt}
      PROMPT
    end

    def live_web_prompt_for(resolved_scope:)
      <<~PROMPT
        You are Notae AI.
        Answer the user's question using current web information when needed.
        Keep the answer concise, practical, and directly responsive.
        If the question depends on a location, account, or other missing detail, ask one short clarifying question instead of guessing.
        Do not include raw URLs or citation markers in the answer body.

        Scope: #{resolved_scope}
        Question: #{prompt}
      PROMPT
    end

    def web_search_tool
      tool = { type: WEB_SEARCH_TOOL_TYPE }
      timezone_name = user_time_zone&.tzinfo&.name.presence
      if timezone_name.present?
        tool[:user_location] = {
          type: "approximate",
          timezone: timezone_name
        }
      end
      tool
    end

    def writing_prompt_for(resolved_scope:, resolved_intent:)
      context_lines = []
      context_lines << "Scope: #{resolved_scope}"
      if current_page.present?
        context_lines << "Current page: #{current_page.title}"
      end
      if target_block.present?
        context_lines << "Target block type: #{target_block.block_type}"
      end
      if target_block_text.present?
        context_lines << "Target block text:\n#{target_block_text}"
      end

      instruction =
        if resolved_intent == INTENT_SUGGEST_EDITS
          "Rewrite the target text so it reads better while preserving meaning. Fix grammar, spelling, punctuation, and awkward phrasing."
        else
          "Generate paste-ready text that satisfies the request. Keep wording clean and natural."
        end

      <<~PROMPT
        You are Notae AI.
        #{instruction}
        Return only the final text and no preamble.

        #{context_lines.join("\n")}

        User request:
        #{prompt}
      PROMPT
    end

    def current_page
      return @current_page if defined?(@current_page)
      return @current_page = nil if current_page_id.blank?

      @current_page = current_workspace_pages_scope.find_by(id: current_page_id)
    end

    def current_workspace_pages_scope
      accessible_pages_scope.where(workspace_id: workspace.id)
    end

    def target_block_text
      @target_block_text ||= target_block&.search_text.to_s.squish.presence
    end

    def normalize_citations(text, max_index)
      cleaned = text.gsub(/\[(\d+)\]/) do |_match|
        index = Regexp.last_match(1).to_i
        index.between?(1, max_index) ? "[#{index}]" : ""
      end
      cleaned = cleaned.gsub(/[ \t]+\n/, "\n").gsub(/[ \t]{2,}/, " ").strip

      used_indices = cleaned.scan(/\[(\d+)\]/).flatten.map(&:to_i).uniq
      if used_indices.empty?
        used_indices = [ 1 ]
        cleaned = "#{cleaned} [1]".strip
      end

      [ cleaned, used_indices ]
    end

    def unavailable(reason)
      @unavailable_reason = reason
      nil
    end

    def assistant_api_key
      @assistant_api_key ||= Openai::CredentialResolver.resolve(user: user)
    end
  end
end
