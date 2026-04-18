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

ActiveRecord::Schema[8.1].define(version: 2026_04_18_113000) do
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

  create_table "agent_action_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id"
    t.uuid "agent_action_id", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.jsonb "details_json", default: {}, null: false
    t.string "entry_hash", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.string "previous_entry_hash"
    t.integer "sequence_number", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["actor_id"], name: "index_agent_action_events_on_actor_id"
    t.index ["agent_action_id", "sequence_number"], name: "idx_agent_action_events_on_action_and_sequence", unique: true
    t.index ["agent_action_id"], name: "index_agent_action_events_on_agent_action_id"
    t.index ["event_type", "created_at"], name: "idx_agent_action_events_on_type_created_at"
    t.index ["workspace_id", "created_at"], name: "idx_agent_action_events_on_workspace_created_at"
    t.index ["workspace_id"], name: "index_agent_action_events_on_workspace_id"
  end

  create_table "agent_actions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "approval_required", default: true, null: false
    t.datetime "approved_at"
    t.uuid "approved_by_id"
    t.datetime "created_at", null: false
    t.string "draft_type", null: false
    t.boolean "dry_run", default: true, null: false
    t.datetime "executed_at"
    t.jsonb "metadata_json", default: {}, null: false
    t.jsonb "payload_json", default: {}, null: false
    t.jsonb "policy_evaluation_json", default: {}, null: false
    t.string "proposed_by", default: "manual", null: false
    t.datetime "rejected_at"
    t.uuid "rejected_by_id"
    t.jsonb "result_json", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.string "target_system", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "workspace_id", null: false
    t.index ["approved_by_id"], name: "index_agent_actions_on_approved_by_id"
    t.index ["rejected_by_id"], name: "index_agent_actions_on_rejected_by_id"
    t.index ["target_system", "draft_type"], name: "idx_agent_actions_on_system_and_type"
    t.index ["user_id", "created_at"], name: "idx_agent_actions_on_user_created_at"
    t.index ["user_id"], name: "index_agent_actions_on_user_id"
    t.index ["workspace_id", "status", "created_at"], name: "idx_agent_actions_on_workspace_status_created_at"
    t.index ["workspace_id"], name: "index_agent_actions_on_workspace_id"
  end

  create_table "agent_policies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "allow_internal_automation", default: true, null: false
    t.jsonb "allowed_draft_types_json", default: [], null: false
    t.jsonb "allowed_internal_actions_json", default: [], null: false
    t.jsonb "allowed_lifecycle_operations_json", default: [], null: false
    t.jsonb "allowed_target_systems_json", default: [], null: false
    t.boolean "approval_required", default: true, null: false
    t.jsonb "approver_roles_json", default: [], null: false
    t.jsonb "author_roles_json", default: [], null: false
    t.decimal "automation_confidence_threshold", precision: 4, scale: 2, default: "0.7", null: false
    t.integer "automation_retry_limit", default: 2, null: false
    t.datetime "created_at", null: false
    t.boolean "dry_run_required", default: true, null: false
    t.decimal "max_estimated_cost_usd", precision: 10, scale: 2, default: "0.0", null: false
    t.jsonb "metadata_json", default: {}, null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id"], name: "index_agent_policies_on_workspace_id", unique: true
  end

  create_table "ai_conversations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "answer", null: false
    t.datetime "created_at", null: false
    t.string "model"
    t.uuid "page_id"
    t.text "prompt", null: false
    t.string "scope", null: false
    t.jsonb "sources", default: [], null: false
    t.string "status", default: "success", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "workspace_id", null: false
    t.index ["model"], name: "index_ai_conversations_on_model"
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

  create_table "api_token_audit_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action_name"
    t.uuid "api_token_id", null: false
    t.string "controller_name"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.integer "http_status"
    t.jsonb "metadata_json", default: {}, null: false
    t.string "path"
    t.string "request_method"
    t.jsonb "required_scopes_json", default: [], null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "workspace_id"
    t.index ["api_token_id", "created_at"], name: "index_api_token_audit_events_on_api_token_id_and_created_at"
    t.index ["api_token_id"], name: "index_api_token_audit_events_on_api_token_id"
    t.index ["event_type", "created_at"], name: "index_api_token_audit_events_on_event_type_and_created_at"
    t.index ["user_id", "created_at"], name: "index_api_token_audit_events_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_api_token_audit_events_on_user_id"
    t.index ["workspace_id", "created_at"], name: "index_api_token_audit_events_on_workspace_id_and_created_at"
    t.index ["workspace_id"], name: "index_api_token_audit_events_on_workspace_id"
  end

  create_table "api_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "name", default: "default", null: false
    t.datetime "revoked_at"
    t.jsonb "scopes_json", default: ["*"], null: false
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

  create_table "automation_controls", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.text "pause_reason"
    t.datetime "paused_at"
    t.string "scope_name", null: false
    t.datetime "updated_at", null: false
    t.index ["scope_name"], name: "index_automation_controls_on_scope_name", unique: true
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

  create_table "database_share_links", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.uuid "database_id", null: false
    t.datetime "expires_at"
    t.datetime "last_viewed_at"
    t.datetime "revoked_at"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["created_by_id"], name: "index_database_share_links_on_created_by_id"
    t.index ["database_id", "revoked_at"], name: "index_database_share_links_on_database_id_and_revoked_at"
    t.index ["database_id"], name: "index_database_share_links_on_database_id"
    t.index ["token"], name: "index_database_share_links_on_token", unique: true
    t.index ["workspace_id", "revoked_at"], name: "index_database_share_links_on_workspace_id_and_revoked_at"
    t.index ["workspace_id"], name: "index_database_share_links_on_workspace_id"
  end

  create_table "database_shares", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.uuid "database_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["created_by_id"], name: "index_database_shares_on_created_by_id"
    t.index ["database_id", "user_id"], name: "index_database_shares_on_database_id_and_user_id", unique: true
    t.index ["database_id"], name: "index_database_shares_on_database_id"
    t.index ["user_id"], name: "index_database_shares_on_user_id"
  end

  create_table "database_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.uuid "database_id"
    t.string "name", null: false
    t.jsonb "snapshot_json", default: {}, null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["created_by_id"], name: "index_database_templates_on_created_by_id"
    t.index ["database_id"], name: "index_database_templates_on_database_id"
    t.index ["workspace_id", "created_at"], name: "index_database_templates_on_workspace_id_and_created_at"
    t.index ["workspace_id", "name"], name: "index_database_templates_on_workspace_id_and_name", unique: true
    t.index ["workspace_id"], name: "index_database_templates_on_workspace_id"
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
    t.string "applied_template_name"
    t.datetime "archived_at"
    t.string "cover_artist_name"
    t.text "cover_artist_url"
    t.integer "cover_focal_y", default: 50, null: false
    t.string "cover_preset_key"
    t.text "cover_remote_thumb_url"
    t.text "cover_remote_url"
    t.string "cover_source_name"
    t.text "cover_source_url"
    t.datetime "created_at", null: false
    t.uuid "created_by_id"
    t.uuid "database_template_id"
    t.text "description"
    t.string "font_style", default: "default", null: false
    t.string "icon"
    t.uuid "linked_page_id"
    t.boolean "locked", default: false, null: false
    t.string "name", null: false
    t.string "name_column_background_color", default: "default", null: false
    t.boolean "name_column_text_bold", default: false, null: false
    t.string "name_column_text_color", default: "default", null: false
    t.boolean "name_column_text_italic", default: false, null: false
    t.integer "permission_mode", default: 0, null: false
    t.boolean "small_text", default: false, null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["created_by_id"], name: "index_databases_on_created_by_id"
    t.index ["database_template_id"], name: "index_databases_on_database_template_id"
    t.index ["linked_page_id"], name: "index_databases_on_linked_page_id"
    t.index ["workspace_id", "archived_at"], name: "index_databases_on_workspace_id_and_archived_at"
    t.index ["workspace_id", "name"], name: "index_databases_on_workspace_id_and_name"
    t.index ["workspace_id", "permission_mode"], name: "index_databases_on_workspace_id_and_permission_mode"
    t.index ["workspace_id"], name: "index_databases_on_workspace_id"
  end

  create_table "db_cells", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "db_property_id", null: false
    t.uuid "db_row_id", null: false
    t.datetime "updated_at", null: false
    t.text "value_text", default: "", null: false
    t.uuid "workspace_id", null: false
    t.index ["db_property_id", "value_text"], name: "index_db_cells_on_property_and_value_text_present", where: "(value_text <> ''::text)"
    t.index ["db_property_id"], name: "index_db_cells_on_db_property_id"
    t.index ["db_row_id", "db_property_id"], name: "index_db_cells_on_db_row_id_and_db_property_id", unique: true
    t.index ["db_row_id"], name: "index_db_cells_on_db_row_id"
    t.index ["workspace_id", "db_property_id"], name: "index_db_cells_on_workspace_id_and_db_property_id"
    t.index ["workspace_id", "db_row_id"], name: "index_db_cells_on_workspace_id_and_db_row_id"
    t.index ["workspace_id"], name: "index_db_cells_on_workspace_id"
  end

  create_table "db_properties", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "background_color", default: "default", null: false
    t.datetime "created_at", null: false
    t.uuid "database_id", null: false
    t.string "name", null: false
    t.integer "position", default: 1024, null: false
    t.integer "property_type", default: 0, null: false
    t.jsonb "select_options_json", default: [], null: false
    t.boolean "text_bold", default: false, null: false
    t.string "text_color", default: "default", null: false
    t.boolean "text_italic", default: false, null: false
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
    t.uuid "linked_page_id"
    t.integer "position", default: 1024, null: false
    t.text "search_text", default: "", null: false
    t.string "title", default: "", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["database_id", "archived_at", "position", "created_at"], name: "index_db_rows_on_database_archived_position_created_at"
    t.index ["database_id", "archived_at"], name: "index_db_rows_on_database_id_and_archived_at"
    t.index ["database_id", "position"], name: "index_db_rows_on_database_id_and_position"
    t.index ["database_id"], name: "index_db_rows_on_database_id"
    t.index ["linked_page_id"], name: "index_db_rows_on_linked_page_id"
    t.index ["search_text"], name: "index_db_rows_on_search_text", opclass: :gin_trgm_ops, using: :gin
    t.index ["workspace_id", "archived_at"], name: "index_db_rows_on_workspace_id_and_archived_at"
    t.index ["workspace_id"], name: "index_db_rows_on_workspace_id"
    t.check_constraint "\"position\" > 0", name: "check_db_rows_position_positive"
  end

  create_table "epistularium_accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "access_token"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.boolean "enabled", default: true, null: false
    t.string "label", null: false
    t.text "last_error"
    t.datetime "last_synced_at"
    t.text "oauth_client_id"
    t.text "oauth_client_secret"
    t.uuid "owner_id", null: false
    t.string "owner_type", null: false
    t.string "provider", null: false
    t.text "provider_password"
    t.text "provider_username"
    t.text "refresh_token"
    t.string "remote_account_id"
    t.jsonb "scopes_json", default: [], null: false
    t.jsonb "settings_json", default: {}, null: false
    t.string "status", default: "connected", null: false
    t.text "sync_cursor"
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["owner_type", "owner_id"], name: "index_epistularium_accounts_on_owner"
    t.index ["workspace_id", "enabled"], name: "index_epistularium_accounts_on_workspace_and_enabled"
    t.index ["workspace_id", "owner_type", "owner_id", "provider", "label"], name: "index_epistularium_accounts_uniqueness", unique: true
  end

  create_table "epistularium_messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "attachment_metadata_json", default: [], null: false
    t.jsonb "bcc_recipients_json", default: [], null: false
    t.text "body_html"
    t.text "body_text"
    t.jsonb "cc_recipients_json", default: [], null: false
    t.datetime "created_at", null: false
    t.uuid "epistularium_account_id", null: false
    t.string "from_email"
    t.string "from_name"
    t.jsonb "headers_json", default: {}, null: false
    t.string "internet_message_id"
    t.datetime "last_synced_at"
    t.string "mailbox", default: "inbox", null: false
    t.jsonb "metadata_json", default: {}, null: false
    t.string "provider_message_id", null: false
    t.string "provider_thread_id"
    t.datetime "received_at"
    t.jsonb "reply_to_recipients_json", default: [], null: false
    t.datetime "sent_at"
    t.text "snippet"
    t.string "source_checksum"
    t.string "subject", default: "", null: false
    t.string "thread_key"
    t.jsonb "to_recipients_json", default: [], null: false
    t.boolean "unread", default: false, null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["epistularium_account_id", "provider_message_id"], name: "index_epistularium_messages_on_account_and_provider_id", unique: true
    t.index ["epistularium_account_id", "received_at", "created_at"], name: "index_epistularium_messages_on_account_inbox_recency", order: { received_at: :desc, created_at: :desc }, where: "((mailbox)::text = 'inbox'::text)"
    t.index ["epistularium_account_id", "sent_at", "created_at"], name: "index_epistularium_messages_on_account_sent_recency", order: { sent_at: :desc, created_at: :desc }, where: "((mailbox)::text = 'sent'::text)"
    t.index ["internet_message_id"], name: "index_epistularium_messages_on_internet_message_id"
    t.index ["workspace_id", "mailbox", "received_at"], name: "index_epistularium_messages_on_workspace_mailbox_received_at"
    t.index ["workspace_id", "thread_key"], name: "index_epistularium_messages_on_workspace_and_thread_key"
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

  create_table "kalendarium_calendars", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "color_hex", default: "#3B82F6", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.boolean "default_for_projects", default: false, null: false
    t.boolean "enabled", default: true, null: false
    t.uuid "kalendarium_connection_id"
    t.jsonb "metadata_json", default: {}, null: false
    t.string "name", null: false
    t.string "provider"
    t.boolean "read_only", default: false, null: false
    t.string "remote_id"
    t.string "source_kind", default: "local", null: false
    t.string "time_zone", default: "UTC", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["kalendarium_connection_id", "remote_id"], name: "index_kalendarium_calendars_on_connection_and_remote_id", unique: true, where: "(remote_id IS NOT NULL)"
    t.index ["workspace_id", "enabled"], name: "index_kalendarium_calendars_on_workspace_and_enabled"
  end

  create_table "kalendarium_connections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "access_token"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.boolean "enabled", default: true, null: false
    t.text "ics_url"
    t.string "label", null: false
    t.text "last_error"
    t.datetime "last_synced_at"
    t.text "oauth_client_id"
    t.text "oauth_client_secret"
    t.uuid "owner_id", null: false
    t.string "owner_type", null: false
    t.string "provider", null: false
    t.text "provider_password"
    t.text "provider_username"
    t.text "refresh_token"
    t.string "remote_account_id"
    t.jsonb "scopes_json", default: [], null: false
    t.jsonb "settings_json", default: {}, null: false
    t.string "status", default: "connected", null: false
    t.text "sync_cursor"
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["owner_type", "owner_id"], name: "index_kalendarium_connections_on_owner"
    t.index ["workspace_id", "enabled"], name: "index_kalendarium_connections_on_workspace_and_enabled"
    t.index ["workspace_id", "owner_type", "owner_id", "provider", "label"], name: "index_kalendarium_connections_uniqueness", unique: true
  end

  create_table "kalendarium_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "all_day", default: false, null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.text "description"
    t.datetime "ends_at_utc", null: false
    t.string "etag"
    t.uuid "kalendarium_calendar_id", null: false
    t.uuid "kalendarium_project_id"
    t.datetime "last_synced_at"
    t.uuid "linked_db_row_id"
    t.uuid "linked_page_id"
    t.string "location"
    t.boolean "meeting_capture_enabled", default: false, null: false
    t.jsonb "metadata_json", default: {}, null: false
    t.integer "reminder_offsets_minutes", default: [], null: false, array: true
    t.string "remote_event_id"
    t.text "rrule"
    t.integer "sequence", default: 0, null: false
    t.string "source_kind", default: "local", null: false
    t.datetime "starts_at_utc", null: false
    t.string "status", default: "confirmed", null: false
    t.string "title", null: false
    t.string "uid"
    t.datetime "updated_at", null: false
    t.uuid "updated_by_id", null: false
    t.string "visibility", default: "default", null: false
    t.uuid "workspace_id", null: false
    t.index ["kalendarium_calendar_id", "remote_event_id"], name: "index_kalendarium_events_on_calendar_and_remote_id", unique: true, where: "(remote_event_id IS NOT NULL)"
    t.index ["kalendarium_calendar_id", "starts_at_utc"], name: "index_kalendarium_events_on_calendar_and_starts_at"
    t.index ["workspace_id", "meeting_capture_enabled", "starts_at_utc"], name: "index_kal_events_on_workspace_capture_starts_at"
    t.index ["workspace_id", "starts_at_utc"], name: "index_kalendarium_events_on_workspace_and_starts_at"
  end

  create_table "kalendarium_projects", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "archived_at"
    t.string "color_hex", default: "#8B5CF6", null: false
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.uuid "kalendarium_calendar_id"
    t.uuid "linked_page_id"
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "archived_at"], name: "index_kalendarium_projects_on_workspace_and_archived_at"
    t.index ["workspace_id", "slug"], name: "index_kalendarium_projects_on_workspace_id_and_slug", unique: true
  end

  create_table "kalendarium_write_proposals", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "expires_at"
    t.uuid "kalendarium_event_id"
    t.string "operation", null: false
    t.jsonb "payload_json", default: {}, null: false
    t.string "proposed_by", default: "api", null: false
    t.datetime "rejected_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "workspace_id", null: false
    t.index ["user_id", "created_at"], name: "index_kalendarium_write_proposals_on_user_and_created_at"
    t.index ["workspace_id", "status"], name: "index_kalendarium_write_proposals_on_workspace_and_status"
  end

  create_table "knowledge_suggestions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "ai_conversation_id"
    t.datetime "converted_at"
    t.datetime "created_at", null: false
    t.datetime "dismissed_at"
    t.datetime "expires_at"
    t.datetime "generated_at", null: false
    t.date "generated_for_date"
    t.jsonb "insights_json", default: [], null: false
    t.string "kind", null: false
    t.jsonb "metadata_json", default: {}, null: false
    t.jsonb "related_notes_json", default: [], null: false
    t.jsonb "sources_json", default: [], null: false
    t.string "status", default: "active", null: false
    t.text "summary", null: false
    t.jsonb "task_suggestions_json", default: [], null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "workspace_id", null: false
    t.index ["ai_conversation_id"], name: "index_knowledge_suggestions_on_ai_conversation_id"
    t.index ["user_id", "workspace_id", "kind", "generated_for_date"], name: "idx_knowledge_suggestions_daily_unique", unique: true, where: "((kind)::text = 'daily_summary'::text)"
    t.index ["user_id", "workspace_id", "status", "generated_at"], name: "idx_knowledge_suggestions_active_lookup"
    t.index ["user_id"], name: "index_knowledge_suggestions_on_user_id"
    t.index ["workspace_id"], name: "index_knowledge_suggestions_on_workspace_id"
  end

  create_table "meeting_bot_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.datetime "last_heartbeat_at"
    t.uuid "meeting_session_id", null: false
    t.jsonb "metadata_json", default: {}, null: false
    t.string "provider", null: false
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.string "worker_id"
    t.index ["meeting_session_id"], name: "index_meeting_bot_runs_on_meeting_session_id"
    t.index ["status", "created_at"], name: "index_meeting_bot_runs_on_status_created_at"
  end

  create_table "meeting_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "action_items_json", default: [], null: false
    t.string "capture_mode", default: "upload", null: false
    t.datetime "consent_warning_seen_at"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.datetime "ended_at"
    t.text "error_message"
    t.text "join_url"
    t.uuid "kalendarium_event_id"
    t.jsonb "metadata_json", default: {}, null: false
    t.uuid "page_id"
    t.datetime "processed_at"
    t.string "provider", default: "local", null: false
    t.datetime "started_at"
    t.string "status", default: "scheduled", null: false
    t.text "summary_markdown"
    t.string "title", null: false
    t.text "transcript_text"
    t.datetime "updated_at", null: false
    t.uuid "updated_by_id", null: false
    t.uuid "workspace_id", null: false
    t.index ["created_at"], name: "index_meeting_sessions_on_created_at", order: :desc
    t.index ["kalendarium_event_id"], name: "index_meeting_sessions_on_kalendarium_event_id"
    t.index ["workspace_id", "status"], name: "index_meeting_sessions_on_workspace_id_and_status"
  end

  create_table "meeting_speaker_aliases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.string "email"
    t.jsonb "metadata_json", default: {}, null: false
    t.string "source", default: "manual", null: false
    t.string "speaker_fingerprint", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "speaker_fingerprint"], name: "index_meeting_speaker_aliases_on_workspace_and_fingerprint", unique: true
  end

  create_table "meeting_utterances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.float "confidence"
    t.datetime "created_at", null: false
    t.integer "ended_ms"
    t.uuid "meeting_session_id", null: false
    t.integer "position", null: false
    t.string "speaker_key", null: false
    t.string "speaker_name"
    t.integer "started_ms"
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.index ["meeting_session_id", "position"], name: "index_meeting_utterances_on_session_and_position", unique: true
  end

  create_table "memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "notification_preferences_json", default: {}, null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.uuid "workspace_id", null: false
    t.index ["user_id", "role", "workspace_id"], name: "index_memberships_on_user_id_role_and_workspace_id"
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
    t.string "cover_artist_name"
    t.text "cover_artist_url"
    t.integer "cover_focal_y", default: 50, null: false
    t.string "cover_preset_key"
    t.text "cover_remote_thumb_url"
    t.text "cover_remote_url"
    t.string "cover_source_name"
    t.text "cover_source_url"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.string "font_style", default: "default", null: false
    t.boolean "full_width", default: false, null: false
    t.string "icon"
    t.boolean "locked", default: false, null: false
    t.string "page_kind", default: "nota", null: false
    t.uuid "parent_page_id"
    t.integer "permission_mode", default: 0, null: false
    t.boolean "remove_blocks", default: false, null: false
    t.string "root_tab_title"
    t.boolean "small_text", default: false, null: false
    t.boolean "suggest_edits", default: false, null: false
    t.string "tab_color", default: "default", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["created_by_id"], name: "index_pages_on_created_by_id"
    t.index ["parent_page_id"], name: "index_pages_on_parent_page_id"
    t.index ["title"], name: "index_pages_on_title", opclass: :gin_trgm_ops, using: :gin
    t.index ["workspace_id", "archived_at"], name: "index_pages_on_workspace_id_and_archived_at"
    t.index ["workspace_id", "page_kind", "updated_at"], name: "index_pages_on_workspace_page_kind_updated_at"
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
    t.uuid "epistularium_message_id"
    t.uuid "kalendarium_event_id"
    t.uuid "meeting_session_id"
    t.jsonb "metadata_json", default: {}, null: false
    t.uuid "page_id"
    t.string "source_content_hash"
    t.uuid "source_id", null: false
    t.string "source_title"
    t.string "source_type", null: false
    t.string "source_uri"
    t.text "text", null: false
    t.integer "token_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["content_hash"], name: "index_search_chunks_on_content_hash"
    t.index ["database_id"], name: "index_search_chunks_on_database_id"
    t.index ["db_row_id"], name: "index_search_chunks_on_db_row_id"
    t.index ["epistularium_message_id"], name: "index_search_chunks_on_epistularium_message_id"
    t.index ["kalendarium_event_id"], name: "index_search_chunks_on_kalendarium_event_id"
    t.index ["meeting_session_id"], name: "index_search_chunks_on_meeting_session_id"
    t.index ["page_id"], name: "index_search_chunks_on_page_id"
    t.index ["source_content_hash"], name: "index_search_chunks_on_source_content_hash"
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

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "ai_loader_style", default: "disco_orbit", null: false
    t.integer "ai_search_answer_rate_limit_per_minute", default: 12, null: false
    t.decimal "ai_search_daily_budget_usd", precision: 12, scale: 4, default: "1.5", null: false
    t.integer "ai_search_semantic_rate_limit_per_minute", default: 24, null: false
    t.boolean "auto_time_zone", default: true, null: false
    t.jsonb "calendar_extra_time_zones", default: [], null: false
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
    t.jsonb "push_notification_preferences", default: {}, null: false
    t.boolean "push_quiet_hours_enabled", default: false, null: false
    t.string "push_quiet_hours_ends_at", default: "07:00", null: false
    t.string "push_quiet_hours_starts_at", default: "22:00", null: false
    t.boolean "reduce_ai_loader_motion", default: false, null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.boolean "show_text_direction_controls", default: false, null: false
    t.boolean "show_view_history", default: true, null: false
    t.string "slack_notification_preference", default: "off", null: false
    t.string "smtp_address"
    t.string "smtp_authentication", default: "plain", null: false
    t.string "smtp_domain"
    t.boolean "smtp_enable_starttls_auto", default: true, null: false
    t.string "smtp_from_email"
    t.string "smtp_from_name"
    t.string "smtp_password"
    t.integer "smtp_port"
    t.string "smtp_username"
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

  create_table "web_push_subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "auth", null: false
    t.datetime "created_at", null: false
    t.text "endpoint", null: false
    t.datetime "expiration_time"
    t.datetime "last_delivered_at"
    t.datetime "last_error_at"
    t.text "last_error_message"
    t.text "p256dh", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.uuid "user_id", null: false
    t.index ["endpoint"], name: "index_web_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id", "created_at"], name: "index_web_push_subscriptions_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_web_push_subscriptions_on_user_id"
  end

  create_table "workflow_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.datetime "cancelled_at"
    t.decimal "confidence_score", precision: 4, scale: 2, default: "1.0", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.jsonb "input_json", default: {}, null: false
    t.integer "max_attempts", default: 2, null: false
    t.jsonb "metadata_json", default: {}, null: false
    t.jsonb "plan_json", default: {}, null: false
    t.jsonb "policy_snapshot_json", default: {}, null: false
    t.datetime "queued_at", null: false
    t.jsonb "result_json", default: {}, null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.string "trigger_source", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.string "workflow_kind", null: false
    t.uuid "workspace_id", null: false
    t.index ["user_id", "created_at"], name: "idx_workflow_runs_on_user_created_at"
    t.index ["user_id"], name: "index_workflow_runs_on_user_id"
    t.index ["workflow_kind", "status"], name: "idx_workflow_runs_on_kind_status"
    t.index ["workspace_id", "status", "created_at"], name: "idx_workflow_runs_on_workspace_status_created_at"
    t.index ["workspace_id"], name: "index_workflow_runs_on_workspace_id"
  end

  create_table "workspace_cover_assets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "artist_name"
    t.text "artist_url"
    t.datetime "created_at", null: false
    t.uuid "created_by_id", null: false
    t.string "external_id"
    t.string "label"
    t.text "remote_image_url"
    t.text "remote_thumb_url"
    t.string "source_kind", default: "upload", null: false
    t.string "source_name"
    t.text "source_url"
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["created_by_id"], name: "index_workspace_cover_assets_on_created_by_id"
    t.index ["workspace_id", "created_by_id", "created_at"], name: "index_workspace_cover_assets_picker_lookup"
    t.index ["workspace_id", "created_by_id", "source_kind", "external_id"], name: "index_workspace_cover_assets_on_external_source", unique: true, where: "(external_id IS NOT NULL)"
    t.index ["workspace_id"], name: "index_workspace_cover_assets_on_workspace_id"
  end

  create_table "workspace_emojis", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.uuid "workspace_id", null: false
    t.index ["workspace_id", "name"], name: "index_workspace_emojis_on_workspace_id_and_name", unique: true
    t.index ["workspace_id"], name: "index_workspace_emojis_on_workspace_id"
  end

  create_table "workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "analytics_enabled", default: true, null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.string "icon"
    t.boolean "join_link_enabled", default: false, null: false
    t.string "join_link_token"
    t.string "name", null: false
    t.string "shell_status_bar_mode", default: "all", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.string "workspace_color", default: "#f43f5e", null: false
    t.index ["archived_at"], name: "index_workspaces_on_archived_at"
    t.index ["join_link_token"], name: "index_workspaces_on_join_link_token", unique: true
    t.index ["slug"], name: "index_workspaces_on_slug", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_action_events", "agent_actions"
  add_foreign_key "agent_action_events", "users", column: "actor_id"
  add_foreign_key "agent_action_events", "workspaces"
  add_foreign_key "agent_actions", "users"
  add_foreign_key "agent_actions", "users", column: "approved_by_id"
  add_foreign_key "agent_actions", "users", column: "rejected_by_id"
  add_foreign_key "agent_actions", "workspaces"
  add_foreign_key "agent_policies", "workspaces"
  add_foreign_key "ai_conversations", "pages"
  add_foreign_key "ai_conversations", "users"
  add_foreign_key "ai_conversations", "workspaces"
  add_foreign_key "ai_usage_logs", "users"
  add_foreign_key "ai_usage_logs", "workspaces"
  add_foreign_key "api_token_audit_events", "api_tokens"
  add_foreign_key "api_token_audit_events", "users"
  add_foreign_key "api_token_audit_events", "workspaces"
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
  add_foreign_key "database_share_links", "databases"
  add_foreign_key "database_share_links", "users", column: "created_by_id"
  add_foreign_key "database_share_links", "workspaces"
  add_foreign_key "database_shares", "databases"
  add_foreign_key "database_shares", "users"
  add_foreign_key "database_shares", "users", column: "created_by_id"
  add_foreign_key "database_templates", "databases", on_delete: :nullify
  add_foreign_key "database_templates", "users", column: "created_by_id"
  add_foreign_key "database_templates", "workspaces"
  add_foreign_key "database_views", "databases"
  add_foreign_key "database_views", "users", column: "created_by_id"
  add_foreign_key "database_views", "workspaces"
  add_foreign_key "databases", "database_templates"
  add_foreign_key "databases", "pages", column: "linked_page_id", on_delete: :nullify
  add_foreign_key "databases", "users", column: "created_by_id"
  add_foreign_key "databases", "workspaces"
  add_foreign_key "db_cells", "db_properties"
  add_foreign_key "db_cells", "db_rows"
  add_foreign_key "db_cells", "workspaces"
  add_foreign_key "db_properties", "databases"
  add_foreign_key "db_properties", "workspaces"
  add_foreign_key "db_rows", "databases"
  add_foreign_key "db_rows", "pages", column: "linked_page_id", on_delete: :nullify
  add_foreign_key "db_rows", "workspaces"
  add_foreign_key "epistularium_accounts", "users", column: "created_by_id"
  add_foreign_key "epistularium_accounts", "workspaces"
  add_foreign_key "epistularium_messages", "epistularium_accounts"
  add_foreign_key "epistularium_messages", "workspaces"
  add_foreign_key "favorites", "users"
  add_foreign_key "favorites", "workspaces"
  add_foreign_key "invitations", "users", column: "accepted_by_id"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "invitations", "workspaces"
  add_foreign_key "kalendarium_calendars", "kalendarium_connections"
  add_foreign_key "kalendarium_calendars", "users", column: "created_by_id"
  add_foreign_key "kalendarium_calendars", "workspaces"
  add_foreign_key "kalendarium_connections", "users", column: "created_by_id"
  add_foreign_key "kalendarium_connections", "workspaces"
  add_foreign_key "kalendarium_events", "db_rows", column: "linked_db_row_id"
  add_foreign_key "kalendarium_events", "kalendarium_calendars"
  add_foreign_key "kalendarium_events", "kalendarium_projects"
  add_foreign_key "kalendarium_events", "pages", column: "linked_page_id"
  add_foreign_key "kalendarium_events", "users", column: "created_by_id"
  add_foreign_key "kalendarium_events", "users", column: "updated_by_id"
  add_foreign_key "kalendarium_events", "workspaces"
  add_foreign_key "kalendarium_projects", "kalendarium_calendars"
  add_foreign_key "kalendarium_projects", "pages", column: "linked_page_id"
  add_foreign_key "kalendarium_projects", "users", column: "created_by_id"
  add_foreign_key "kalendarium_projects", "workspaces"
  add_foreign_key "kalendarium_write_proposals", "kalendarium_events"
  add_foreign_key "kalendarium_write_proposals", "users"
  add_foreign_key "kalendarium_write_proposals", "workspaces"
  add_foreign_key "knowledge_suggestions", "ai_conversations", on_delete: :nullify
  add_foreign_key "knowledge_suggestions", "users", on_delete: :cascade
  add_foreign_key "knowledge_suggestions", "workspaces", on_delete: :cascade
  add_foreign_key "meeting_bot_runs", "meeting_sessions"
  add_foreign_key "meeting_sessions", "kalendarium_events"
  add_foreign_key "meeting_sessions", "pages"
  add_foreign_key "meeting_sessions", "users", column: "created_by_id"
  add_foreign_key "meeting_sessions", "users", column: "updated_by_id"
  add_foreign_key "meeting_sessions", "workspaces"
  add_foreign_key "meeting_speaker_aliases", "workspaces"
  add_foreign_key "meeting_utterances", "meeting_sessions"
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
  add_foreign_key "search_chunks", "epistularium_messages"
  add_foreign_key "search_chunks", "kalendarium_events"
  add_foreign_key "search_chunks", "meeting_sessions"
  add_foreign_key "search_chunks", "pages"
  add_foreign_key "search_chunks", "workspaces"
  add_foreign_key "share_link_views", "pages"
  add_foreign_key "share_link_views", "share_links"
  add_foreign_key "share_link_views", "workspaces"
  add_foreign_key "share_links", "pages"
  add_foreign_key "share_links", "users", column: "created_by_id"
  add_foreign_key "share_links", "workspaces"
  add_foreign_key "web_push_subscriptions", "users"
  add_foreign_key "workflow_runs", "users"
  add_foreign_key "workflow_runs", "workspaces"
  add_foreign_key "workspace_cover_assets", "users", column: "created_by_id"
  add_foreign_key "workspace_cover_assets", "workspaces"
  add_foreign_key "workspace_emojis", "workspaces"
end
