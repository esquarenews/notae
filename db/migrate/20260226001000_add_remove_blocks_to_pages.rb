class AddRemoveBlocksToPages < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :remove_blocks, :boolean, default: false, null: false
  end
end
