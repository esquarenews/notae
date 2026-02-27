class AddLockedToDatabases < ActiveRecord::Migration[8.1]
  def change
    add_column :databases, :locked, :boolean, default: false, null: false
  end
end
