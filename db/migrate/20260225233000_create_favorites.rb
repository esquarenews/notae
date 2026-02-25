class CreateFavorites < ActiveRecord::Migration[8.1]
  def change
    create_table :favorites, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.references :favoritable, polymorphic: true, null: false, type: :uuid

      t.timestamps
    end

    add_index :favorites,
              %i[user_id favoritable_type favoritable_id],
              unique: true,
              name: "index_favorites_on_user_and_favoritable"
    add_index :favorites, %i[workspace_id user_id created_at], name: "index_favorites_on_workspace_user_created_at"
  end
end
