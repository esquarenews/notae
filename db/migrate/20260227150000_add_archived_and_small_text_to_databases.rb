class AddArchivedAndSmallTextToDatabases < ActiveRecord::Migration[8.0]
  def change
    add_column :databases, :archived_at, :datetime
    add_column :databases, :small_text, :boolean, default: false, null: false
    add_index :databases, %i[workspace_id archived_at]
  end
end
