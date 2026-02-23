class AddEmbedUrlToBlocks < ActiveRecord::Migration[8.1]
  def change
    add_column :blocks, :embed_url, :string
    add_index :blocks, :embed_url
  end
end
