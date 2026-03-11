module Search
  class WorkspaceIngestionService
    Result = Struct.new(
      :source_count,
      :indexed_source_count,
      :coverage_percentage,
      :embedded_chunk_count,
      :missing_embedding_count,
      keyword_init: true
    )

    EMBEDDING_BATCH_SIZE = 80

    def initialize(workspace:, requested_by:)
      @workspace = workspace
      @requested_by = requested_by
    end

    def call
      indexed_sources = 0
      eligible_sources = source_records.select do |record|
        record.respond_to?(:search_source_text) && record.search_source_text.to_s.strip.present?
      end

      eligible_sources.each do |record|
        index_record!(record)
        indexed_sources += 1 if SearchChunk.for_source(source_type_for(record), record.id).exists?
      end

      embedded_chunk_count = embed_missing_chunks!
      missing_embedding_count = missing_embedding_scope.count
      source_count = eligible_sources.length
      coverage_percentage = source_count.zero? ? 100.0 : ((indexed_sources.to_f / source_count) * 100).round(2)

      Result.new(
        source_count: source_count,
        indexed_source_count: indexed_sources,
        coverage_percentage: coverage_percentage,
        embedded_chunk_count: embedded_chunk_count,
        missing_embedding_count: missing_embedding_count
      )
    end

    private

    attr_reader :workspace, :requested_by

    def source_records
      @source_records ||= begin
        pages = workspace.pages.active.includes(:blocks).to_a
        rows = workspace.db_rows.active.to_a
        events = workspace.kalendarium_events.includes(:kalendarium_project, :linked_page, :linked_db_row).to_a
        meetings = workspace.meeting_sessions.includes(:kalendarium_event, :page).to_a
        pages + rows + events + meetings
      end
    end

    def index_record!(record)
      case record
      when Page
        Search::ChunkIndexingService.index_page!(page: record)
      when DbRow
        Search::ChunkIndexingService.index_db_row!(db_row: record)
      when KalendariumEvent
        Search::ChunkIndexingService.index_kalendarium_event!(kalendarium_event: record)
      when MeetingSession
        Search::ChunkIndexingService.index_meeting_session!(meeting_session: record)
      end
    end

    def source_type_for(record)
      case record
      when Page then SearchChunk::SOURCE_PAGE
      when DbRow then SearchChunk::SOURCE_DB_ROW
      when KalendariumEvent then SearchChunk::SOURCE_KALENDARIUM_EVENT
      when MeetingSession then SearchChunk::SOURCE_MEETING_SESSION
      else raise ArgumentError, "Unsupported source record: #{record.class.name}"
      end
    end

    def embed_missing_chunks!
      return 0 unless requested_by.openai_api_key_configured?
      return 0 unless Search::AiBudgetGuard.within_daily_budget?(user: requested_by, workspace: workspace)

      embedded_chunk_count = 0
      missing_embedding_scope.find_in_batches(batch_size: EMBEDDING_BATCH_SIZE) do |batch|
        response = Openai::EmbeddingsClient.embed_many_with_usage(
          texts: batch.map(&:text),
          api_key: requested_by.openai_api_key,
          model: SearchChunk::EMBEDDING_MODEL
        )

        batch.zip(response[:embeddings]).each do |chunk, embedding|
          next if embedding.blank?

          chunk.update_columns(
            embedding: embedding,
            embedding_model: SearchChunk::EMBEDDING_MODEL,
            updated_at: Time.current
          )
          embedded_chunk_count += 1
        end

        Search::AiUsageLogger.log!(
          user: requested_by,
          workspace: workspace,
          operation: AiUsageLog::OP_SEMANTIC_BACKFILL,
          model: SearchChunk::EMBEDDING_MODEL,
          usage: response[:usage],
          metadata: {
            chunk_count: batch.length,
            source: "workspace_ingestion_service"
          }
        )
      end

      embedded_chunk_count
    rescue Openai::EmbeddingsClient::Error => error
      Rails.logger.warn("Workspace ingestion embedding pass failed for workspace=#{workspace.id}: #{error.message}")
      embedded_chunk_count
    end

    def missing_embedding_scope
      SearchChunk.for_workspace(workspace).where(embedding_model: nil)
    end
  end
end
