require "digest"

module Search
  class ChunkIndexingService
    def self.index_page!(page:)
      new(source_type: SearchChunk::SOURCE_PAGE, source_record: page).index!
    end

    def self.index_db_row!(db_row:)
      new(source_type: SearchChunk::SOURCE_DB_ROW, source_record: db_row).index!
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
      else
        false
      end
    end

    def source_id
      source_record.id
    end

    def source_text
      case source_type
      when SearchChunk::SOURCE_PAGE
        page_text
      when SearchChunk::SOURCE_DB_ROW
        db_row_text
      else
        ""
      end
    end

    def page_text
      block_text = source_record.blocks.active.ordered.pluck(:search_text).join("\n")
      [ source_record.title, block_text ].join("\n").squish
    end

    def db_row_text
      [ source_record.title, source_record.search_text ].join("\n").squish
    end

    def upsert_chunk!(chunk_text:, chunk_index:)
      hash = Digest::SHA256.hexdigest(chunk_text)
      chunk = SearchChunk.find_or_initialize_by(source_type: source_type, source_id: source_id, chunk_index: chunk_index)

      attributes = {
        workspace_id: source_record.workspace_id,
        page_id: page_id_for_chunk,
        db_row_id: db_row_id_for_chunk,
        database_id: database_id_for_chunk,
        text: chunk_text,
        token_count: chunk_text.split(/\s+/).size,
        content_hash: hash
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

    def delete_source!
      self.class.delete_source!(source_type: source_type, source_id: source_id)
    end
  end
end
