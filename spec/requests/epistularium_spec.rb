require "rails_helper"

RSpec.describe "Epistularium", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before do
    clear_enqueued_jobs
  end

  def build_stack(suffix:, openai_api_key: nil)
    user_attributes = {
      email: "epistularium-request-#{suffix}@example.com",
      password: "password123"
    }
    user_attributes[:openai_api_key] = openai_api_key if openai_api_key.present?
    user = User.create!(**user_attributes)
    workspace = Workspace.create!(name: "Epistularium Request #{suffix}", slug: "epistularium-request-#{suffix}")
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
    message = EpistulariumMessage.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-#{suffix}",
      subject: "Launch note #{suffix}",
      from_name: "Alex",
      from_email: "alex@example.com",
      body_text: "Please review the launch note for #{suffix}.",
      snippet: "Launch note snippet #{suffix}"
    )

    [ user, workspace, account, message ]
  end

  it "renders the Epistularium page with message content and AI actions" do
    user, workspace, account, message = build_stack(suffix: "show")
    sign_in user

    get workspace_epistularium_path(
      workspace_slug: workspace.slug,
      account_id: account.id,
      mailbox: "inbox",
      message_id: message.id
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Epistularium")
    expect(response.body).to include("Launch note show")
    expect(response.body).to include("AI draft suggestions")
    expect(response.body).to include("Manage Epistula")
    expect(response.body).to include("Suggest reply draft")
    expect(response.body).to include("data-controller=\"epistularium-poller\"")
  end

  it "returns refreshed mailbox html and a polling cursor for in-place updates" do
    user, workspace, account, message = build_stack(suffix: "json-refresh")
    sign_in user

    get workspace_epistularium_path(
      workspace_slug: workspace.slug,
      account_id: account.id,
      mailbox: "inbox",
      message_id: message.id
    ), headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)

    payload = JSON.parse(response.body)
    expect(payload["cursor"]).to be_present
    expect(payload["active"]).to eq(true)
    expect(payload["html"]).to include("Launch note json-refresh")
    expect(payload["html"]).to include("data-epistularium-pane-key=\"list\"")
    expect(payload["html"]).to include("data-epistularium-selected-message-id")
  end

  it "renders a persistent visual indicator for the active email account" do
    user, workspace, account, message = build_stack(suffix: "active-account")
    account.update!(label: "eSquareNews")
    EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Personal Mail",
      provider_username: "person@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.personal.example.com" }
    )
    sign_in user

    get workspace_epistularium_path(
      workspace_slug: workspace.slug,
      account_id: account.id,
      mailbox: "inbox",
      message_id: message.id
    )

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    account_items = document.css(".notae-epistularium-account-item")
    active_item = account_items.find { |node| node["class"].to_s.include?("is-active") }

    expect(account_items.size).to eq(2)
    expect(active_item).to be_present
    expect(active_item["style"].to_s).to include("--notae-epistularium-accent:")
    expect(active_item.at_css(".notae-epistularium-account-indicator")).to be_present
    expect(active_item.at_css(".notae-chip-button.is-active[aria-current='page']")).to be_present
    expect(active_item.text).to include("eSquareNews")

    message_list_pane = document.at_css(".notae-epistularium-pane-list.has-account-accent")
    expect(message_list_pane).to be_present
    expect(message_list_pane["style"].to_s).to include("--notae-epistularium-accent:")
    expect(message_list_pane.text).to include("eSquareNews · Inbox")

    inactive_item = account_items.reject { |node| node == active_item }.first
    expect(inactive_item["class"].to_s).not_to include("is-active")
    expect(inactive_item["style"].to_s).to include("--notae-epistularium-accent:")
    expect(inactive_item.at_css(".notae-epistularium-account-indicator")).to be_present
  end

  it "renders readable email html without leaking stylesheet text into the reading pane" do
    user, workspace, account, message = build_stack(suffix: "html-render")
    message.update!(
      body_text: nil,
      body_html: <<~HTML
        <html>
          <head>
            <style>
              .promo { color: #ff0000; }
              body { font-family: Arial; }
            </style>
          </head>
          <body>
            <div class="preheader">This should stay hidden.</div>
            <table>
              <tr>
                <td><p>Hello from the readable email body.</p></td>
              </tr>
            </table>
          </body>
        </html>
      HTML
    )
    sign_in user

    get workspace_epistularium_path(
      workspace_slug: workspace.slug,
      account_id: account.id,
      mailbox: "inbox",
      message_id: message.id
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Hello from the readable email body.")
    expect(response.body).not_to include("font-family: Arial")
    expect(response.body).not_to include("This should stay hidden.")
    expect(response.body).to include("notae-epistularium-message-meta-row")
    expect(response.body).to include("notae-epistularium-message-snippet")
  end

  it "renders html-like body_text as html when no body_html is stored" do
    user, workspace, account, message = build_stack(suffix: "html-body-text")
    message.update!(
      body_html: nil,
      body_text: <<~HTML
        <div class="preheader">This should stay hidden.</div>
        <p>Hello from HTML-like body text.</p>
        <p><strong>Readable formatting</strong> should remain intact.</p>
      HTML
    )
    sign_in user

    get workspace_epistularium_path(
      workspace_slug: workspace.slug,
      account_id: account.id,
      mailbox: "inbox",
      message_id: message.id
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Hello from HTML-like body text.")
    expect(response.body).to include("<strong>Readable formatting</strong>")
    expect(response.body).not_to include("&lt;strong&gt;Readable formatting&lt;/strong&gt;")
    expect(response.body).not_to include("This should stay hidden.")
  end

  it "strips leading css boilerplate from stored html emails before rendering" do
    user, workspace, account, message = build_stack(suffix: "css-preamble")
    message.update!(
      body_text: nil,
      body_html: <<~HTML
        /* What it does: Stops email clients resizing small text. */
        * { -ms-text-size-adjust: 100%; -webkit-text-size-adjust: 100%; }
        table, td { border-collapse: collapse !important; mso-table-lspace: 0pt !important; }
        @media screen and (max-width: 600px) { .email-container { width: 100% !important; } }
        <table>
          <tr>
            <td>
              <h1>Parent Teacher Student Interviews</h1>
              <p>Dear family, the interview schedule is now available.</p>
            </td>
          </tr>
        </table>
      HTML
    )
    sign_in user

    get workspace_epistularium_path(
      workspace_slug: workspace.slug,
      account_id: account.id,
      mailbox: "inbox",
      message_id: message.id
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Parent Teacher Student Interviews")
    expect(response.body).to include("Dear family, the interview schedule is now available.")
    expect(response.body).not_to include("-webkit-text-size-adjust")
    expect(response.body).not_to include("border-collapse")
  end

  it "renders Epistularium settings with provider setup and navigation entry" do
    user, workspace, = build_stack(suffix: "settings-page")
    sign_in user

    get workspace_epistularium_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Connect Gmail with OAuth")
    expect(response.body).to include("Add IMAP or Amazon WorkMail")
    expect(response.body).to include("Manage Epistula")
    expect(response.body).to include("Open Epistularium")
    expect(response.body).to include("notae-sidebar-link-label\">Epistularium")
    expect(response.body).to include("For Amazon WorkMail, use the incoming IMAP host")
    expect(response.body).to include("username must be the full mailbox email address")
    expect(response.body).to include("Last fresh mail check")
    expect(response.body).to include("Backfill status")
    expect(response.body).to include("Backfill window: Last 12 months")
    expect(response.body).to include("data-controller=\"google-oauth-launch\"")
    expect(response.body).to include("submit-&gt;google-oauth-launch#submit")
    expect(response.body).to include("data-google-oauth-launch=\"true\"")
  end

  it "auto-recovers a stalled queued sync when settings is opened" do
    user, workspace, account, = build_stack(suffix: "settings-stalled")
    account.mark_sync_enqueued!(at: 3.minutes.ago)
    sign_in user

    expect do
      get workspace_epistularium_settings_path(workspace_slug: workspace.slug)
    end.to have_enqueued_job(Epistularium::SyncConnectionJob).with(account.id, mode: "bootstrap")

    expect(response).to have_http_status(:ok)
    expect(account.reload.sync_enqueued_at).to be_present
  end

  it "shows the last fresh-mail check in settings separately from generic sync timestamps" do
    travel_to(Time.zone.parse("2026-03-22 12:00:00")) do
      user, workspace, account, message = build_stack(suffix: "settings-visible-sync")
      account.update!(
        last_synced_at: 7.hours.ago,
        status: "connected",
        settings_json: account.settings_json.to_h.merge(
          "last_fresh_sync_at" => 30.minutes.ago.iso8601,
          "last_backfill_sync_at" => 2.hours.ago.iso8601
        )
      )
      message.update!(last_synced_at: 30.minutes.ago)
      sign_in user

      get workspace_epistularium_settings_path(workspace_slug: workspace.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Last fresh mail check: 30 minutes ago")
      expect(response.body).to include("Last backfill batch: about 2 hours ago")
      expect(response.body).not_to include("about 7 hours ago")
    end
  end

  it "redirects directly to Google OAuth with a signed state payload for Gmail" do
    user, workspace, = build_stack(suffix: "google-oauth-authorize")
    sign_in user
    oauth_service = instance_double(Epistularium::GoogleOauthService)
    allow(Epistularium::GoogleOauthService).to receive(:new).and_return(oauth_service)
    allow(oauth_service).to receive(:authorization_url) do |redirect_uri:, state:|
      payload = Rails.application.message_verifier("epistularium_google_oauth_state").verify(state)
      expect(payload["workspace_id"]).to eq(workspace.id)
      expect(payload["user_id"]).to eq(user.id)
      expect(payload["owner_scope"]).to eq("workspace")
      expect(payload["label"]).to eq("Team Gmail")
      expect(redirect_uri).to end_with(epistularium_google_callback_path)
      "https://accounts.google.com/o/oauth2/v2/auth?state=#{CGI.escape(state)}"
    end

    get google_authorize_epistularium_accounts_path(workspace_slug: workspace.slug), params: {
      "epistularium_account" => { "owner_scope" => "workspace" },
      label: "Team Gmail"
    }

    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("accounts.google.com/o/oauth2")
  end

  it "uses the configured public app host for Google OAuth when the request arrives via localhost" do
    user, workspace, = build_stack(suffix: "google-oauth-public-host")
    sign_in user
    oauth_service = instance_double(Epistularium::GoogleOauthService)
    allow(Epistularium::GoogleOauthService).to receive(:new).and_return(oauth_service)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("APP_BASE_URL").and_return(nil)
    allow(ENV).to receive(:[]).with("APP_HOST").and_return("notae.example.com")
    allow(ENV).to receive(:[]).with("APP_PORT").and_return("443")
    allow(ENV).to receive(:[]).with("APP_PROTOCOL").and_return(nil)
    allow(oauth_service).to receive(:authorization_url) do |redirect_uri:, state:|
      payload = Rails.application.message_verifier("epistularium_google_oauth_state").verify(state)
      expect(payload["workspace_id"]).to eq(workspace.id)
      expect(redirect_uri).to eq("https://notae.example.com#{epistularium_google_callback_path}")
      "https://accounts.google.com/o/oauth2/v2/auth?state=#{CGI.escape(state)}"
    end

    get google_authorize_epistularium_accounts_path(workspace_slug: workspace.slug), params: {
      "epistularium_account" => { "owner_scope" => "workspace" },
      label: "Team Gmail"
    }, headers: {
      "Host" => "localhost:4000"
    }

    expect(response).to have_http_status(:found)
    expect(response.headers["Location"]).to include("accounts.google.com/o/oauth2")
  end

  it "runs a bootstrap Gmail sync inline after OAuth callback so recent mail appears quickly" do
    user, workspace, = build_stack(suffix: "google-oauth-callback")
    sign_in user
    state = Rails.application.message_verifier("epistularium_google_oauth_state").generate(
      {
        "workspace_id" => workspace.id,
        "user_id" => user.id,
        "owner_scope" => "workspace",
        "label" => "Workspace Gmail"
      },
      expires_in: 20.minutes
    )
    oauth_service = instance_double(Epistularium::GoogleOauthService, exchange_code!: {
      access_token: "oauth-access",
      refresh_token: "oauth-refresh",
      scope: "https://www.googleapis.com/auth/gmail.readonly",
      token_type: "Bearer",
      expires_in: 3600
    })
    allow(Epistularium::GoogleOauthService).to receive(:new).and_return(oauth_service)
    allow(Epistularium::GoogleOauthService).to receive(:resolved_client_id).and_return("oauth-client-id")
    allow(Epistularium::GoogleOauthService).to receive(:resolved_client_secret).and_return("oauth-client-secret")
    allow(Epistularium::SyncConnectionJob).to receive(:perform_now)

    get epistularium_google_callback_path, params: {
      state: state,
      code: "google-auth-code"
    }

    account = EpistulariumAccount.order(:created_at).last
    expect(Epistularium::SyncConnectionJob).to have_received(:perform_now).with(account.id, mode: "bootstrap")
    expect(account.provider).to eq("gmail")
    expect(account.owner).to eq(workspace)
    expect(account.label).to eq("Workspace Gmail")
    expect(account.access_token).to eq("oauth-access")
    expect(account.refresh_token).to eq("oauth-refresh")
    expect(response).to redirect_to(workspace_epistularium_settings_path(workspace_slug: workspace.slug))
  end

  it "queues due account refreshes when Epistularium is opened after the 10 minute sync window" do
    user, workspace, account, message = build_stack(suffix: "due-sync")
    account.update!(
      last_synced_at: 11.minutes.ago,
      status: "connected",
      settings_json: account.settings_json.to_h.merge("last_fresh_sync_at" => 11.minutes.ago.iso8601)
    )
    clear_enqueued_jobs
    sign_in user

    expect do
      get workspace_epistularium_path(
        workspace_slug: workspace.slug,
        account_id: account.id,
        mailbox: "inbox",
        message_id: message.id
      )
    end.to have_enqueued_job(Epistularium::SyncConnectionJob).with(account.id, mode: "incremental")
  end

  it "does not run inline recovery sync work while Epistularium is rendering" do
    user = User.create!(email: "epistularium-request-recover-open@example.com", password: "password123")
    workspace = Workspace.create!(name: "Epistularium Recover Open", slug: "epistularium-recover-open")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "gmail",
      label: "Gmail inbox",
      access_token: "gmail-token"
    )
    account.mark_sync_enqueued!(at: 3.minutes.ago)
    sign_in user
    allow(Epistularium::SyncConnectionJob).to receive(:perform_now)

    get workspace_epistularium_path(
      workspace_slug: workspace.slug,
      account_id: account.id,
      mailbox: "inbox"
    )

    expect(response).to have_http_status(:ok)
    expect(Epistularium::SyncConnectionJob).not_to have_received(:perform_now)
  end

  it "recovers stale sync state when the user manually clicks Sync" do
    user, workspace, account, _message = build_stack(suffix: "manual-stale-sync")
    account.update!(
      last_synced_at: 2.hours.ago,
      status: "sync_error",
      settings_json: account.settings_json.to_h.merge("last_fresh_sync_at" => 2.hours.ago.iso8601)
    )
    account.mark_sync_started!(at: 30.minutes.ago)
    clear_enqueued_jobs
    sign_in user

    expect do
      post sync_epistularium_account_path(workspace_slug: workspace.slug, id: account.id)
    end.to have_enqueued_job(Epistularium::SyncConnectionJob).with(account.id, mode: "incremental")

    expect(response).to redirect_to(workspace_epistularium_settings_path(workspace_slug: workspace.slug))
    follow_redirect!
    expect(response.body).to include("Recent mail sync queued. Full backfill will continue in the background.")
    expect(account.reload.sync_started_at).to be_nil
  end

  it "shows when a fresh sync is already running instead of queueing duplicates" do
    user, workspace, account, _message = build_stack(suffix: "manual-active-sync")
    account.mark_sync_started!(at: 2.minutes.ago)
    clear_enqueued_jobs
    sign_in user

    expect do
      post sync_epistularium_account_path(workspace_slug: workspace.slug, id: account.id)
    end.not_to have_enqueued_job(Epistularium::SyncConnectionJob)

    expect(response).to redirect_to(workspace_epistularium_settings_path(workspace_slug: workspace.slug))
    follow_redirect!
    expect(response.body).to include("Sync is already in progress.")
  end

  it "runs an inline recovery sync when the queued mailbox has stalled" do
    user, workspace, account, _message = build_stack(suffix: "manual-recovery")
    account.update!(
      last_synced_at: 2.hours.ago,
      status: "connected",
      settings_json: account.settings_json.to_h.merge("last_fresh_sync_at" => 2.hours.ago.iso8601)
    )
    account.mark_sync_enqueued!(at: 3.minutes.ago)
    clear_enqueued_jobs
    sign_in user
    allow(Epistularium::SyncConnectionJob).to receive(:perform_now)

    post sync_epistularium_account_path(workspace_slug: workspace.slug, id: account.id)

    expect(Epistularium::SyncConnectionJob).to have_received(:perform_now).with(account.id, mode: "incremental")
    expect(response).to redirect_to(workspace_epistularium_settings_path(workspace_slug: workspace.slug))
    follow_redirect!
    expect(response.body).to include("Recent mail refreshed.")
  end

  it "honors the requested account and message when multiple Epistula are present" do
    user, workspace, account, _message = build_stack(suffix: "selection")
    other_account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Support inbox",
      provider_username: "support@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.example.com" }
    )
    selected_message = EpistulariumMessage.create!(
      workspace: workspace,
      epistularium_account: other_account,
      provider_message_id: "msg-selection-selected",
      subject: "Support launch note",
      from_name: "Priya",
      from_email: "priya@example.com",
      body_text: "Support queue follow-up body",
      snippet: "Support queue follow-up snippet"
    )
    EpistulariumMessage.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-selection-original",
      subject: "Original inbox note",
      from_name: "Alex",
      from_email: "alex@example.com",
      body_text: "Original inbox body"
    )

    sign_in user

    get workspace_epistularium_path(
      workspace_slug: workspace.slug,
      account_id: other_account.id,
      mailbox: "inbox",
      message_id: selected_message.id
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Support inbox · Inbox")
    expect(response.body).to include("Support queue follow-up body")
    expect(response.body).not_to include("Original inbox body")
  end

  it "runs an initial bootstrap sync inline when an IMAP Epistulum is created from settings" do
    user = User.create!(email: "epistularium-settings@example.com", password: "password123")
    workspace = Workspace.create!(name: "Epistularium Settings", slug: "epistularium-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    allow(Epistularium::ConnectionSyncService).to receive(:new)
    allow(Epistularium::SyncConnectionJob).to receive(:perform_now)

    sign_in user

    expect do
      post epistularium_accounts_path(workspace_slug: workspace.slug), params: {
        epistularium_account: {
          provider: "imap",
          label: "Support inbox",
          owner_scope: "user",
          imap_host: "imap.example.com",
          imap_port: 993,
          imap_ssl: "1",
          provider_username: "support@example.com",
          provider_password: "secret",
          sent_mailbox: "Sent"
        },
        sync_now: "1"
      }
    end.to change(EpistulariumAccount, :count).by(1)

    expect(response).to redirect_to(workspace_epistularium_settings_path(workspace_slug: workspace.slug))
    created_account = EpistulariumAccount.order(:created_at).last
    expect(Epistularium::SyncConnectionJob).to have_received(:perform_now).with(created_account.id, mode: "bootstrap")
    expect(Epistularium::ConnectionSyncService).not_to have_received(:new)
  end

  it "does not queue a sync when sync_now is unchecked during IMAP account creation" do
    user = User.create!(email: "epistularium-settings-no-sync@example.com", password: "password123")
    workspace = Workspace.create!(name: "Epistularium Settings No Sync", slug: "epistularium-settings-no-sync")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    allow(Epistularium::ConnectionSyncService).to receive(:new)

    sign_in user

    expect do
      post epistularium_accounts_path(workspace_slug: workspace.slug), params: {
        epistularium_account: {
          provider: "imap",
          label: "Archive inbox",
          owner_scope: "user",
          imap_host: "imap.example.com",
          imap_port: 993,
          imap_ssl: "1",
          provider_username: "archive@example.com",
          provider_password: "secret",
          sent_mailbox: "Sent"
        },
        sync_now: "0"
      }
    end.to change(EpistulariumAccount, :count).by(1)

    expect(response).to redirect_to(workspace_epistularium_settings_path(workspace_slug: workspace.slug))
    expect(enqueued_jobs.map { |job| job[:job] }).not_to include(Epistularium::SyncConnectionJob)
    expect(Epistularium::ConnectionSyncService).not_to have_received(:new)
  end

  it "creates a draft reply suggestion from a selected email" do
    user, workspace, account, message = build_stack(suffix: "suggest", openai_api_key: "sk-test")
    sign_in user

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      {
        text: {
          title: "Reply to Alex",
          payload: {
            to: [ "alex@example.com" ],
            cc: [],
            subject: "Re: Launch note suggest",
            body: "I will review it today."
          }
        }.to_json,
        usage: { prompt_tokens: 140, completion_tokens: 55, total_tokens: 195 }
      }
    )

    post suggest_workspace_epistularium_message_path(workspace_slug: workspace.slug, id: message.id), params: { suggestion_type: "reply" }

    agent_action = AgentAction.order(:created_at).last
    expect(response).to redirect_to(agent_action_path(workspace_slug: workspace.slug, id: agent_action.id))
    expect(agent_action.target_system).to eq("email")
    expect(agent_action.metadata_json["source_email_id"]).to eq(message.id)
    expect(agent_action.payload["to"]).to eq([ "alex@example.com" ])
  end
end
