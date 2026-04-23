class AddCalendarPreferencesToMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :memberships, :calendar_preferences_json, :jsonb, default: {}, null: false
  end
end
