class AdjustPreferenceDefaultsAndFormats < ActiveRecord::Migration[8.1]
  def up
    change_column_default :users, :start_week_on_monday, from: false, to: true
    change_column_default :users, :open_links_in_desktop_app, from: false, to: true
    change_column_default :users, :open_on_start_preference, from: "last_visited_page", to: "workspace_home"

    execute <<~SQL
      UPDATE users
      SET start_week_on_monday = TRUE
      WHERE start_week_on_monday = FALSE;
    SQL

    execute <<~SQL
      UPDATE users
      SET open_links_in_desktop_app = TRUE
      WHERE open_links_in_desktop_app = FALSE;
    SQL

    execute <<~SQL
      UPDATE users
      SET open_on_start_preference = 'workspace_home'
      WHERE open_on_start_preference = 'last_visited_page'
         OR open_on_start_preference IS NULL
         OR open_on_start_preference = '';
    SQL

    execute <<~SQL
      UPDATE users
      SET date_format_preference = 'full_date'
      WHERE date_format_preference = 'absolute';
    SQL
  end

  def down
    execute <<~SQL
      UPDATE users
      SET date_format_preference = 'absolute'
      WHERE date_format_preference = 'full_date';
    SQL

    execute <<~SQL
      UPDATE users
      SET open_on_start_preference = 'last_visited_page'
      WHERE open_on_start_preference = 'workspace_home';
    SQL

    execute <<~SQL
      UPDATE users
      SET open_links_in_desktop_app = FALSE
      WHERE open_links_in_desktop_app = TRUE;
    SQL

    execute <<~SQL
      UPDATE users
      SET start_week_on_monday = FALSE
      WHERE start_week_on_monday = TRUE;
    SQL

    change_column_default :users, :open_on_start_preference, from: "workspace_home", to: "last_visited_page"
    change_column_default :users, :open_links_in_desktop_app, from: true, to: false
    change_column_default :users, :start_week_on_monday, from: true, to: false
  end
end
