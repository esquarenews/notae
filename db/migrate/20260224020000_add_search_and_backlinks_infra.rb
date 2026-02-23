class AddSearchAndBacklinksInfra < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    create_table :databases, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    add_index :databases, %i[workspace_id name]

    create_table :db_rows, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :database, null: false, type: :uuid, foreign_key: true
      t.string :title, null: false, default: ""
      t.jsonb :data_json, null: false, default: {}
      t.text :search_text, null: false, default: ""
      t.datetime :archived_at

      t.timestamps
    end

    add_index :db_rows, %i[workspace_id archived_at]
    add_index :db_rows, %i[database_id archived_at]
    add_index :db_rows, :search_text, using: :gin, opclass: :gin_trgm_ops

    add_column :blocks, :search_text, :text, null: false, default: ""
    add_index :blocks, :search_text, using: :gin, opclass: :gin_trgm_ops
    add_index :pages, :title, using: :gin, opclass: :gin_trgm_ops

    create_table :page_links, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :source_page, null: false, type: :uuid, foreign_key: { to_table: :pages }
      t.references :target_page, null: false, type: :uuid, foreign_key: { to_table: :pages }
      t.references :source_block, type: :uuid, foreign_key: { to_table: :blocks }

      t.timestamps
    end

    add_index :page_links, %i[workspace_id target_page_id]
    add_index :page_links, %i[workspace_id source_page_id]
    add_index :page_links,
              %i[source_block_id target_page_id],
              unique: true,
              where: "source_block_id IS NOT NULL",
              name: "index_page_links_on_source_block_and_target"

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE blocks
          SET search_text = content_json::text
          WHERE search_text = '';
        SQL
      end
    end
  end
end
