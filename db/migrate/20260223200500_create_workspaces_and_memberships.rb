class CreateWorkspacesAndMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :workspaces, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false

      t.timestamps
    end

    add_index :workspaces, :slug, unique: true

    create_table :memberships, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.integer :role, null: false, default: 0

      t.timestamps
    end

    add_index :memberships, %i[workspace_id user_id], unique: true
  end
end
