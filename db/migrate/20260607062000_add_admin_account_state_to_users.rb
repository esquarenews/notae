class AddAdminAccountStateToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin_suspended_until, :datetime
    add_column :users, :removed_at, :datetime
    add_column :users, :admin_free_tier_ends_at, :datetime

    add_index :users, :admin_suspended_until
    add_index :users, :removed_at
  end
end
