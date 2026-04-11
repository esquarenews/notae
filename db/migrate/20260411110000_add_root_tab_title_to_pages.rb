class AddRootTabTitleToPages < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :root_tab_title, :string
  end
end
