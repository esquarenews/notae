class AddShellStatusBarModeToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :shell_status_bar_mode, :string, null: false, default: "all"
  end
end
