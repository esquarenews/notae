class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :invited_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.references :accepted_by, type: :uuid, foreign_key: { to_table: :users }
      t.string :email, null: false
      t.integer :role, null: false, default: 3
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at

      t.timestamps
    end

    add_index :invitations, :token, unique: true
    add_index :invitations, %i[workspace_id email], where: "accepted_at IS NULL", name: "index_open_invitations_on_workspace_and_email"
  end
end
