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

ActiveRecord::Schema[8.1].define(version: 2026_02_26_193000) do
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

  create_table "ai_conversations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "answer", null: false
    t.datetime "created_at", null: false
    t.uuid "page_id"
    t.text "prompt", null: false
    t.string "scope", null: false
    t.jsonb "sources", default: [], null: false
    t.string "status", default: "success", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "workspace_id", null: false
    t.index ["page_id"], name: "index_ai_conversations_on_page_id"
    t.index ["scope"], name: "index_ai_conversations_on_scope"
    t.index ["status"], name: "index_ai_conversations_on_status"
    t.index ["user_id", "created_at"], name: "idx_ai_conversations_on_user_created_at"
    t.index ["user_id", "workspace_id", "created_at"], name: "idx_ai_conversations_on_user_workspace_created_at"
    t.index ["user_id"], name: "index_ai_conversations_on_user_id"
    t.index ["workspace_id", "created_at"], name: "idx_ai_conversations_on_workspace_created_at"
    t.index ["workspace_id"], name: "index_ai_conversations_on_workspace_id"
  end

  create_table "ai_usage_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "completion_tokens", default: 0, null: false
    t.datetime "created_at", null: false
    t.decimal "estimated_cost_usd", precision: 12, scale: 6, default: "0.0", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "model", null: false
    t.string "operation", null: false
    t.integer "prompt_tokens", default: 0, null: false
    t.integer "total_tokens", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "workspace_id", null: false
    t.index ["model"], name: "index_ai_usage_logs_on_model"
    t.index ["operation"], name: "index_ai_usage_logs_on_operation"
    t.index ["user_id", "workspace_id", "created_at"], name: "idx_ai_usage_logs_on_user_workspace_created_at"
    t.index ["user_id"], name: "index_ai_usage_logs_on_user_id"
    t.index ["workspace_id", "created_at"], name: "idx_ai_usage_logs_on_workspace_created_at"
    t.index ["workspace_id"], name: "index_ai_usage_logs_on_workspace_id"
  end

  create_table "api_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "name", default: "default", null: false
    t.datetime "revoked_at"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["token"], name: "index_api_tokens_on_token", unique: true
    t.index ["user_id", "created_at"], name: "index_api_tokens_on_user_id_and_created_at"
    t.index ["user_id", "revoked_at"], name: "index_api_tokens_on_user_id_and_revoked_at"
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
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

  create_table "database_views", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "config_json", default: {}, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.uuid "database_id", null: false
    t.boolean "default", default: false, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "view_type", default: 0, null: false
    t.uuid "workspace_id", null: false
    t.index ["created_by_id"], name: "index_database_views_on_created_by_id"
    t.index ["database_id", "default"], name: "index_database_views_on_database_id_and_default", unique: true, where: "(\"default\" = true)"
    t.index ["database_id", "name"], name: "index_database_views_on_database_id_and_name", unique: true
    t.index ["database_id"], name: "index_database_views_on_database_id"
    t.index ["workspace_id", "database_id"], name: "index_database_views_on_workspace_id_and_database_id"
    t.index ["workspace_id"], name: "index_database_views_on_workspace_id"
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
    t.integer "position", default: 1024, null: false
    t.text "search_text", default: "", null: false
    t.string "title", default: "", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["database_id", "archived_at"], name: "index_db_rows_on_database_id_and_archived_at"
    t.index ["database_id", "position"], name: "index_db_rows_on_database_id_and_position"
    t.index ["database_id"], name: "index_db_rows_on_database_id"
    t.index ["search_text"], name: "index_db_rows_on_search_text", opclass: :gin_trgm_ops, using: :gin
    t.index ["workspace_id", "archived_at"], name: "index_db_rows_on_workspace_id_and_archived_at"
    t.index ["workspace_id"], name: "index_db_rows_on_workspace_id"
    t.check_constraint "\"position\" > 0", name: "check_db_rows_position_positive"
  end

  create_table "favorites", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "favoritable_id", null: false
    t.string "favoritable_type", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "workspace_id", null: false
    t.index ["favoritable_type", "favoritable_id"], name: "index_favorites_on_favoritable"
    t.index ["user_id", "favoritable_type", "favoritable_id"], name: "index_favorites_on_user_and_favoritable", unique: true
    t.index ["user_id"], name: "index_favorites_on_user_id"
    t.index ["workspace_id", "user_id", "created_at"], name: "index_favorites_on_workspace_user_created_at"
    t.index ["workspace_id"], name: "index_favorites_on_workspace_id"
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

  create_table "page_exports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message", default: "", null: false
    t.datetime "expires_at", null: false
    t.datetime "failed_at"
    t.uuid "page_id", null: false
    t.uuid "requested_by_id", null: false
    t.integer "status", default: 0, null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["page_id"], name: "index_page_exports_on_page_id"
    t.index ["requested_by_id"], name: "index_page_exports_on_requested_by_id"
    t.index ["token"], name: "index_page_exports_on_token", unique: true
    t.index ["workspace_id", "expires_at"], name: "index_page_exports_on_workspace_id_and_expires_at"
    t.index ["workspace_id", "page_id", "created_at"], name: "index_page_exports_on_workspace_page_created_at"
    t.index ["workspace_id"], name: "index_page_exports_on_workspace_id"
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

  create_table "page_presences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "editing_block_id"
    t.datetime "editing_seen_at"
    t.datetime "last_seen_at", null: false
    t.uuid "page_id", null: false
    t.string "session_token", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "workspace_id", null: false
    t.index ["page_id", "editing_seen_at"], name: "index_page_presences_on_page_id_and_editing_seen_at"
    t.index ["page_id", "last_seen_at"], name: "index_page_presences_on_page_id_and_last_seen_at"
    t.index ["page_id"], name: "index_page_presences_on_page_id"
    t.index ["session_token"], name: "index_page_presences_on_session_token", unique: true
    t.index ["user_id"], name: "index_page_presences_on_user_id"
    t.index ["workspace_id"], name: "index_page_presences_on_workspace_id"
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

  create_table "page_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.string "name", null: false
    t.uuid "page_id", null: false
    t.jsonb "snapshot_json", default: {}, null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["created_by_id"], name: "index_page_templates_on_created_by_id"
    t.index ["page_id"], name: "index_page_templates_on_page_id"
    t.index ["workspace_id", "created_at"], name: "index_page_templates_on_workspace_id_and_created_at"
    t.index ["workspace_id", "name"], name: "index_page_templates_on_workspace_id_and_name", unique: true
    t.index ["workspace_id"], name: "index_page_templates_on_workspace_id"
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "archived_at"
    t.integer "cover_focal_y", default: 50, null: false
    t.string "cover_preset_key"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.string "font_style", default: "default", null: false
    t.boolean "full_width", default: false, null: false
    t.string "icon"
    t.boolean "locked", default: false, null: false
    t.uuid "parent_page_id"
    t.integer "permission_mode", default: 0, null: false
    t.boolean "remove_blocks", default: false, null: false
    t.boolean "small_text", default: false, null: false
    t.boolean "suggest_edits", default: false, null: false
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

  create_table "search_chunks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "chunk_index", null: false
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.uuid "database_id"
    t.uuid "db_row_id"
    t.jsonb "embedding", default: [], null: false
    t.string "embedding_model"
    t.uuid "page_id"
    t.uuid "source_id", null: false
    t.string "source_type", null: false
    t.text "text", null: false
    t.integer "token_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["content_hash"], name: "index_search_chunks_on_content_hash"
    t.index ["database_id"], name: "index_search_chunks_on_database_id"
    t.index ["db_row_id"], name: "index_search_chunks_on_db_row_id"
    t.index ["page_id"], name: "index_search_chunks_on_page_id"
    t.index ["source_type", "source_id", "chunk_index"], name: "idx_search_chunks_on_source_and_index", unique: true
    t.index ["workspace_id", "source_type"], name: "idx_search_chunks_on_workspace_and_source_type"
    t.index ["workspace_id", "updated_at"], name: "idx_search_chunks_on_workspace_and_updated_at"
    t.index ["workspace_id"], name: "index_search_chunks_on_workspace_id"
  end

  create_table "share_link_views", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address", null: false
    t.uuid "page_id", null: false
    t.uuid "share_link_id", null: false
    t.datetime "updated_at", null: false
    t.datetime "viewed_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["page_id"], name: "index_share_link_views_on_page_id"
    t.index ["share_link_id", "viewed_at"], name: "index_share_link_views_on_share_link_id_and_viewed_at"
    t.index ["share_link_id"], name: "index_share_link_views_on_share_link_id"
    t.index ["workspace_id", "viewed_at"], name: "index_share_link_views_on_workspace_id_and_viewed_at"
    t.index ["workspace_id"], name: "index_share_link_views_on_workspace_id"
  end

  create_table "share_links", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.datetime "expires_at"
    t.datetime "last_viewed_at"
    t.uuid "page_id", null: false
    t.datetime "revoked_at"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["created_by_id"], name: "index_share_links_on_created_by_id"
    t.index ["page_id", "revoked_at"], name: "index_share_links_on_page_id_and_revoked_at"
    t.index ["page_id"], name: "index_share_links_on_page_id"
    t.index ["token"], name: "index_share_links_on_token", unique: true
    t.index ["workspace_id", "revoked_at"], name: "index_share_links_on_workspace_id_and_revoked_at"
    t.index ["workspace_id"], name: "index_share_links_on_workspace_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "ai_loader_style", default: "disco_orbit", null: false
    t.integer "ai_search_answer_rate_limit_per_minute", default: 12, null: false
    t.decimal "ai_search_daily_budget_usd", precision: 12, scale: 4, default: "1.5", null: false
    t.integer "ai_search_semantic_rate_limit_per_minute", default: 24, null: false
    t.boolean "auto_time_zone", default: true, null: false
    t.string "cookie_settings_preference", default: "customize", null: false
    t.datetime "created_at", null: false
    t.string "date_format_preference", default: "relative", null: false
    t.string "discord_notification_preference", default: "off", null: false
    t.string "email", default: "", null: false
    t.boolean "email_notify_activity", default: true, null: false
    t.boolean "email_notify_always_send", default: false, null: false
    t.boolean "email_notify_page_updates", default: true, null: false
    t.boolean "email_notify_workspace_digest", default: true, null: false
    t.string "encrypted_password", default: "", null: false
    t.string "language_preference", default: "en-US", null: false
    t.boolean "meeting_notify_join_transcribing", default: false, null: false
    t.boolean "meeting_notify_summarized", default: false, null: false
    t.boolean "meeting_notify_transcribed", default: true, null: false
    t.boolean "open_links_in_desktop_app", default: true, null: false
    t.string "open_on_start_preference", default: "workspace_home", null: false
    t.string "openai_api_key"
    t.boolean "profile_discoverability", default: true, null: false
    t.boolean "reduce_ai_loader_motion", default: false, null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.boolean "show_text_direction_controls", default: false, null: false
    t.boolean "show_view_history", default: true, null: false
    t.string "slack_notification_preference", default: "off", null: false
    t.boolean "start_week_on_monday", default: true, null: false
    t.string "theme_preference", default: "light", null: false
    t.string "time_zone", default: "UTC", null: false
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
    t.boolean "analytics_enabled", default: true, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.string "icon"
    t.boolean "join_link_enabled", default: false, null: false
    t.string "join_link_token"
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["archived_at"], name: "index_workspaces_on_archived_at"
    t.index ["join_link_token"], name: "index_workspaces_on_join_link_token", unique: true
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_conversations", "pages"
  add_foreign_key "ai_conversations", "users"
  add_foreign_key "ai_conversations", "workspaces"
  add_foreign_key "ai_usage_logs", "users"
  add_foreign_key "ai_usage_logs", "workspaces"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "audit_events", "users", column: "actor_id"
  add_foreign_key "audit_events", "workspaces"
  add_foreign_key "blocks", "blocks", column: "parent_block_id"
  add_foreign_key "blocks", "pages"
  add_foreign_key "blocks", "users", column: "created_by_id"
  add_foreign_key "blocks", "workspaces"
  add_foreign_key "comments", "users", column: "author_id"
  add_foreign_key "comments", "users", column: "resolved_by_id"
  add_foreign_key "comments", "workspaces"
  add_foreign_key "database_views", "databases"
  add_foreign_key "database_views", "users", column: "created_by_id"
  add_foreign_key "database_views", "workspaces"
  add_foreign_key "databases", "workspaces"
  add_foreign_key "db_cells", "db_properties"
  add_foreign_key "db_cells", "db_rows"
  add_foreign_key "db_cells", "workspaces"
  add_foreign_key "db_properties", "databases"
  add_foreign_key "db_properties", "workspaces"
  add_foreign_key "db_rows", "databases"
  add_foreign_key "db_rows", "workspaces"
  add_foreign_key "favorites", "users"
  add_foreign_key "favorites", "workspaces"
  add_foreign_key "invitations", "users", column: "accepted_by_id"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "invitations", "workspaces"
  add_foreign_key "memberships", "users"
  add_foreign_key "memberships", "workspaces"
  add_foreign_key "notifications", "users", column: "actor_id"
  add_foreign_key "notifications", "users", column: "recipient_id"
  add_foreign_key "notifications", "workspaces"
  add_foreign_key "page_exports", "pages"
  add_foreign_key "page_exports", "users", column: "requested_by_id"
  add_foreign_key "page_exports", "workspaces"
  add_foreign_key "page_links", "blocks", column: "source_block_id"
  add_foreign_key "page_links", "pages", column: "source_page_id"
  add_foreign_key "page_links", "pages", column: "target_page_id"
  add_foreign_key "page_links", "workspaces"
  add_foreign_key "page_presences", "pages"
  add_foreign_key "page_presences", "users"
  add_foreign_key "page_presences", "workspaces"
  add_foreign_key "page_shares", "pages"
  add_foreign_key "page_shares", "users"
  add_foreign_key "page_shares", "users", column: "created_by_id"
  add_foreign_key "page_templates", "pages"
  add_foreign_key "page_templates", "users", column: "created_by_id"
  add_foreign_key "page_templates", "workspaces"
  add_foreign_key "pages", "pages", column: "parent_page_id"
  add_foreign_key "pages", "users", column: "created_by_id"
  add_foreign_key "pages", "workspaces"
  add_foreign_key "search_chunks", "databases"
  add_foreign_key "search_chunks", "db_rows"
  add_foreign_key "search_chunks", "pages"
  add_foreign_key "search_chunks", "workspaces"
  add_foreign_key "share_link_views", "pages"
  add_foreign_key "share_link_views", "share_links"
  add_foreign_key "share_link_views", "workspaces"
  add_foreign_key "share_links", "pages"
  add_foreign_key "share_links", "users", column: "created_by_id"
  add_foreign_key "share_links", "workspaces"
end
