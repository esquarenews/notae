module Search
  class WorkspaceSearchService
    Result = Struct.new(:kind, :title, :excerpt, :url, :score, keyword_init: true)

    SEMANTIC_CANDIDATE_LIMIT = 220
    SEMANTIC_EMBEDDING_BATCH_LIMIT = 80
    SEMANTIC_RESULT_LIMIT = 12

    def initialize(user:, workspace:, query:)
      @user = user
      @workspace = workspace
      @query = query.to_s.strip
    end

    def call
      return [] if query.blank?

      merge_and_rank_results(
        page_results +
        block_results +
        db_row_results +
        kalendarium_event_results +
        meeting_session_results +
        epistularium_message_results +
        semantic_chunk_results
      )
    end

    private

    attr_reader :user, :workspace, :query

    def page_results
      Pundit.policy_scope!(user, Page)
            .for_workspace(workspace)
            .active
            .distinct(false)
            .search_full_text(query)
            .includes(:parent_page, :linked_database)
            .limit(15)
            .map do |page|
        Result.new(
          kind: page_result_kind(page),
          title: page_result_title(page),
          excerpt: highlighted_excerpt(page.tab_child? ? page.tab_reference_title : page.title),
          url: page_result_url(page),
          score: 30
        )
      end
    end

    def block_results
      Pundit.policy_scope!(user, Block)
            .for_workspace(workspace)
            .active
            .search_full_text(query)
            .includes(page: [ :parent_page, :linked_database ])
            .limit(20)
            .map do |block|
        Result.new(
          kind: block.page.tab_child? ? "Tab block" : "Block",
          title: page_result_title(block.page),
          excerpt: highlighted_excerpt(block.search_text),
          url: "#{page_result_url(block.page)}#block_#{block.id}",
          score: 20
        )
      end
    end

    def db_row_results
      Pundit.policy_scope!(user, DbRow)
            .for_workspace(workspace)
            .active
            .search_full_text(query)
            .includes(database: { linked_page: :parent_page })
            .limit(15)
            .map do |row|
        Result.new(
          kind: row.database.tab_child? ? "Grid tab row" : "Row",
          title: row_result_title(row, row.database),
          excerpt: highlighted_excerpt(row.search_text),
          url: Rails.application.routes.url_helpers.database_path(workspace_slug: workspace.slug, id: row.database_id, anchor: "row_#{row.id}"),
          score: 10
        )
      end
    end

    def kalendarium_event_results
      Pundit.policy_scope!(user, KalendariumEvent)
            .for_workspace(workspace)
            .search_full_text(query)
            .includes(:kalendarium_project)
            .limit(15)
            .map do |event|
        event_date = event.starts_at_utc.in_time_zone(user.time_zone).strftime("%b %-d %H:%M")
        Result.new(
          kind: "Kalendarium event",
          title: event.title,
          excerpt: highlighted_excerpt([ event.description, event.location, event.kalendarium_project&.name, event_date ].compact.join(" · ")),
          url: Rails.application.routes.url_helpers.kalendarium_path(
            workspace_slug: workspace.slug,
            view: "day",
            date: event.starts_at_utc.to_date.iso8601,
            anchor: "kalendarium_event_#{event.id}"
          ),
          score: 18
        )
      end
    end

    def meeting_session_results
      Pundit.policy_scope!(user, MeetingSession)
            .for_workspace(workspace)
            .search_full_text(query)
            .limit(12)
            .map do |session|
        Result.new(
          kind: "Meeting session",
          title: session.title,
          excerpt: highlighted_excerpt([ session.summary_markdown, session.transcript_text ].compact.join(" · ")),
          url: Rails.application.routes.url_helpers.workspace_meetings_path(workspace_slug: workspace.slug, anchor: "meeting_session_#{session.id}"),
          score: 16
        )
      end
    end

    def epistularium_message_results
      return [] unless ActiveRecord::Base.connection.data_source_exists?("epistularium_messages")

      Pundit.policy_scope!(user, EpistulariumMessage)
            .for_workspace(workspace)
            .search_full_text(query)
            .includes(:epistularium_account)
            .limit(15)
            .map do |message|
        Result.new(
          kind: "Email",
          title: message.display_subject,
          excerpt: highlighted_excerpt([ message.from_display, message.snippet, message.body_text ].compact.join(" · ")),
          url: Rails.application.routes.url_helpers.workspace_epistularium_message_path(workspace_slug: workspace.slug, id: message.id),
          score: 18
        )
      end
    end

    def semantic_chunk_results
      return [] unless user.openai_api_key_configured?
      return [] unless semantic_ai_allowed?

      query_embedding = embed_query
      return [] if query_embedding.empty?

      chunks = semantic_candidates
      return [] if chunks.empty?

      schedule_chunk_embedding_backfill!(chunks)
      rankable_chunks = chunks.select(&:has_embedding?)
      return [] if rankable_chunks.empty?

      rankable_chunks.filter_map do |chunk|
        similarity = cosine_similarity(query_embedding, chunk.embedding_vector)
        next if similarity.nil? || similarity <= 0.2

        build_semantic_result(chunk, similarity)
      end
            .sort_by { |result| -result.score.to_f }
            .first(SEMANTIC_RESULT_LIMIT)
    rescue Openai::EmbeddingsClient::Error => e
      Rails.logger.warn("Semantic search disabled for workspace=#{workspace.id}: #{e.message}")
      []
    end

    def semantic_candidates
      scope = accessible_semantic_chunks_scope
      patterns = query_terms.first(5).map { |term| "%#{ActiveRecord::Base.sanitize_sql_like(term)}%" }

      if patterns.any?
        where_clause = patterns.map { "search_chunks.text ILIKE ?" }.join(" OR ")
        scope = scope.where([ where_clause, *patterns ])
      end

      scope.includes(SearchChunk.context_preload_associations)
           .order(updated_at: :desc)
           .limit(SEMANTIC_CANDIDATE_LIMIT)
           .to_a
    end

    def accessible_semantic_chunks_scope
      page_ids = Pundit.policy_scope!(user, Page).for_workspace(workspace).active.select(:id)
      row_ids = Pundit.policy_scope!(user, DbRow).for_workspace(workspace).active.select(:id)
      event_ids = Pundit.policy_scope!(user, KalendariumEvent).for_workspace(workspace).select(:id)
      meeting_ids = Pundit.policy_scope!(user, MeetingSession).for_workspace(workspace).select(:id)
      message_ids =
        if ActiveRecord::Base.connection.data_source_exists?("epistularium_messages")
          Pundit.policy_scope!(user, EpistulariumMessage).for_workspace(workspace).select(:id)
        end
      workspace_scope = SearchChunk.for_workspace(workspace)

      SearchChunk.accessible_scope_from(
        base: workspace_scope,
        page_ids: page_ids,
        row_ids: row_ids,
        event_ids: event_ids,
        meeting_ids: meeting_ids,
        message_ids: message_ids
      )
    end

    def embed_query
      response = Openai::EmbeddingsClient.embed_with_usage(
        text: query,
        api_key: user.openai_api_key,
        model: SearchChunk::EMBEDDING_MODEL
      )
      log_embedding_usage!(
        usage: response[:usage],
        operation: AiUsageLog::OP_SEMANTIC_QUERY,
        metadata: { query_length: query.length }
      )

      response[:embedding]
    end

    def schedule_chunk_embedding_backfill!(chunks)
      missing_chunks = chunks.select { |chunk| !chunk.has_embedding? }
                             .first(SEMANTIC_EMBEDDING_BATCH_LIMIT)
      return if missing_chunks.empty?

      Search::BackfillChunkEmbeddingsJob.perform_later(
        user.id,
        workspace.id,
        missing_chunks.map(&:id)
      )
    rescue StandardError => error
      raise unless Queueing::JobEnqueueSafety.queue_unavailable?(error)

      Rails.logger.warn("Skipping semantic embedding backfill enqueue workspace=#{workspace.id}: #{error.class}: #{error.message}")
    end

    def build_semantic_result(chunk, similarity)
      if chunk.page.present?
        Result.new(
          kind: page_result_kind(chunk.page),
          title: page_result_title(chunk.page),
          excerpt: highlighted_excerpt(chunk.text),
          url: page_result_url(chunk.page),
          score: 36 + (similarity * 12)
        )
      elsif chunk.db_row.present?
        database = chunk.database || chunk.db_row.database

        Result.new(
          kind: database&.tab_child? ? "Grid tab row" : "Row",
          title: row_result_title(chunk.db_row, database),
          excerpt: highlighted_excerpt(chunk.text),
          url: Rails.application.routes.url_helpers.database_path(workspace_slug: workspace.slug, id: chunk.database_id, anchor: "row_#{chunk.db_row_id}"),
          score: 30 + (similarity * 12)
        )
      elsif SearchChunk.reference_column_available?(:kalendarium_event_id) && chunk.kalendarium_event.present?
        event = chunk.kalendarium_event
        Result.new(
          kind: "Kalendarium event",
          title: event.title,
          excerpt: highlighted_excerpt(chunk.text),
          url: Rails.application.routes.url_helpers.kalendarium_path(
            workspace_slug: workspace.slug,
            view: "day",
            date: event.starts_at_utc.to_date.iso8601,
            anchor: "kalendarium_event_#{event.id}"
          ),
          score: 30 + (similarity * 12)
        )
      elsif SearchChunk.reference_column_available?(:meeting_session_id) && chunk.meeting_session.present?
        session = chunk.meeting_session
        Result.new(
          kind: "Meeting session",
          title: session.title,
          excerpt: highlighted_excerpt(chunk.text),
          url: Rails.application.routes.url_helpers.workspace_meetings_path(workspace_slug: workspace.slug, anchor: "meeting_session_#{session.id}"),
          score: 30 + (similarity * 12)
        )
      elsif SearchChunk.reference_column_available?(:epistularium_message_id) && chunk.epistularium_message.present?
        message = chunk.epistularium_message
        Result.new(
          kind: "Email",
          title: message.display_subject,
          excerpt: highlighted_excerpt(chunk.text),
          url: Rails.application.routes.url_helpers.workspace_epistularium_message_path(workspace_slug: workspace.slug, id: message.id),
          score: 30 + (similarity * 12)
        )
      end
    end

    def cosine_similarity(query_vector, chunk_vector)
      return nil if query_vector.empty? || chunk_vector.empty?
      return nil unless query_vector.length == chunk_vector.length

      dot_product = 0.0
      query_norm = 0.0
      chunk_norm = 0.0

      query_vector.each_with_index do |query_value, index|
        chunk_value = chunk_vector[index]
        dot_product += (query_value * chunk_value)
        query_norm += (query_value**2)
        chunk_norm += (chunk_value**2)
      end

      denominator = Math.sqrt(query_norm) * Math.sqrt(chunk_norm)
      return nil if denominator.zero?

      dot_product / denominator
    end

    def merge_and_rank_results(results)
      best_by_target = {}

      results.each do |result|
        key = [ result.kind, result.url ]
        current = best_by_target[key]
        best_by_target[key] = result if current.nil? || result.score.to_f > current.score.to_f
      end

      best_by_target.values.sort_by { |result| -reranked_score(result) }
    end

    def reranked_score(result)
      score = result.score.to_f
      title = result.title.to_s.downcase
      excerpt = ActionView::Base.full_sanitizer.sanitize(result.excerpt.to_s).downcase

      query_terms.each do |term|
        token = term.downcase
        score += 1.8 if title.include?(token)
        score += 0.8 if excerpt.include?(token)
      end

      score += 2.4 if title == query.downcase
      score
    end

    def page_result_kind(page)
      return "Grid tab" if page.tab_child? && page.linked_database.present?
      return "Grid" if page.linked_database.present?
      return "Page" unless page.tab_child?

      "Tab"
    end

    def page_result_title(page)
      page.tab_child? ? page.tab_reference_title : page.title
    end

    def page_result_url(page)
      if page.linked_database.present?
        Rails.application.routes.url_helpers.database_path(workspace_slug: workspace.slug, id: page.linked_database.id)
      else
        Rails.application.routes.url_helpers.page_path(workspace_slug: workspace.slug, id: page.id)
      end
    end

    def row_result_title(row, database)
      return row.title.presence || "Row" if database.blank?
      return row.title.presence || database.name unless database.tab_child?

      row_title = row.title.presence
      return database.tab_reference_title if row_title.blank?

      "#{row_title} · #{database.tab_reference_title}"
    end

    def highlighted_excerpt(text)
      compact = text.to_s.squish
      return "" if compact.blank?

      ActionController::Base.helpers.highlight(
        compact.truncate(220),
        query_terms,
        highlighter: "<mark>\\1</mark>"
      )
    end

    def query_terms
      @query_terms ||= query.split(/\s+/).reject(&:blank?).uniq
    end

    def semantic_ai_allowed?
      return false unless Search::AiBudgetGuard.within_daily_budget?(user: user, workspace: workspace)
      return false unless Search::AiRateLimiter.allowed?(user: user, workspace: workspace, operation: "semantic_search")

      true
    end

    def log_embedding_usage!(usage:, operation:, metadata:)
      Search::AiUsageLogger.log!(
        user: user,
        workspace: workspace,
        operation: operation,
        model: SearchChunk::EMBEDDING_MODEL,
        usage: usage,
        metadata: metadata
      )
    end
  end
end
