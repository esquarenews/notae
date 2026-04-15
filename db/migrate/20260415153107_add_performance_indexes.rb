class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :memberships,
              %i[user_id role workspace_id],
              name: "index_memberships_on_user_id_role_and_workspace_id",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :db_rows,
              %i[database_id archived_at position created_at],
              name: "index_db_rows_on_database_archived_position_created_at",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :db_cells,
              %i[db_property_id value_text],
              name: "index_db_cells_on_property_and_value_text_present",
              where: "value_text <> ''",
              algorithm: :concurrently,
              if_not_exists: true
  end

  def down
    remove_index :db_cells, name: "index_db_cells_on_property_and_value_text_present", algorithm: :concurrently, if_exists: true
    remove_index :db_rows, name: "index_db_rows_on_database_archived_position_created_at", algorithm: :concurrently, if_exists: true
    remove_index :memberships, name: "index_memberships_on_user_id_role_and_workspace_id", algorithm: :concurrently, if_exists: true
  end
end
