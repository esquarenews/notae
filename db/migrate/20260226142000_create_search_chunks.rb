class CreateSearchChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :search_chunks, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.string :source_type, null: false
      t.uuid :source_id, null: false
      t.references :page, type: :uuid, foreign_key: true
      t.references :db_row, type: :uuid, foreign_key: true
      t.references :database, type: :uuid, foreign_key: true
      t.integer :chunk_index, null: false
      t.text :text, null: false
      t.integer :token_count, null: false, default: 0
      t.string :content_hash, null: false
      t.jsonb :embedding, null: false, default: []
      t.string :embedding_model
      t.timestamps
    end

    add_index :search_chunks, [ :source_type, :source_id, :chunk_index ], unique: true, name: "idx_search_chunks_on_source_and_index"
    add_index :search_chunks, [ :workspace_id, :source_type ], name: "idx_search_chunks_on_workspace_and_source_type"
    add_index :search_chunks, [ :workspace_id, :updated_at ], name: "idx_search_chunks_on_workspace_and_updated_at"
    add_index :search_chunks, :content_hash
  end
end
