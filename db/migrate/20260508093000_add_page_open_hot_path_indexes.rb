class AddPageOpenHotPathIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :notifications,
              %i[workspace_id recipient_id created_at],
              name: "idx_notifications_unread_recent_workspace_user",
              order: { created_at: :desc },
              where: "read_at IS NULL",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :agent_actions,
              %i[workspace_id proposed_by updated_at],
              name: "idx_agent_actions_workspace_proposed_updated",
              order: { updated_at: :desc },
              algorithm: :concurrently,
              if_not_exists: true

    add_index :workflow_runs,
              %i[workspace_id trigger_source updated_at],
              name: "idx_workflow_runs_workspace_trigger_updated",
              order: { updated_at: :desc },
              algorithm: :concurrently,
              if_not_exists: true

    add_index :knowledge_suggestions,
              %i[workspace_id status kind generated_at created_at],
              name: "idx_knowledge_suggestions_workspace_active_recent",
              order: { generated_at: :desc, created_at: :desc },
              algorithm: :concurrently,
              if_not_exists: true

    return unless postgresql?

    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_epistularium_unread_inbox_workspace_recent
      ON epistularium_messages (workspace_id, (COALESCE(received_at, created_at)) DESC)
      WHERE mailbox = 'inbox' AND unread = TRUE
    SQL
  end

  def down
    if postgresql?
      execute "DROP INDEX CONCURRENTLY IF EXISTS idx_epistularium_unread_inbox_workspace_recent"
    end

    remove_index :knowledge_suggestions,
                 name: "idx_knowledge_suggestions_workspace_active_recent",
                 algorithm: :concurrently,
                 if_exists: true
    remove_index :workflow_runs,
                 name: "idx_workflow_runs_workspace_trigger_updated",
                 algorithm: :concurrently,
                 if_exists: true
    remove_index :agent_actions,
                 name: "idx_agent_actions_workspace_proposed_updated",
                 algorithm: :concurrently,
                 if_exists: true
    remove_index :notifications,
                 name: "idx_notifications_unread_recent_workspace_user",
                 algorithm: :concurrently,
                 if_exists: true
  end

  private

  def postgresql?
    connection.adapter_name.casecmp("PostgreSQL").zero?
  end
end
