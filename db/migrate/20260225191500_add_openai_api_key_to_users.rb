class AddOpenaiApiKeyToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :openai_api_key, :string
  end
end
