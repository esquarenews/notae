require "digest"

module Search
  class ChunkIndexingService
    def self.index_page!(page:)
      new(source_type: SearchChunk::SOURCE_PAGE, source_record: page).index!
    end

    def self.index_db_row!(db_row:)
      new(source_type: SearchChunk::SOURCE_DB_ROW, source_record: db_row).index!
    end

    def self.index_kalendarium_event!(kalendarium_event:)
      new(source_type: SearchChunk::SOURCE_KALENDARIUM_EVENT, source_record: kalendarium_event).index!
    end

    def self.index_meeting_session!(meeting_session:)
      new(source_type: SearchChunk::SOURCE_MEETING_SESSION, source_record: meeting_session).index!
    end

    def self.delete_source!(source_type:, source_id:)
      SearchChunk.for_source(source_type, source_id).delete_all
    end

    def initialize(source_type:, source_record:)
      @source_type = source_type
      @source_record = source_record
    end

    def index!
      return delete_source! unless indexable_record?

      chunks = Search::TextChunker.call(source_text)
      return delete_source! if chunks.empty?

      ActiveRecord::Base.transaction do
        chunks.each_with_index do |chunk_text, index|
          upsert_chunk!(chunk_text: chunk_text, chunk_index: index)
        end

        SearchChunk.for_source(source_type, source_id)
                   .where("chunk_index >= ?", chunks.length)
                   .delete_all
      end
    end

    private

    attr_reader :source_type, :source_record

    def indexable_record?
      case source_type
      when SearchChunk::SOURCE_PAGE
        source_record.present? && !source_record.archived?
      when SearchChunk::SOURCE_DB_ROW
        source_record.present? && source_record.archived_at.nil?
      when SearchChunk::SOURCE_KALENDARIUM_EVENT
        source_record.present?
      when SearchChunk::SOURCE_MEETING_SESSION
        source_record.present?
      else
        false
      end
    end

    def source_id
      source_record.id
    end

    def source_text
      return @source_text if defined?(@source_text)

      @source_text = case source_type
      when SearchChunk::SOURCE_PAGE
        page_text
      when SearchChunk::SOURCE_DB_ROW
        db_row_text
      when SearchChunk::SOURCE_KALENDARIUM_EVENT
        kalendarium_event_text
      when SearchChunk::SOURCE_MEETING_SESSION
        meeting_session_text
      else
        ""
      end
    end

    def page_text
      source_record.search_source_text
    end

    def db_row_text
      source_record.search_source_text
    end

    def kalendarium_event_text
      source_record.search_source_text
    end

    def meeting_session_text
      source_record.search_source_text
    end

    def upsert_chunk!(chunk_text:, chunk_index:)
      hash = Digest::SHA256.hexdigest(chunk_text)
      source_hash = Digest::SHA256.hexdigest(source_text)
      chunk = SearchChunk.find_or_initialize_by(source_type: source_type, source_id: source_id, chunk_index: chunk_index)

      attributes = {
        workspace_id: source_record.workspace_id,
        page_id: page_id_for_chunk,
        db_row_id: db_row_id_for_chunk,
        database_id: database_id_for_chunk,
        kalendarium_event_id: kalendarium_event_id_for_chunk,
        meeting_session_id: meeting_session_id_for_chunk,
        text: chunk_text,
        token_count: chunk_text.split(/\s+/).size,
        content_hash: hash,
        source_content_hash: source_hash,
        source_uri: source_uri,
        source_title: source_title,
        metadata_json: metadata_for_chunk(chunk_text: chunk_text)
      }

      clear_embedding = chunk.new_record? || chunk.content_hash != hash

      chunk.assign_attributes(attributes)
      if clear_embedding
        chunk.embedding = []
        chunk.embedding_model = nil
      end

      chunk.save!
    end

    def page_id_for_chunk
      source_type == SearchChunk::SOURCE_PAGE ? source_record.id : nil
    end

    def db_row_id_for_chunk
      source_type == SearchChunk::SOURCE_DB_ROW ? source_record.id : nil
    end

    def database_id_for_chunk
      return source_record.database_id if source_type == SearchChunk::SOURCE_DB_ROW

      nil
    end

    def kalendarium_event_id_for_chunk
      return source_record.id if source_type == SearchChunk::SOURCE_KALENDARIUM_EVENT

      nil
    end

    def meeting_session_id_for_chunk
      return source_record.id if source_type == SearchChunk::SOURCE_MEETING_SESSION

      nil
    end

    def source_uri
      routes = Rails.application.routes.url_helpers

      case source_type
      when SearchChunk::SOURCE_PAGE
        routes.page_path(workspace_slug: source_record.workspace.slug, id: source_record.id)
      when SearchChunk::SOURCE_DB_ROW
        routes.database_path(workspace_slug: source_record.workspace.slug, id: source_record.database_id, anchor: "row_#{source_record.id}")
      when SearchChunk::SOURCE_KALENDARIUM_EVENT
        routes.kalendarium_path(
          workspace_slug: source_record.workspace.slug,
          view: "day",
          date: source_record.starts_at_utc.to_date.iso8601,
          anchor: "kalendarium_event_#{source_record.id}"
        )
      when SearchChunk::SOURCE_MEETING_SESSION
        routes.workspace_meetings_path(workspace_slug: source_record.workspace.slug, anchor: "meeting_session_#{source_record.id}")
      end
    end

    def source_title
      case source_type
      when SearchChunk::SOURCE_PAGE
        source_record.title
      when SearchChunk::SOURCE_DB_ROW
        source_record.title.presence || source_record.database&.name || "Row"
      when SearchChunk::SOURCE_KALENDARIUM_EVENT
        source_record.title
      when SearchChunk::SOURCE_MEETING_SESSION
        source_record.title
      end
    end

    def metadata_for_chunk(chunk_text:)
      metadata = {
        "source_kind" => source_type,
        "entities" => Search::EntityExtractionService.call(text: chunk_text)
      }

      if source_type == SearchChunk::SOURCE_MEETING_SESSION
        metadata["meeting_session_status"] = source_record.status
        metadata["provider"] = source_record.provider
        metadata["kalendarium_event_id"] = source_record.kalendarium_event_id
      elsif source_type == SearchChunk::SOURCE_KALENDARIUM_EVENT
        metadata["calendar_id"] = source_record.kalendarium_calendar_id
        metadata["starts_at_utc"] = source_record.starts_at_utc&.iso8601
      end

      metadata
    end

    def delete_source!
      self.class.delete_source!(source_type: source_type, source_id: source_id)
    end
  end
end
