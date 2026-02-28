class AddDatabasePermissionsAndShares < ActiveRecord::Migration[8.1]
  def change
    add_column :databases, :permission_mode, :integer, null: false, default: 0
    add_reference :databases, :created_by, type: :uuid, foreign_key: { to_table: :users }
    add_index :databases, %i[workspace_id permission_mode]

    create_table :database_shares, id: :uuid do |t|
      t.references :database, null: false, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :database_shares, %i[database_id user_id], unique: true
  end
end
