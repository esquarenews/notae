class AddRowsPerPageToDatabases < ActiveRecord::Migration[8.0]
  def change
    add_column :databases, :rows_per_page, :integer, null: false, default: 25
  end
end
