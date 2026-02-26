module Search
  class AssistantQueryService
    Response = Struct.new(:answer, :sources, :scope, keyword_init: true)

    SCOPE_AUTO = "auto"
    SCOPE_DOCUMENT = "document"
    SCOPE_WORKSPACE = "workspace"
    SCOPE_ACCOUNT = "account"
    SCOPE_OPTIONS = [
      [ "Auto", SCOPE_AUTO ],
      [ "This document only", SCOPE_DOCUMENT ],
      [ "This workspace only", SCOPE_WORKSPACE ],
      [ "Whole account", SCOPE_ACCOUNT ]
    ].freeze

    MODEL = "gpt-4o-mini"
    MAX_CONTEXT_ITEMS = 12

    attr_reader :unavailable_reason

    def initialize(user:, workspace:, prompt:, scope:, current_page_id: nil)
      @user = user
      @workspace = workspace
      @prompt = prompt.to_s.strip
      @scope = scope.to_s
      @current_page_id = current_page_id
      @unavailable_reason = nil
    end

    def call
      return unavailable(:missing_prompt) if prompt.blank?
      return unavailable(:missing_api_key) unless user.openai_api_key_configured?
      return unavailable(:budget_exceeded) unless Search::AiBudgetGuard.within_daily_budget?(user: user, workspace: workspace)
      return unavailable(:rate_limited) unless Search::AiRateLimiter.allowed?(user: user, workspace: workspace, operation: "answer_generation")

      resolved_scope = resolve_scope
      context_entries = build_context_entries(resolved_scope)
      return unavailable(:no_context) if context_entries.empty?

      response = Openai::ResponsesClient.generate_text_with_usage(
        prompt: prompt_for(context_entries, resolved_scope),
        api_key: user.openai_api_key,
        model: MODEL,
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
        model: MODEL,
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
        scope: resolved_scope
      )
    rescue Openai::ResponsesClient::Error => e
      Rails.logger.warn("AI assistant query failed for workspace=#{workspace.id}: #{e.message}")
      unavailable(:provider_error)
    end

    private

    attr_reader :user, :workspace, :prompt, :scope, :current_page_id

    def resolve_scope
      return SCOPE_DOCUMENT if scope == SCOPE_AUTO && current_page_id.present?
      return SCOPE_WORKSPACE if scope == SCOPE_AUTO

      [ SCOPE_DOCUMENT, SCOPE_WORKSPACE, SCOPE_ACCOUNT ].include?(scope) ? scope : SCOPE_WORKSPACE
    end

    def build_context_entries(resolved_scope)
      case resolved_scope
      when SCOPE_DOCUMENT
        document_context_entries
      when SCOPE_ACCOUNT
        chunk_context_entries(scope: account_chunks_scope)
      else
        chunk_context_entries(scope: workspace_chunks_scope)
      end
    end

    def document_context_entries
      page = accessible_pages_scope.find_by(id: current_page_id)
      return [] if page.blank?

      text = [ page.title, page.blocks.active.ordered.pluck(:search_text).join("\n") ].join("\n").squish
      chunks = Search::TextChunker.call(text, target_words: 150, overlap_words: 25).first(MAX_CONTEXT_ITEMS)

      chunks.map.with_index do |chunk_text, index|
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

    def chunk_context_entries(scope:)
      chunks = select_top_chunks(scope)
      chunks.each_with_index.map { |chunk, index| context_entry_for_chunk(chunk, index + 1) }.compact
    end

    def select_top_chunks(scope)
      terms = query_terms
      records = scope.includes(:workspace, :page, db_row: :database).order(updated_at: :desc).limit(220).to_a
      return records.first(MAX_CONTEXT_ITEMS) if terms.empty?

      records.sort_by do |chunk|
        text = chunk.text.to_s.downcase
        score = terms.sum { |term| text.split(term).length - 1 }
        [ -score, -chunk.updated_at.to_i ]
      end.first(MAX_CONTEXT_ITEMS)
    end

    def query_terms
      @query_terms ||= prompt.downcase.scan(/[a-z0-9]{3,}/).uniq.first(8)
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
      base = SearchChunk.where(workspace_id: workspace_ids)

      base.where(page_id: page_ids).or(base.where(db_row_id: row_ids))
    end

    def accessible_pages_scope
      Pundit.policy_scope!(user, Page).active
    end

    def accessible_rows_scope
      Pundit.policy_scope!(user, DbRow).active
    end

    def context_entry_for_chunk(chunk, index)
      if chunk.page.present?
        {
          index: index,
          kind: "Page",
          title: chunk.page.title,
          excerpt: chunk.text,
          workspace_name: chunk.workspace.name,
          url: Rails.application.routes.url_helpers.page_path(workspace_slug: chunk.workspace.slug, id: chunk.page_id)
        }
      elsif chunk.db_row.present?
        database = chunk.database || chunk.db_row.database
        {
          index: index,
          kind: "Row",
          title: chunk.db_row.title.presence || database&.name || "Row",
          excerpt: chunk.text,
          workspace_name: chunk.workspace.name,
          url: Rails.application.routes.url_helpers.database_path(workspace_slug: chunk.workspace.slug, id: chunk.database_id, anchor: "row_#{chunk.db_row_id}")
        }
      end
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
  end
end
