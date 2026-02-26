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

      merge_and_rank_results(page_results + block_results + db_row_results + semantic_chunk_results)
    end

    private

    attr_reader :user, :workspace, :query

    def page_results
      Pundit.policy_scope!(user, Page)
            .for_workspace(workspace)
            .active
            .distinct(false)
            .search_full_text(query)
            .limit(15)
            .map do |page|
        Result.new(
          kind: "Page",
          title: page.title,
          excerpt: highlighted_excerpt(page.title),
          url: Rails.application.routes.url_helpers.page_path(workspace_slug: workspace.slug, id: page.id),
          score: 30
        )
      end
    end

    def block_results
      Pundit.policy_scope!(user, Block)
            .for_workspace(workspace)
            .active
            .search_full_text(query)
            .includes(:page)
            .limit(20)
            .map do |block|
        Result.new(
          kind: "Block",
          title: block.page.title,
          excerpt: highlighted_excerpt(block.search_text),
          url: "#{Rails.application.routes.url_helpers.page_path(workspace_slug: workspace.slug, id: block.page_id)}#block_#{block.id}",
          score: 20
        )
      end
    end

    def db_row_results
      Pundit.policy_scope!(user, DbRow)
            .for_workspace(workspace)
            .active
            .search_full_text(query)
            .includes(:database)
            .limit(15)
            .map do |row|
        Result.new(
          kind: "Row",
          title: row.title.presence || row.database.name,
          excerpt: highlighted_excerpt(row.search_text),
          url: Rails.application.routes.url_helpers.database_path(workspace_slug: workspace.slug, id: row.database_id, anchor: "row_#{row.id}"),
          score: 10
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

      scope.includes(:page, db_row: :database)
           .order(updated_at: :desc)
           .limit(SEMANTIC_CANDIDATE_LIMIT)
           .to_a
    end

    def accessible_semantic_chunks_scope
      page_ids = Pundit.policy_scope!(user, Page).for_workspace(workspace).active.select(:id)
      row_ids = Pundit.policy_scope!(user, DbRow).for_workspace(workspace).active.select(:id)
      workspace_scope = SearchChunk.for_workspace(workspace)

      workspace_scope.where(page_id: page_ids)
                     .or(workspace_scope.where(db_row_id: row_ids))
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
    end

    def build_semantic_result(chunk, similarity)
      if chunk.page.present?
        Result.new(
          kind: "Page",
          title: chunk.page.title,
          excerpt: highlighted_excerpt(chunk.text),
          url: Rails.application.routes.url_helpers.page_path(workspace_slug: workspace.slug, id: chunk.page_id),
          score: 36 + (similarity * 12)
        )
      elsif chunk.db_row.present?
        database = chunk.database || chunk.db_row.database

        Result.new(
          kind: "Row",
          title: chunk.db_row.title.presence || database&.name || "Row",
          excerpt: highlighted_excerpt(chunk.text),
          url: Rails.application.routes.url_helpers.database_path(workspace_slug: workspace.slug, id: chunk.database_id, anchor: "row_#{chunk.db_row_id}"),
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
