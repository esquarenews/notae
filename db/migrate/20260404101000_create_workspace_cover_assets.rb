class CreateWorkspaceCoverAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :workspace_cover_assets, id: :uuid do |t|
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.references :created_by, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :source_kind, null: false, default: "upload"
      t.string :label
      t.string :external_id
      t.text :remote_image_url
      t.text :remote_thumb_url
      t.string :artist_name
      t.text :artist_url
      t.string :source_name
      t.text :source_url

      t.timestamps
    end

    add_index :workspace_cover_assets, [ :workspace_id, :created_by_id, :created_at ],
              name: "index_workspace_cover_assets_picker_lookup"
    add_index :workspace_cover_assets, [ :workspace_id, :created_by_id, :source_kind, :external_id ],
              unique: true,
              where: "external_id IS NOT NULL",
              name: "index_workspace_cover_assets_on_external_source"
  end
end
