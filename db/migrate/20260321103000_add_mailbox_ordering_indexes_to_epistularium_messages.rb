class AddMailboxOrderingIndexesToEpistulariumMessages < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :epistularium_messages,
              [ :epistularium_account_id, :received_at, :created_at ],
              name: "index_epistularium_messages_on_account_inbox_recency",
              order: { received_at: :desc, created_at: :desc },
              where: "mailbox = 'inbox'",
              algorithm: :concurrently

    add_index :epistularium_messages,
              [ :epistularium_account_id, :sent_at, :created_at ],
              name: "index_epistularium_messages_on_account_sent_recency",
              order: { sent_at: :desc, created_at: :desc },
              where: "mailbox = 'sent'",
              algorithm: :concurrently
  end
end
