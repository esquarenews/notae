class AddActionsMenuSettingsToPages < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :font_style, :string, null: false, default: "default"
    add_column :pages, :small_text, :boolean, null: false, default: false
    add_column :pages, :full_width, :boolean, null: false, default: false
    add_column :pages, :locked, :boolean, null: false, default: false
    add_column :pages, :suggest_edits, :boolean, null: false, default: false
  end
end
