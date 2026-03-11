class CreateKnowledgeSuggestions < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_suggestions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :ai_conversation, null: true, type: :uuid, foreign_key: true
      t.string :kind, null: false
      t.string :status, null: false, default: "active"
      t.string :title, null: false
      t.text :summary, null: false
      t.jsonb :insights_json, null: false, default: []
      t.jsonb :task_suggestions_json, null: false, default: []
      t.jsonb :related_notes_json, null: false, default: []
      t.jsonb :sources_json, null: false, default: []
      t.jsonb :metadata_json, null: false, default: {}
      t.date :generated_for_date
      t.datetime :generated_at, null: false
      t.datetime :expires_at
      t.datetime :dismissed_at
      t.datetime :converted_at
      t.timestamps
    end

    add_index :knowledge_suggestions, [ :user_id, :workspace_id, :kind, :generated_for_date ], unique: true, where: "kind = 'daily_summary'", name: "idx_knowledge_suggestions_daily_unique"
    add_index :knowledge_suggestions, [ :user_id, :workspace_id, :status, :generated_at ], name: "idx_knowledge_suggestions_active_lookup"
  end
end
