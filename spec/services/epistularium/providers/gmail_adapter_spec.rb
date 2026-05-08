require "rails_helper"

RSpec.describe Epistularium::Providers::GmailAdapter do
  def build_stack(suffix:)
    user = User.create!(email: "epistularium-gmail-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Epistularium Gmail #{suffix}", slug: "epistularium-gmail-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "gmail",
      label: "Gmail",
      access_token: "google-token-#{suffix}"
    )

    [ user, workspace, account ]
  end

  def gmail_body(value)
    Base64.urlsafe_encode64(value).delete("=")
  end

  def google_response(code:, body:)
    Struct.new(:code, :body).new(code.to_s, body.to_json)
  end

  it "imports full Gmail messages from inbox and sent mailboxes" do
    _user, workspace, account = build_stack(suffix: "import")
    adapter = described_class.new(account: account)

    allow(adapter).to receive(:fetch_json) do |path:, params:, allow_refresh: true|
      if path == "/gmail/v1/users/me/messages"
        label_id = params.fetch(:labelIds)
        if label_id == "INBOX"
          { "messages" => [ { "id" => "inbox-1" } ] }
        else
          { "messages" => [ { "id" => "sent-1" } ] }
        end
      elsif path.end_with?("/inbox-1")
        {
          "id" => "inbox-1",
          "threadId" => "thread-1",
          "labelIds" => %w[INBOX UNREAD],
          "internalDate" => Time.utc(2026, 3, 18, 5, 0, 0).to_i * 1000,
          "snippet" => "Can you review this launch note?",
          "payload" => {
            "headers" => [
              { "name" => "Subject", "value" => "Launch note" },
              { "name" => "From", "value" => "Alex <alex@example.com>" },
              { "name" => "To", "value" => "Team <team@example.com>" },
              { "name" => "Date", "value" => "Tue, 18 Mar 2026 16:00:00 +1100" },
              { "name" => "Message-ID", "value" => "<inbox-1@example.com>" }
            ],
            "parts" => [
              { "mimeType" => "text/plain", "body" => { "data" => gmail_body("Please review the launch note.") } },
              { "mimeType" => "text/html", "body" => { "data" => gmail_body("<p>Please review the <strong>launch note</strong>.</p>") } }
            ]
          }
        }
      else
        {
          "id" => "sent-1",
          "threadId" => "thread-2",
          "labelIds" => %w[SENT],
          "internalDate" => Time.utc(2026, 3, 18, 7, 0, 0).to_i * 1000,
          "snippet" => "Sent summary",
          "payload" => {
            "headers" => [
              { "name" => "Subject", "value" => "Sent summary" },
              { "name" => "From", "value" => "Me <me@example.com>" },
              { "name" => "To", "value" => "Alex <alex@example.com>" },
              { "name" => "Date", "value" => "Tue, 18 Mar 2026 18:00:00 +1100" },
              { "name" => "Message-ID", "value" => "<sent-1@example.com>" }
            ],
            "parts" => [
              { "mimeType" => "text/plain", "body" => { "data" => gmail_body("Sent summary body.") } }
            ]
          }
        }
      end
    end

    adapter.sync!

    expect(account.reload.sync_cursor).to be_present
    expect(account.epistularium_messages.count).to eq(2)

    inbox = account.epistularium_messages.find_by(provider_message_id: "inbox-1")
    expect(inbox.mailbox).to eq("inbox")
    expect(inbox.display_subject).to eq("Launch note")
    expect(inbox.body_text).to include("Please review the launch note")
    expect(inbox.body_html).to include("<strong>launch note</strong>")
    expect(inbox.unread).to eq(true)

    sent = account.epistularium_messages.find_by(provider_message_id: "sent-1")
    expect(sent.mailbox).to eq("sent")
    expect(sent.from_email).to eq("me@example.com")
  end

  it "stores html-like Gmail text/plain bodies as renderable html" do
    _user, _workspace, account = build_stack(suffix: "html-text")
    adapter = described_class.new(account: account)

    allow(adapter).to receive(:fetch_json) do |path:, params:, allow_refresh: true|
      if path == "/gmail/v1/users/me/messages"
        { "messages" => [ { "id" => "inbox-html-text" } ] }
      else
        {
          "id" => "inbox-html-text",
          "threadId" => "thread-html-text",
          "labelIds" => %w[INBOX],
          "internalDate" => Time.utc(2026, 3, 18, 5, 0, 0).to_i * 1000,
          "snippet" => "HTML-like text body",
          "payload" => {
            "headers" => [
              { "name" => "Subject", "value" => "HTML text body" },
              { "name" => "From", "value" => "Alex <alex@example.com>" },
              { "name" => "To", "value" => "Team <team@example.com>" },
              { "name" => "Date", "value" => "Tue, 18 Mar 2026 16:00:00 +1100" },
              { "name" => "Message-ID", "value" => "<inbox-html-text@example.com>" }
            ],
            "parts" => [
              {
                "mimeType" => "text/plain",
                "body" => {
                  "data" => gmail_body(
                    <<~HTML
                      <div class="preheader">This should stay hidden.</div>
                      <p>Hello from Gmail HTML-like text/plain content.</p>
                      <p><strong>Formatting should survive.</strong></p>
                    HTML
                  )
                }
              }
            ]
          }
        }
      end
    end

    adapter.sync!(max_messages_per_mailbox: 1)

    message = account.epistularium_messages.find_by!(provider_message_id: "inbox-html-text")
    expect(message.body_html).to include("Hello from Gmail HTML-like text/plain content.")
    expect(message.body_html).to include("<strong>Formatting should survive.</strong>")
    expect(message.body_html).not_to include("This should stay hidden.")
    expect(message.body_text).to include("Hello from Gmail HTML-like text/plain content.")
    expect(message.body_text).not_to include("<strong>")
  end

  it "limits Gmail full backfill requests to the trailing 12 months" do
    _user, _workspace, account = build_stack(suffix: "backfill-window")
    adapter = described_class.new(account: account)
    captured_queries = []

    allow(adapter).to receive(:fetch_json) do |path:, params:, allow_refresh: true|
      if path == "/gmail/v1/users/me/messages"
        captured_queries << params[:q]
        { "messages" => [] }
      else
        raise "unexpected message fetch"
      end
    end

    adapter.sync!(full_backfill: true, update_cursor: true)

    expected_query = "after:#{Epistularium::SyncConfig.backfill_cutoff_time.to_i}"
    expect(captured_queries).to eq([ expected_query, expected_query ])
    expect(account.reload.settings_json["full_backfill_completed_at"]).to be_present
  end

  it "falls back to current google oauth credentials when stored Gmail credentials are invalid" do
    _user, _workspace, account = build_stack(suffix: "refresh-credential-fallback")
    account.update!(
      refresh_token: "gmail-refresh-token",
      oauth_client_id: "stale-client-id",
      oauth_client_secret: "stale-client-secret"
    )
    adapter = described_class.new(account: account)

    allow(Epistularium::GoogleOauthService).to receive(:resolved_client_id).and_return("fresh-client-id")
    allow(Epistularium::GoogleOauthService).to receive(:resolved_client_secret).and_return("fresh-client-secret")
    seen_client_ids = []
    allow(adapter).to receive(:perform_token_refresh_request) do |client_id:, client_secret:|
      seen_client_ids << client_id
      if client_id == "stale-client-id" && client_secret == "stale-client-secret"
        google_response(code: 401, body: { "error" => "invalid_client", "error_description" => "OAuth client was not found" })
      else
        google_response(code: 200, body: { "access_token" => "fresh-access-token", "expires_in" => 3600 })
      end
    end

    adapter.send(:refresh_access_token!)

    expect(seen_client_ids).to eq([ "stale-client-id", "fresh-client-id" ])
    expect(account.reload.access_token).to eq("fresh-access-token")
    expect(account.oauth_client_id).to eq("fresh-client-id")
    expect(account.oauth_client_secret).to eq("fresh-client-secret")
    expect(account.settings_json["google_access_token_expires_at"]).to be_present
  end
end
