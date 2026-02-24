class CreateShareLinksAndShareLinkViews < ActiveRecord::Migration[8.1]
  def change
    create_table :share_links, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :page, null: false, type: :uuid, foreign_key: true
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.string :token, null: false
      t.datetime :expires_at
      t.datetime :revoked_at
      t.datetime :last_viewed_at

      t.timestamps
    end

    add_index :share_links, :token, unique: true
    add_index :share_links, %i[page_id revoked_at]
    add_index :share_links, %i[workspace_id revoked_at]

    create_table :share_link_views, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :page, null: false, type: :uuid, foreign_key: true
      t.references :share_link, null: false, type: :uuid, foreign_key: true
      t.string :ip_address, null: false
      t.datetime :viewed_at, null: false

      t.timestamps
    end

    add_index :share_link_views, %i[share_link_id viewed_at]
    add_index :share_link_views, %i[workspace_id viewed_at]
  end
end
