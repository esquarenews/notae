class AddTabColorToPages < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :tab_color, :string, null: false, default: "default"
  end
end
