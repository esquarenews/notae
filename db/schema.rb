# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_24_050000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "audit_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.uuid "actor_id", null: false
    t.uuid "auditable_id"
    t.string "auditable_type"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["action"], name: "index_audit_events_on_action"
    t.index ["actor_id"], name: "index_audit_events_on_actor_id"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_events_on_auditable_type_and_auditable_id"
    t.index ["workspace_id", "created_at"], name: "index_audit_events_on_workspace_id_and_created_at"
    t.index ["workspace_id"], name: "index_audit_events_on_workspace_id"
  end

  create_table "blocks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "archived_at"
    t.string "block_type", default: "paragraph", null: false
    t.jsonb "content_json", default: {}, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.string "embed_url"
    t.uuid "page_id", null: false
    t.uuid "parent_block_id"
    t.integer "position", default: 1024, null: false
    t.text "search_text", default: "", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["created_by_id"], name: "index_blocks_on_created_by_id"
    t.index ["embed_url"], name: "index_blocks_on_embed_url"
    t.index ["page_id", "archived_at"], name: "index_blocks_on_page_id_and_archived_at"
    t.index ["page_id", "parent_block_id", "position"], name: "index_active_blocks_on_page_parent_position", unique: true, where: "(archived_at IS NULL)"
    t.index ["page_id"], name: "index_blocks_on_page_id"
    t.index ["parent_block_id"], name: "index_blocks_on_parent_block_id"
    t.index ["search_text"], name: "index_blocks_on_search_text", opclass: :gin_trgm_ops, using: :gin
    t.index ["workspace_id"], name: "index_blocks_on_workspace_id"
    t.check_constraint "\"position\" > 0", name: "check_blocks_position_positive"
  end

  create_table "comments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "author_id", null: false
    t.text "body", null: false
    t.uuid "commentable_id", null: false
    t.string "commentable_type", null: false
    t.datetime "created_at", null: false
    t.datetime "resolved_at"
    t.uuid "resolved_by_id"
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["author_id"], name: "index_comments_on_author_id"
    t.index ["commentable_type", "commentable_id", "created_at"], name: "index_comments_on_commentable_lookup"
    t.index ["commentable_type", "commentable_id"], name: "index_comments_on_commentable"
    t.index ["resolved_by_id"], name: "index_comments_on_resolved_by_id"
    t.index ["workspace_id", "created_at"], name: "index_comments_on_workspace_id_and_created_at"
    t.index ["workspace_id"], name: "index_comments_on_workspace_id"
  end

  create_table "databases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "name"], name: "index_databases_on_workspace_id_and_name"
    t.index ["workspace_id"], name: "index_databases_on_workspace_id"
  end

  create_table "db_cells", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "db_property_id", null: false
    t.uuid "db_row_id", null: false
    t.datetime "updated_at", null: false
    t.text "value_text", default: "", null: false
    t.uuid "workspace_id", null: false
    t.index ["db_property_id"], name: "index_db_cells_on_db_property_id"
    t.index ["db_row_id", "db_property_id"], name: "index_db_cells_on_db_row_id_and_db_property_id", unique: true
    t.index ["db_row_id"], name: "index_db_cells_on_db_row_id"
    t.index ["workspace_id", "db_property_id"], name: "index_db_cells_on_workspace_id_and_db_property_id"
    t.index ["workspace_id", "db_row_id"], name: "index_db_cells_on_workspace_id_and_db_row_id"
    t.index ["workspace_id"], name: "index_db_cells_on_workspace_id"
  end

  create_table "db_properties", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "database_id", null: false
    t.string "name", null: false
    t.integer "position", default: 1024, null: false
    t.integer "property_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["database_id", "name"], name: "index_db_properties_on_database_id_and_name", unique: true
    t.index ["database_id", "position"], name: "index_db_properties_on_database_id_and_position"
    t.index ["database_id"], name: "index_db_properties_on_database_id"
    t.index ["workspace_id", "database_id"], name: "index_db_properties_on_workspace_id_and_database_id"
    t.index ["workspace_id"], name: "index_db_properties_on_workspace_id"
    t.check_constraint "\"position\" > 0", name: "check_db_properties_position_positive"
  end

  create_table "db_rows", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.jsonb "data_json", default: {}, null: false
    t.uuid "database_id", null: false
    t.text "search_text", default: "", null: false
    t.string "title", default: "", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["database_id", "archived_at"], name: "index_db_rows_on_database_id_and_archived_at"
    t.index ["database_id"], name: "index_db_rows_on_database_id"
    t.index ["search_text"], name: "index_db_rows_on_search_text", opclass: :gin_trgm_ops, using: :gin
    t.index ["workspace_id", "archived_at"], name: "index_db_rows_on_workspace_id_and_archived_at"
    t.index ["workspace_id"], name: "index_db_rows_on_workspace_id"
  end

  create_table "invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "accepted_at"
    t.uuid "accepted_by_id"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.uuid "invited_by_id", null: false
    t.integer "role", default: 3, null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["accepted_by_id"], name: "index_invitations_on_accepted_by_id"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
    t.index ["workspace_id", "email"], name: "index_open_invitations_on_workspace_and_email", where: "(accepted_at IS NULL)"
    t.index ["workspace_id"], name: "index_invitations_on_workspace_id"
  end

  create_table "memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "workspace_id", null: false
    t.index ["user_id"], name: "index_memberships_on_user_id"
    t.index ["workspace_id", "user_id"], name: "index_memberships_on_workspace_id_and_user_id", unique: true
    t.index ["workspace_id"], name: "index_memberships_on_workspace_id"
  end

  create_table "notifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.uuid "notifiable_id"
    t.string "notifiable_type"
    t.string "notification_type", default: "mention", null: false
    t.datetime "read_at"
    t.uuid "recipient_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["actor_id"], name: "index_notifications_on_actor_id"
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable"
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable_lookup"
    t.index ["recipient_id", "created_at"], name: "index_notifications_on_recipient_id_and_created_at"
    t.index ["recipient_id"], name: "index_notifications_on_recipient_id"
    t.index ["workspace_id", "recipient_id", "read_at"], name: "index_notifications_unread_lookup"
    t.index ["workspace_id"], name: "index_notifications_on_workspace_id"
  end

  create_table "page_links", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "source_block_id"
    t.uuid "source_page_id", null: false
    t.uuid "target_page_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["source_block_id", "target_page_id"], name: "index_page_links_on_source_block_and_target", unique: true, where: "(source_block_id IS NOT NULL)"
    t.index ["source_block_id"], name: "index_page_links_on_source_block_id"
    t.index ["source_page_id"], name: "index_page_links_on_source_page_id"
    t.index ["target_page_id"], name: "index_page_links_on_target_page_id"
    t.index ["workspace_id", "source_page_id"], name: "index_page_links_on_workspace_id_and_source_page_id"
    t.index ["workspace_id", "target_page_id"], name: "index_page_links_on_workspace_id_and_target_page_id"
    t.index ["workspace_id"], name: "index_page_links_on_workspace_id"
  end

  create_table "page_shares", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.uuid "page_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["created_by_id"], name: "index_page_shares_on_created_by_id"
    t.index ["page_id", "user_id"], name: "index_page_shares_on_page_id_and_user_id", unique: true
    t.index ["page_id"], name: "index_page_shares_on_page_id"
    t.index ["user_id"], name: "index_page_shares_on_user_id"
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.uuid "parent_page_id"
    t.integer "permission_mode", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["created_by_id"], name: "index_pages_on_created_by_id"
    t.index ["parent_page_id"], name: "index_pages_on_parent_page_id"
    t.index ["title"], name: "index_pages_on_title", opclass: :gin_trgm_ops, using: :gin
    t.index ["workspace_id", "archived_at"], name: "index_pages_on_workspace_id_and_archived_at"
    t.index ["workspace_id", "parent_page_id", "created_at"], name: "index_pages_tree_lookup"
    t.index ["workspace_id", "permission_mode"], name: "index_pages_on_workspace_id_and_permission_mode"
    t.index ["workspace_id"], name: "index_pages_on_workspace_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.uuid "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "audit_events", "users", column: "actor_id"
  add_foreign_key "audit_events", "workspaces"
  add_foreign_key "blocks", "blocks", column: "parent_block_id"
  add_foreign_key "blocks", "pages"
  add_foreign_key "blocks", "users", column: "created_by_id"
  add_foreign_key "blocks", "workspaces"
  add_foreign_key "comments", "users", column: "author_id"
  add_foreign_key "comments", "users", column: "resolved_by_id"
  add_foreign_key "comments", "workspaces"
  add_foreign_key "databases", "workspaces"
  add_foreign_key "db_cells", "db_properties"
  add_foreign_key "db_cells", "db_rows"
  add_foreign_key "db_cells", "workspaces"
  add_foreign_key "db_properties", "databases"
  add_foreign_key "db_properties", "workspaces"
  add_foreign_key "db_rows", "databases"
  add_foreign_key "db_rows", "workspaces"
  add_foreign_key "invitations", "users", column: "accepted_by_id"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "invitations", "workspaces"
  add_foreign_key "memberships", "users"
  add_foreign_key "memberships", "workspaces"
  add_foreign_key "notifications", "users", column: "actor_id"
  add_foreign_key "notifications", "users", column: "recipient_id"
  add_foreign_key "notifications", "workspaces"
  add_foreign_key "page_links", "blocks", column: "source_block_id"
  add_foreign_key "page_links", "pages", column: "source_page_id"
  add_foreign_key "page_links", "pages", column: "target_page_id"
  add_foreign_key "page_links", "workspaces"
  add_foreign_key "page_shares", "pages"
  add_foreign_key "page_shares", "users"
  add_foreign_key "page_shares", "users", column: "created_by_id"
  add_foreign_key "pages", "pages", column: "parent_page_id"
  add_foreign_key "pages", "users", column: "created_by_id"
  add_foreign_key "pages", "workspaces"
end
