class CreatePagesAndBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :pages, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :parent_page, type: :uuid, foreign_key: { to_table: :pages }
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.datetime :archived_at

      t.timestamps
    end

    add_index :pages, %i[workspace_id parent_page_id created_at], name: "index_pages_tree_lookup"
    add_index :pages, %i[workspace_id archived_at]

    create_table :blocks, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :page, null: false, type: :uuid, foreign_key: true
      t.references :parent_block, type: :uuid, foreign_key: { to_table: :blocks }
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.string :block_type, null: false, default: "paragraph"
      t.jsonb :content_json, null: false, default: {}
      t.integer :position, null: false, default: 1024
      t.datetime :archived_at

      t.timestamps
    end

    add_check_constraint :blocks, "position > 0", name: "check_blocks_position_positive"
    add_index :blocks, %i[page_id parent_block_id position],
              unique: true,
              where: "archived_at IS NULL",
              name: "index_active_blocks_on_page_parent_position"
    add_index :blocks, %i[page_id archived_at]
  end
end
