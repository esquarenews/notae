class CreatePagePresences < ActiveRecord::Migration[8.1]
  def change
    create_table :page_presences, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :page, null: false, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.string :session_token, null: false
      t.datetime :last_seen_at, null: false
      t.uuid :editing_block_id
      t.datetime :editing_seen_at

      t.timestamps
    end

    add_index :page_presences, :session_token, unique: true
    add_index :page_presences, %i[page_id last_seen_at]
    add_index :page_presences, %i[page_id editing_seen_at]
  end
end
