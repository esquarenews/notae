class AddPeopleSettingsToWorkspaces < ActiveRecord::Migration[8.1]
  def up
    add_column :workspaces, :join_link_enabled, :boolean, default: false, null: false
    add_column :workspaces, :join_link_token, :string
    add_index :workspaces, :join_link_token, unique: true

    Workspace.reset_column_information
    Workspace.where(join_link_token: nil).find_each do |workspace|
      workspace.update_columns(join_link_token: Workspace.generate_join_link_token)
    end
  end

  def down
    remove_index :workspaces, :join_link_token
    remove_column :workspaces, :join_link_token
    remove_column :workspaces, :join_link_enabled
  end
end
