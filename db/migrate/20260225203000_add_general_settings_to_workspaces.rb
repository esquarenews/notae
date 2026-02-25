class AddGeneralSettingsToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :icon, :string
    add_column :workspaces, :analytics_enabled, :boolean, default: true, null: false
  end
end
