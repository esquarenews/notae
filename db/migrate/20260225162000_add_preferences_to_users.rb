class AddPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :theme_preference, :string, null: false, default: "light"
    add_column :users, :language_preference, :string, null: false, default: "en-US"
    add_column :users, :show_text_direction_controls, :boolean, null: false, default: false
    add_column :users, :start_week_on_monday, :boolean, null: false, default: false
    add_column :users, :date_format_preference, :string, null: false, default: "relative"
    add_column :users, :auto_time_zone, :boolean, null: false, default: true
    add_column :users, :time_zone, :string, null: false, default: "UTC"
    add_column :users, :open_links_in_desktop_app, :boolean, null: false, default: false
    add_column :users, :open_on_start_preference, :string, null: false, default: "last_visited_page"
    add_column :users, :cookie_settings_preference, :string, null: false, default: "customize"
    add_column :users, :show_view_history, :boolean, null: false, default: true
    add_column :users, :profile_discoverability, :boolean, null: false, default: true
  end
end
