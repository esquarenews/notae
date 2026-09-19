class AddThreadIdToAiConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_conversations, :thread_id, :uuid
    add_index :ai_conversations,
              %i[user_id workspace_id thread_id created_at],
              name: "idx_ai_conversations_on_active_thread"
  end
end
