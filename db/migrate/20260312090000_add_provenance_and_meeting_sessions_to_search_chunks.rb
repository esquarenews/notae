class AddProvenanceAndMeetingSessionsToSearchChunks < ActiveRecord::Migration[8.1]
  def change
    add_reference :search_chunks, :meeting_session, type: :uuid, foreign_key: true, index: true
    add_column :search_chunks, :source_uri, :string
    add_column :search_chunks, :source_title, :string
    add_column :search_chunks, :source_content_hash, :string
    add_column :search_chunks, :metadata_json, :jsonb, default: {}, null: false

    add_index :search_chunks, :source_content_hash
  end
end
