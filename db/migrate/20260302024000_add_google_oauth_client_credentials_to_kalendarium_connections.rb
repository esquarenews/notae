class AddGoogleOauthClientCredentialsToKalendariumConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :kalendarium_connections, :oauth_client_id, :text
    add_column :kalendarium_connections, :oauth_client_secret, :text
  end
end
