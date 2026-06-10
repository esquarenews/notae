class AddTrialEndsAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :trial_ends_at, :datetime
    add_index :users, :trial_ends_at
  end
end
