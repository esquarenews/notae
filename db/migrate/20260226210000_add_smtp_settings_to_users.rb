class AddSmtpSettingsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :smtp_address, :string
    add_column :users, :smtp_port, :integer
    add_column :users, :smtp_domain, :string
    add_column :users, :smtp_username, :string
    add_column :users, :smtp_password, :string
    add_column :users, :smtp_authentication, :string, null: false, default: "plain"
    add_column :users, :smtp_enable_starttls_auto, :boolean, null: false, default: true
    add_column :users, :smtp_from_name, :string
    add_column :users, :smtp_from_email, :string
  end
end
