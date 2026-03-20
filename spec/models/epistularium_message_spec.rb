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
end
