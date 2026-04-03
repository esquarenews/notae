class CreateWorkspaceEmojis < ActiveRecord::Migration[8.1]
  def change
    create_table :workspace_emojis, id: :uuid do |t|
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false

      t.timestamps
    end

    add_index :workspace_emojis, [ :workspace_id, :name ], unique: true
  end
end
