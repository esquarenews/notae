class AddModelToAiConversations < ActiveRecord::Migration[8.1]
  def up
    add_column :ai_conversations, :model, :string
    add_index :ai_conversations, :model

    execute <<~SQL.squish
      UPDATE ai_conversations
      SET model = 'unknown'
      WHERE model IS NULL OR model = ''
    SQL
  end

  def down
    remove_index :ai_conversations, :model
    remove_column :ai_conversations, :model
  end
end
