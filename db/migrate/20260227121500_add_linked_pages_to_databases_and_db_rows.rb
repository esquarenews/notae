class AddLinkedPagesToDatabasesAndDbRows < ActiveRecord::Migration[8.1]
  def change
    add_column :databases, :linked_page_id, :uuid
    add_index :databases, :linked_page_id
    add_foreign_key :databases, :pages, column: :linked_page_id, on_delete: :nullify

    add_column :db_rows, :linked_page_id, :uuid
    add_index :db_rows, :linked_page_id
    add_foreign_key :db_rows, :pages, column: :linked_page_id, on_delete: :nullify
  end
end
