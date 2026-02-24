class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.string :name, null: false, default: "default"
      t.string :token, null: false
      t.datetime :last_used_at
      t.datetime :expires_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :api_tokens, :token, unique: true
    add_index :api_tokens, %i[user_id revoked_at]
    add_index :api_tokens, %i[user_id created_at]
  end
end
