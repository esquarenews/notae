class FixKnowledgeSuggestionForeignKeys < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :knowledge_suggestions, :workspaces
    add_foreign_key :knowledge_suggestions, :workspaces, on_delete: :cascade

    remove_foreign_key :knowledge_suggestions, :users
    add_foreign_key :knowledge_suggestions, :users, on_delete: :cascade

    remove_foreign_key :knowledge_suggestions, :ai_conversations
    add_foreign_key :knowledge_suggestions, :ai_conversations, on_delete: :nullify
  end
end
