class CreateDatabaseShareLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :database_share_links, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :database, null: false, type: :uuid, foreign_key: true
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.string :token, null: false
      t.datetime :expires_at
      t.datetime :revoked_at
      t.datetime :last_viewed_at
      t.timestamps
    end

    add_index :database_share_links, :token, unique: true
    add_index :database_share_links, %i[database_id revoked_at]
    add_index :database_share_links, %i[workspace_id revoked_at]
  end
end
