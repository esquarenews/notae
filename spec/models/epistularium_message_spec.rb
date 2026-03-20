require "rails_helper"

RSpec.describe EpistulariumMessage, type: :model do
  def build_stack(suffix:)
    user = User.create!(email: "epistularium-message-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Epistularium Message #{suffix}", slug: "epistularium-message-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Inbox",
      provider_username: "me@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.example.com" }
    )

    [ user, workspace, account ]
  end

  it "builds searchable source text from headers and message content" do
    _user, workspace, account = build_stack(suffix: "search-source")
    message = described_class.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-1",
      subject: "Board update",
      from_name: "Alex",
      from_email: "alex@example.com",
      to_recipients_json: [ { "email" => "team@example.com" } ],
      snippet: "Review the attached board update.",
      body_text: "The board pack is due on Friday."
    )

    expect(message.search_source_text).to include("Board update")
    expect(message.search_source_text).to include("Alex")
    expect(message.search_source_text).to include("team@example.com")
    expect(message.search_source_text).to include("board pack")
  end

  it "queues reindexing only for searchable changes and removes indexed chunks on destroy" do
    _user, workspace, account = build_stack(suffix: "reindex")
    allow(Search::IndexEpistulariumMessageJob).to receive(:perform_later)

    message = described_class.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-2",
      subject: "Launch",
      from_email: "alex@example.com",
      body_text: "Initial body"
    )
    expect(Search::IndexEpistulariumMessageJob).to have_received(:perform_later).with(message.id).once

    message.update!(last_synced_at: Time.current + 5.minutes)
    expect(Search::IndexEpistulariumMessageJob).to have_received(:perform_later).with(message.id).once

    message.update!(body_text: "Updated body")
    expect(Search::IndexEpistulariumMessageJob).to have_received(:perform_later).with(message.id).twice

    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_EPISTULARIUM_MESSAGE,
      source_id: message.id,
      epistularium_message: message,
      chunk_index: 0,
      text: "Updated body",
      token_count: 2,
      content_hash: "epistularium-message-destroy"
    )

    expect do
      message.destroy!
    end.to change { SearchChunk.where(source_type: SearchChunk::SOURCE_EPISTULARIUM_MESSAGE, source_id: message.id).count }.from(1).to(0)
  end

  it "orders inbox and sent mailboxes by their natural timestamps" do
    _user, workspace, account = build_stack(suffix: "mailbox-order")

    older_inbox = described_class.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-inbox-older",
      mailbox: "inbox",
      subject: "Older inbox",
      from_email: "alex@example.com",
      received_at: 2.days.ago,
      created_at: 2.days.ago
    )
    newer_inbox = described_class.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-inbox-newer",
      mailbox: "inbox",
      subject: "Newer inbox",
      from_email: "alex@example.com",
      received_at: 1.day.ago,
      created_at: 1.day.ago
    )
    older_sent = described_class.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-sent-older",
      mailbox: "sent",
      subject: "Older sent",
      from_email: "alex@example.com",
      sent_at: 3.days.ago,
      created_at: 3.days.ago
    )
    newer_sent = described_class.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-sent-newer",
      mailbox: "sent",
      subject: "Newer sent",
      from_email: "alex@example.com",
      sent_at: 12.hours.ago,
      created_at: 12.hours.ago
    )

    inbox_ids = described_class.for_workspace(workspace).for_account(account).for_mailbox("inbox").recent_first_for_mailbox("inbox").pluck(:id)
    sent_ids = described_class.for_workspace(workspace).for_account(account).for_mailbox("sent").recent_first_for_mailbox("sent").pluck(:id)

    expect(inbox_ids.first(2)).to eq([ newer_inbox.id, older_inbox.id ])
    expect(sent_ids.first(2)).to eq([ newer_sent.id, older_sent.id ])
  end
end
