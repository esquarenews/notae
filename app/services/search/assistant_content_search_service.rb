module Search
  class AssistantContentSearchService
    Result = Struct.new(
      :kind,
      :title,
      :excerpt,
      :url,
      :score,
      :workspace_id,
      :workspace_name,
      :source_type,
      :source_id,
      :media,
      keyword_init: true
    )

    SCOPE_DOCUMENT = "document"
    SCOPE_WORKSPACE = "workspace"
    SCOPE_ACCOUNT = "account"
    SCOPES = [ SCOPE_DOCUMENT, SCOPE_WORKSPACE, SCOPE_ACCOUNT ].freeze

    MEDIA_BLOCK_TYPES = %w[image video file embed].freeze
    RESULT_LIMIT = 40
    SEMANTIC_RESULT_LIMIT = 16
    SEMANTIC_EMBEDDING_BATCH_LIMIT = 80
    SEMANTIC_SIMILARITY_THRESHOLD = 0.2
    QUERY_STOPWORDS = %w[
      a across all an and are as at be by can did do does find for from give has have how i in
      inside into is it locate look looking me my need notae of on or our please search show
      that the their this to want was what when where which who whole why will with within
      workspace app account document nota page
    ].freeze

    def initialize(user:, workspace:, query:, scope:, page: nil, current_page_id: nil, limit: RESULT_LIMIT)
      @user = user
      @workspace = workspace
      @query = query.to_s.squish
      @scope = scope.to_s
      @page_id = page.respond_to?(:id) ? page.id : (page.presence || current_page_id)
      @limit = limit.to_i.positive? ? limit.to_i : RESULT_LIMIT
    end

    def call
      return [] if query.blank?
      raise ArgumentError, "Unsupported assistant content search scope: #{scope}" unless SCOPES.include?(scope)
      return [] if scoped_workspaces.empty?

      merge_and_rank(lexical_results + media_results + semantic_results).first(limit)
    end

    private

    attr_reader :user, :workspace, :query, :scope, :page_id, :limit

    def lexical_results
      scoped_workspaces.flat_map do |target_workspace|
        results = Search::WorkspaceSearchService.new(
          user: user,
          workspace: target_workspace,
          query: lexical_query,
          semantic: false
        ).call
        results = filter_document_results(results) if document_scope?

        results.map { |result| wrap_lexical_result(result, target_workspace) }
      end
    end

    def filter_document_results(results)
      target_url = page_url_for(document_page)
      results.select { |result| result.url.to_s.split("#", 2).first == target_url }
    end

    def wrap_lexical_result(result, target_workspace)
      Result.new(
        kind: result.kind,
        title: result.title,
        excerpt: result.excerpt,
        url: result.url,
        score: result.score,
        workspace_id: target_workspace.id,
        workspace_name: target_workspace.name,
        source_type: source_type_for_kind(result.kind),
        source_id: nil,
        media: nil
      )
    end

    def media_results
      return [] if query_terms.empty?

      patterns = query_term_variants.map { |term| "%#{ActiveRecord::Base.sanitize_sql_like(term)}%" }
      predicate = patterns.map { "#{media_search_expression} ILIKE ?" }.join(" OR ")

      media_blocks_scope
        .where([ predicate, *patterns ])
        .distinct
        .order(updated_at: :desc)
        .limit([ limit * 3, 120 ].min)
        .preload(:page, :workspace, asset_attachment: :blob)
        .map { |block| build_media_result(block) }
    end

    def media_blocks_scope
      relation = Pundit.policy_scope!(user, Block)
                       .active
                       .where(workspace_id: scoped_workspace_ids, block_type: MEDIA_BLOCK_TYPES)
                       .joins(:page, :workspace)
                       .where(pages: { archived_at: nil })
                       .left_outer_joins(asset_attachment: :blob)
      relation = relation.where(page_id: document_page.id) if document_scope?
      relation
    end

    def media_search_expression
      <<~SQL.squish
        CONCAT_WS(
          ' ',
          blocks.search_text,
          blocks.block_type,
          'media',
          CASE WHEN active_storage_blobs.id IS NULL THEN NULL ELSE 'attachment' END,
          blocks.embed_url,
          active_storage_blobs.filename,
          active_storage_blobs.content_type,
          pages.title,
          workspaces.name
        )
      SQL
    end

    def build_media_result(block)
      metadata = media_metadata(block)
      kind = block.block_type.to_s.humanize
      title = metadata[:filename].presence || embed_title(block).presence || "#{kind} in #{block.page.title}"

      Result.new(
        kind: kind,
        title: title,
        excerpt: highlighted_excerpt(
          [ block.searchable_content, block.page.title, block.workspace.name ].filter_map(&:presence).join(" · ")
        ),
        url: metadata[:page_url] + "#block_#{block.id}",
        score: 42 + lexical_match_score([ title, block.searchable_content, block.page.title ].join(" ")),
        workspace_id: block.workspace_id,
        workspace_name: block.workspace.name,
        source_type: "media",
        source_id: block.id,
        media: metadata
      )
    end

    def media_metadata(block)
      attached = block.asset.attached?
      page_url = page_url_for(block.page)

      {
        block_id: block.id,
        block_type: block.block_type,
        filename: attached ? block.asset.filename.to_s : nil,
        content_type: attached ? block.asset.content_type.to_s : nil,
        byte_size: attached ? block.asset.blob.byte_size : nil,
        embed_url: block.embed_url.presence,
        page_id: block.page_id,
        page_title: block.page.title,
        page_url: page_url,
        workspace_id: block.workspace_id,
        workspace_name: block.workspace.name,
        workspace_url: routes.workspace_path(workspace_slug: block.workspace.slug),
        download_url: attached ? routes.download_page_block_path(
          workspace_slug: block.workspace.slug,
          page_id: block.page_id,
          id: block.id
        ) : nil
      }
    end

    def embed_title(block)
      uri = URI.parse(block.embed_url.to_s)
      uri.host.presence || block.embed_url
    rescue URI::InvalidURIError
      block.embed_url
    end

    def semantic_results
      return [] if openai_api_key.blank?
      return [] unless semantic_ai_allowed?

      schedule_missing_chunk_embeddings!
      return [] unless rankable_semantic_chunks.exists?

      embedding = query_embedding
      return [] if embedding.empty?

      ranked_ids = rank_semantic_chunk_ids(embedding)
      return [] if ranked_ids.empty?

      chunks_by_id = semantic_chunks_scope
                     .where(id: ranked_ids.map(&:last))
                     .includes(SearchChunk.context_preload_associations)
                     .index_by(&:id)

      ranked_ids.filter_map do |similarity, chunk_id|
        chunk = chunks_by_id[chunk_id]
        build_semantic_result(chunk, similarity) if chunk.present?
      end
    rescue Openai::EmbeddingsClient::Error => error
      Rails.logger.warn("Assistant semantic content search disabled scope=#{scope}: #{error.message}")
      []
    end

    def rank_semantic_chunk_ids(embedding)
      ranked = []

      rankable_semantic_chunks.select(:id, :embedding).find_each(batch_size: 250) do |chunk|
        similarity = cosine_similarity(embedding, chunk.embedding_vector)
        next if similarity.nil? || similarity <= SEMANTIC_SIMILARITY_THRESHOLD

        ranked << [ similarity, chunk.id ]
        ranked.sort_by! { |score, _id| -score }
        ranked.pop while ranked.length > SEMANTIC_RESULT_LIMIT
      end

      ranked
    end

    def rankable_semantic_chunks
      semantic_chunks_scope
        .where(embedding_model: SearchChunk::EMBEDDING_MODEL)
        .where.not(embedding: [])
    end

    def semantic_chunks_scope
      return @semantic_chunks_scope if defined?(@semantic_chunks_scope)

      page_ids = Pundit.policy_scope!(user, Page).active.where(workspace_id: scoped_workspace_ids)
      row_ids = Pundit.policy_scope!(user, DbRow).active.where(workspace_id: scoped_workspace_ids)
      event_ids = Pundit.policy_scope!(user, KalendariumEvent).where(workspace_id: scoped_workspace_ids)
      meeting_ids = Pundit.policy_scope!(user, MeetingSession).where(workspace_id: scoped_workspace_ids)
      message_ids = accessible_epistularium_messages.where(workspace_id: scoped_workspace_ids)

      if document_scope?
        page_ids = page_ids.where(id: document_page.id)
        row_ids = if document_page.linked_database.present?
                    row_ids.where(database_id: document_page.linked_database.id)
        else
                    row_ids.none
        end
        event_ids = event_ids.none
        meeting_ids = meeting_ids.none
        message_ids = message_ids.none
      end

      base = SearchChunk.where(workspace_id: scoped_workspace_ids)
      @semantic_chunks_scope = SearchChunk.accessible_scope_from(
        base: base,
        page_ids: page_ids.select(:id),
        row_ids: row_ids.select(:id),
        event_ids: event_ids.select(:id),
        meeting_ids: meeting_ids.select(:id),
        message_ids: message_ids.select(:id)
      )
    end

    def accessible_epistularium_messages
      return EpistulariumMessage.none unless ActiveRecord::Base.connection.data_source_exists?("epistularium_messages")

      Pundit.policy_scope!(user, EpistulariumMessage)
    end

    def schedule_missing_chunk_embeddings!
      missing_by_workspace = semantic_chunks_scope
                             .where(embedding_model: nil)
                             .order(updated_at: :desc)
                             .limit(SEMANTIC_EMBEDDING_BATCH_LIMIT)
                             .pluck(:workspace_id, :id)
                             .group_by(&:first)

      missing_by_workspace.each do |workspace_id, pairs|
        Search::BackfillChunkEmbeddingsJob.perform_later(user.id, workspace_id, pairs.map(&:last))
      rescue StandardError => error
        raise unless Queueing::JobEnqueueSafety.queue_unavailable?(error)

        Rails.logger.warn(
          "Skipping assistant search embedding backfill workspace=#{workspace_id}: #{error.class}: #{error.message}"
        )
      end
    end

    def query_embedding
      return @query_embedding if defined?(@query_embedding)

      response = Openai::EmbeddingsClient.embed_with_usage(
        text: query,
        api_key: openai_api_key,
        model: SearchChunk::EMBEDDING_MODEL
      )
      Search::AiUsageLogger.log!(
        user: user,
        workspace: usage_workspace,
        operation: AiUsageLog::OP_SEMANTIC_QUERY,
        model: SearchChunk::EMBEDDING_MODEL,
        usage: response[:usage],
        metadata: { scope: scope, query_length: query.length, service: "assistant_content_search" }
      )

      @query_embedding = Array(response[:embedding])
    end

    def openai_api_key
      return @openai_api_key if defined?(@openai_api_key)

      @openai_api_key = Openai::CredentialResolver.resolve(user: user)
    end

    def semantic_ai_allowed?
      Search::AiBudgetGuard.within_daily_budget?(user: user, workspace: usage_workspace) &&
        Search::AiRateLimiter.allowed?(user: user, workspace: usage_workspace, operation: "semantic_search")
    end

    def usage_workspace
      @usage_workspace ||= document_page&.workspace || scoped_workspaces.find { |candidate| candidate.id == workspace.id } || scoped_workspaces.first
    end

    def build_semantic_result(chunk, similarity)
      target_workspace = chunk.workspace
      attributes = semantic_result_attributes(chunk, target_workspace)
      return if attributes.blank?

      Result.new(
        **attributes,
        excerpt: highlighted_excerpt(chunk.text),
        score: attributes.fetch(:score) + (similarity * 20),
        workspace_id: target_workspace.id,
        workspace_name: target_workspace.name,
        source_type: chunk.source_type,
        source_id: chunk.source_id,
        media: nil
      )
    end

    def semantic_result_attributes(chunk, target_workspace)
      if chunk.page.present?
        {
          kind: page_kind(chunk.page),
          title: page_title(chunk.page),
          url: page_url_for(chunk.page),
          score: 48
        }
      elsif chunk.db_row.present?
        database = chunk.database || chunk.db_row.database
        {
          kind: database&.tab_child? ? "Grid tab row" : "Row",
          title: chunk.db_row.title.presence || database&.name || "Row",
          url: routes.database_path(
            workspace_slug: target_workspace.slug,
            id: chunk.database_id,
            anchor: "row_#{chunk.db_row_id}"
          ),
          score: 44
        }
      elsif SearchChunk.reference_column_available?(:kalendarium_event_id) && chunk.kalendarium_event.present?
        event = chunk.kalendarium_event
        {
          kind: "Kalendarium event",
          title: event.title,
          url: routes.kalendarium_path(
            workspace_slug: target_workspace.slug,
            view: "day",
            date: event.starts_at_utc.to_date.iso8601,
            anchor: "kalendarium_event_#{event.id}"
          ),
          score: 44
        }
      elsif SearchChunk.reference_column_available?(:meeting_session_id) && chunk.meeting_session.present?
        session = chunk.meeting_session
        {
          kind: "Meeting session",
          title: session.title,
          url: routes.workspace_meetings_path(
            workspace_slug: target_workspace.slug,
            anchor: "meeting_session_#{session.id}"
          ),
          score: 44
        }
      elsif SearchChunk.reference_column_available?(:epistularium_message_id) && chunk.epistularium_message.present?
        message = chunk.epistularium_message
        {
          kind: "Email",
          title: message.display_subject,
          url: routes.workspace_epistularium_message_path(workspace_slug: target_workspace.slug, id: message.id),
          score: 44
        }
      end
    end

    def cosine_similarity(left, right)
      return if left.empty? || right.empty? || left.length != right.length

      dot_product = 0.0
      left_norm = 0.0
      right_norm = 0.0
      left.each_with_index do |value, index|
        other = right[index]
        dot_product += value.to_f * other.to_f
        left_norm += value.to_f**2
        right_norm += other.to_f**2
      end

      denominator = Math.sqrt(left_norm) * Math.sqrt(right_norm)
      dot_product / denominator unless denominator.zero?
    end

    def merge_and_rank(results)
      best_by_url = {}
      results.compact.each do |result|
        current = best_by_url[result.url]
        best_by_url[result.url] = result if current.nil? || reranked_score(result) > reranked_score(current)
      end

      best_by_url.values.sort_by { |result| -reranked_score(result) }
    end

    def reranked_score(result)
      result.score.to_f + lexical_match_score([ result.title, sanitized_excerpt(result.excerpt) ].join(" "))
    end

    def lexical_match_score(text)
      normalized = text.to_s.downcase
      query_terms.sum { |term| normalized.scan(Regexp.new(Regexp.escape(term))).length * 1.2 }
    end

    def sanitized_excerpt(excerpt)
      ActionView::Base.full_sanitizer.sanitize(excerpt.to_s)
    end

    def highlighted_excerpt(text)
      compact = text.to_s.squish
      return "" if compact.blank?

      ActionController::Base.helpers.highlight(
        compact.truncate(260),
        query_terms,
        highlighter: "<mark>\\1</mark>"
      )
    end

    def query_terms
      @query_terms ||= query.downcase
                            .scan(/[[:alnum:]]+/)
                            .select { |term| term.length >= 2 }
                            .reject { |term| QUERY_STOPWORDS.include?(term) }
                            .uniq
                            .first(12)
    end

    def query_term_variants
      @query_term_variants ||= query_terms.flat_map { |term| [ term, term.singularize ] }.uniq
    end

    def lexical_query
      query_terms.presence&.join(" ") || query
    end

    def scoped_workspaces
      return @scoped_workspaces if defined?(@scoped_workspaces)

      accessible = Pundit.policy_scope!(user, Workspace)
      @scoped_workspaces =
        case scope
        when SCOPE_ACCOUNT
          accessible.order(:name).to_a
        when SCOPE_WORKSPACE
          Array(accessible_current_workspace)
        when SCOPE_DOCUMENT
          document_page.present? ? [ accessible_current_workspace ] : []
        else
          []
        end
    end

    def scoped_workspace_ids
      @scoped_workspace_ids ||= scoped_workspaces.map(&:id)
    end

    def document_page
      return @document_page if defined?(@document_page)
      return @document_page = nil unless document_scope? && page_id.present?
      return @document_page = nil if accessible_current_workspace.blank?

      @document_page = Pundit.policy_scope!(user, Page)
                             .active
                             .where(workspace_id: accessible_current_workspace.id)
                             .find_by(id: page_id)
    end

    def accessible_current_workspace
      return @accessible_current_workspace if defined?(@accessible_current_workspace)

      @accessible_current_workspace = Pundit.policy_scope!(user, Workspace).find_by(id: workspace.id)
    end

    def document_scope?
      scope == SCOPE_DOCUMENT
    end

    def page_kind(page)
      return "Grid tab" if page.tab_child? && page.linked_database.present?
      return "Grid" if page.linked_database.present?
      return "Page" unless page.tab_child?

      "Tab"
    end

    def page_title(page)
      page.tab_child? ? page.tab_reference_title : page.title
    end

    def page_url_for(page)
      if page.linked_database.present?
        routes.database_path(workspace_slug: page.workspace.slug, id: page.linked_database.id)
      else
        routes.page_path(workspace_slug: page.workspace.slug, id: page.id)
      end
    end

    def source_type_for_kind(kind)
      case kind
      when "Page", "Tab", "Grid", "Grid tab" then "page"
      when "Block", "Tab block" then "block"
      when "Row", "Grid tab row" then "db_row"
      when "Kalendarium event" then "kalendarium_event"
      when "Meeting session" then "meeting_session"
      when "Email" then "epistularium_message"
      else kind.to_s.parameterize(separator: "_")
      end
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
