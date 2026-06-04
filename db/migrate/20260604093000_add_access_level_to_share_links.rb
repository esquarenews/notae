class AddAccessLevelToShareLinks < ActiveRecord::Migration[8.1]
  def change
    add_column :share_links, :access_level, :integer, null: false, default: 0
    add_column :database_share_links, :access_level, :integer, null: false, default: 0
  end
end
