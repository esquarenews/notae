class AddConfirmationAndLockingToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.string :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string :unconfirmed_email
      t.integer :failed_attempts, default: 0, null: false
      t.string :unlock_token
      t.datetime :locked_at
    end

    add_index :users, :confirmation_token, unique: true
    add_index :users, :unlock_token, unique: true

    reversible do |dir|
      dir.up do
        execute "UPDATE users SET confirmed_at = CURRENT_TIMESTAMP WHERE confirmed_at IS NULL"
      end
    end
  end
end
