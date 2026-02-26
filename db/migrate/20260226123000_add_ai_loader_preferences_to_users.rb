class AddAiLoaderPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :ai_loader_style, :string, null: false, default: "disco_orbit"
    add_column :users, :reduce_ai_loader_motion, :boolean, null: false, default: false
  end
end
