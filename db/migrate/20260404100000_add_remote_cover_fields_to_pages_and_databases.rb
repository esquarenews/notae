class AddRemoteCoverFieldsToPagesAndDatabases < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :cover_remote_url, :text
    add_column :pages, :cover_remote_thumb_url, :text
    add_column :pages, :cover_artist_name, :string
    add_column :pages, :cover_artist_url, :text
    add_column :pages, :cover_source_name, :string
    add_column :pages, :cover_source_url, :text

    add_column :databases, :cover_remote_url, :text
    add_column :databases, :cover_remote_thumb_url, :text
    add_column :databases, :cover_artist_name, :string
    add_column :databases, :cover_artist_url, :text
    add_column :databases, :cover_source_name, :string
    add_column :databases, :cover_source_url, :text
  end
end
