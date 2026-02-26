class CreateAiConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_conversations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :page, null: true, type: :uuid, foreign_key: true
      t.string :scope, null: false
      t.string :status, null: false, default: "success"
      t.text :prompt, null: false
      t.text :answer, null: false
      t.jsonb :sources, null: false, default: []
      t.timestamps
    end

    add_index :ai_conversations, %i[user_id created_at], name: "idx_ai_conversations_on_user_created_at"
    add_index :ai_conversations, %i[user_id workspace_id created_at], name: "idx_ai_conversations_on_user_workspace_created_at"
    add_index :ai_conversations, %i[workspace_id created_at], name: "idx_ai_conversations_on_workspace_created_at"
    add_index :ai_conversations, :status
    add_index :ai_conversations, :scope
  end
end
