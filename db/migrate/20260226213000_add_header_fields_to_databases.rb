class AddHeaderFieldsToDatabases < ActiveRecord::Migration[8.0]
  def change
    add_column :databases, :icon, :string
    add_column :databases, :description, :text
  end
end
