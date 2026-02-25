class AddArchivedAtToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :workspaces, :archived_at, :datetime
    add_index :workspaces, :archived_at
  end
end
