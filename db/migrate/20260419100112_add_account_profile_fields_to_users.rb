class AddAccountProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :full_name, :string
    add_column :users, :backup_email, :string
    add_column :users, :personal_bio, :text
  end
end
