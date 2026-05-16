require "rails_helper"
require "cgi"
require "uri"

RSpec.describe "Meetings", type: :request do
  include ActiveJob::TestHelper

  def build_stack(suffix:)
    user = User.create!(email: "meetings-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Meetings #{suffix}", slug: "meetings-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Weekly sync",
      starts_at_utc: 1.day.from_now.change(min: 0),
      ends_at_utc: 1.day.from_now.change(min: 30),
      metadata_json: { "meeting_join_url" => "https://meet.google.com/abc-defg-hij" }
    )

    [ user, workspace, event ]
  end

  before do
    clear_enqueued_jobs
  end

  it "renders the meetings page and entry in the sidebar navigation" do
    user, workspace, = build_stack(suffix: "show")
    sign_in user

    get workspace_meetings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Google Meet Transcript Extension")
    expect(response.body).to include("Live In-Person Recording")
    expect(response.body).to include("File Upload and Transcribe")
    expect(response.body).to include("Transcribed / Processed Sessions")
    expect(response.body).to include("Live / Active Sessions")
    expect(response.body).to include("Microphone recorder")
    expect(response.body).to include("Start mic recording")
    expect(response.body).to include("Stop recording")
    expect(response.body).to include("Submit for processing")
    expect(response.body).to include("Delete recording")
    expect(response.body).to include("Action Proposals")
    expect(response.body).to include("Generate extension token")
    expect(response.body).to include("Workspace slug")
    expect(response.body).to include("browser_extensions/notae_google_meet_transcript")
    expect(response.body).to include("notae-sidebar-link-label\">Meetings")
    expect(response.body).to include("<h1 class=\"notae-tool-page-title\">Meetings</h1>")
    expect(response.body).to include("notae-topbar-page-icon-glyph")
    expect(response.body).to include("If access is denied, use the lock/camera icon in the browser address bar to allow microphone, then retry.")
    expect(response.body).to include('form="in_person_meeting_form"')
    expect(response.body).to include('data-meeting-capture-target="sessionTitleInput"')
    expect(response.body).to include('input-&gt;meeting-capture#syncSessionTitle')
    expect(response.body).to include('data-meeting-sessions-poller-active-value="false"')
    expect(response.headers["Permissions-Policy"].to_s).to include("microphone=(self)")

    document = Nokogiri::HTML(response.body)
    start_button = document.at_css("[data-meeting-capture-target='startButton']")
    stop_button = document.at_css("[data-meeting-capture-target='stopButton']")

    expect(start_button["class"]).to include("notae-meetings-recorder-button-start")
    expect(stop_button["class"]).to include("notae-meetings-recorder-button-stop")
  end

  it "creates and revokes a Google Meet extension token for the current workspace" do
    user, workspace, = build_stack(suffix: "extension-token")
    sign_in user

    expect do
      post meeting_extension_token_path(workspace_slug: workspace.slug)
    end.to change(ApiToken, :count).by(1)

    created_token = ApiToken.order(:created_at).last
    redirect_uri = URI.parse(response.location)
    redirect_params = Rack::Utils.parse_query(redirect_uri.query.to_s)

    expect(redirect_uri.path).to eq(workspace_meetings_path(workspace_slug: workspace.slug))
    expect(redirect_params["extension_token_status"]).to eq("created")
    expect(redirect_params["extension_token_ref"]).to be_present
    expect(created_token.name).to eq("Google Meet transcript extension (#{workspace.slug})")
    expect(created_token.scopes).to contain_exactly(ApiToken::SCOPE_MEETINGS_READ, ApiToken::SCOPE_MEETINGS_WRITE)
    expect(flash[:meeting_extension_token]).to be_nil
    expect(flash[:meeting_extension_token_expires_at]).to be_nil
    expect(flash[:meeting_extension_token_id]).to be_nil

    follow_redirect!
    expect(response.body).to include("New extension token")
    expect(response.body).to include(created_token.token)

    delete meeting_extension_token_path(workspace_slug: workspace.slug)

    expect(response).to redirect_to(workspace_meetings_path(workspace_slug: workspace.slug, extension_token_status: "revoked"))
    expect(created_token.reload.revoked_at).to be_present
    expect(ApiTokenAuditEvent.where(workspace: workspace).pluck(:event_type)).to include("issued", "revoked")
  end

  it "renders the meetings page without a 500 when extension token storage is unavailable" do
    user, workspace, = build_stack(suffix: "extension-token-unavailable-show")
    sign_in user
    allow_any_instance_of(Meetings::ExtensionTokenService).to receive(:storage_available?).and_return(false)

    get workspace_meetings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Google Meet extension tokens are unavailable right now")
    expect(response.body).not_to include("Generate extension token")
  end

  it "redirects with an alert instead of raising when extension token creation is unavailable" do
    user, workspace, = build_stack(suffix: "extension-token-unavailable-create")
    sign_in user
    allow_any_instance_of(Meetings::ExtensionTokenService).to receive(:issue!).and_raise(Meetings::ExtensionTokenService::UnavailableError, "API token storage is unavailable.")

    expect do
      post meeting_extension_token_path(workspace_slug: workspace.slug)
    end.not_to change(ApiToken, :count)

    expect(response).to redirect_to(workspace_meetings_path(workspace_slug: workspace.slug, extension_token_status: "unavailable"))
    follow_redirect!
    expect(response.body).to include("Google Meet extension tokens are unavailable right now")
  end

  it "shows a recording-in-progress indicator when a live session exists" do
    user, workspace, event = build_stack(suffix: "active-indicator")
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      created_by: user,
      updated_by: user,
      title: "Live capture",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "recording",
      join_url: "https://meet.google.com/abc-defg-hij"
    )
    MeetingBotRun.create!(
      meeting_session: session,
      provider: "google_meet",
      status: "recording",
      worker_id: "worker-1",
      last_heartbeat_at: Time.current,
      metadata_json: {
        "join_stage" => "waiting_room",
        "page_body_excerpt" => "You asked to join. Someone in the call should let you in soon."
      }
    )
    sign_in user

    get workspace_meetings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Live / Active Sessions")
    expect(response.body).to include("Live capture")
    expect(response.body).to include("Bot run")
    expect(response.body).to include("Join stage")
    expect(response.body).to include("Waiting room")
    expect(response.body).not_to include("Someone in the call should let you in soon")
    expect(response.body).to include(">Stop<")
    expect(response.body).to include('data-meeting-sessions-poller-active-value="true"')
  end

  it "renders scheduled future recordings and upload-to-processed sessions in separate columns" do
    user, workspace, event = build_stack(suffix: "split-columns")
    MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      created_by: user,
      updated_by: user,
      title: "Future scheduled run",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "scheduled",
      join_url: "https://meet.google.com/abc-defg-hij"
    )
    MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      created_by: user,
      updated_by: user,
      title: "Uploaded session",
      capture_mode: "upload",
      provider: "local",
      status: "uploading"
    )
    sign_in user

    get workspace_meetings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    sections = document.css(".notae-meetings-layout--session-split > section")
    expect(sections.size).to eq(2)
    expect(sections[0].text).to include("Legacy scheduled browser captures")
    expect(sections[0].text).to include("Future scheduled run")
    expect(sections[1].text).to include("Transcribed / Processed Sessions")
    expect(sections[1].text).to include("Uploaded session")
  end

  it "updates linked note transcript blocks when speaker mapping is edited" do
    user, workspace, event = build_stack(suffix: "speaker-sync")
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      title: "Speaker sync call",
      capture_mode: "upload",
      provider: "local",
      status: "completed",
      summary_markdown: "### Summary\n- Speaker 1 confirmed the scope",
      action_items_json: [ { "title" => "Send recap", "owner" => "Speaker 1", "due_at" => nil, "confidence" => 0.8 } ],
      created_by: user,
      updated_by: user
    )
    session.meeting_utterances.create!(
      position: 0,
      started_ms: 0,
      ended_ms: 1200,
      speaker_key: "S1",
      speaker_name: "Speaker 1",
      text: "Hello team"
    )

    Meetings::NotaMaterializerService.new(session: session, actor: user).upsert_session_output!(
      transcript_text: session.transcript_text_from_utterances,
      summary_markdown: session.summary_markdown,
      action_items: session.action_items_json
    )

    sign_in user
    patch speakers_meeting_session_path(workspace_slug: workspace.slug, id: session.id), params: {
      meeting_session: {
        speaker_map: {
          "S1" => "Errol"
        }
      }
    }

    expect(response).to redirect_to(workspace_meetings_path(workspace_slug: workspace.slug))
    session.reload
    expect(session.transcript_text).to include("Errol")
    expect(session.page).to be_present
    page_text = session.page.blocks.active.order(:position).pluck(:search_text).join("\n")
    expect(page_text).to include("Transcript")
    expect(page_text).to include("Errol")
    expect(page_text).to include("Errol confirmed the scope")
    expect(page_text).not_to include("Speaker 1: Hello team")
    expect(page_text).not_to include("Speaker 1 confirmed the scope")
    expect(page_text).not_to include("owner: Speaker 1")
  end

  it "does not rewrite a linked private note when the speaker editor cannot see it" do
    owner, workspace, event = build_stack(suffix: "speaker-private-note-owner")
    member = User.create!(email: "meetings-speaker-private-note-member@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: member, role: :member)
    private_page = Page.create!(
      workspace: workspace,
      created_by: owner,
      title: "Private meeting notes",
      permission_mode: :private_page
    )
    private_block = private_page.blocks.create!(
      workspace: workspace,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        Meetings::NotaMaterializerService::SESSION_MARKER_KEY => "pending-session",
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [ { "type" => "text", "text" => "Private owner note" } ]
          }
        ]
      }
    )
    event.update!(linked_page: private_page, updated_by: owner)
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      title: "Private speaker sync call",
      capture_mode: "upload",
      provider: "local",
      status: "completed",
      summary_markdown: "### Summary\n- Speaker 1 confirmed the scope",
      action_items_json: [ { "title" => "Send recap", "owner" => "Speaker 1", "due_at" => nil, "confidence" => 0.8 } ],
      created_by: member,
      updated_by: member
    )
    private_block.update!(
      content_json: private_block.content_json.merge(
        Meetings::NotaMaterializerService::SESSION_MARKER_KEY => session.id.to_s
      )
    )
    session.meeting_utterances.create!(
      position: 0,
      started_ms: 0,
      ended_ms: 1200,
      speaker_key: "S1",
      speaker_name: "Speaker 1",
      text: "Hello team"
    )
    sign_in member

    patch speakers_meeting_session_path(workspace_slug: workspace.slug, id: session.id), params: {
      meeting_session: {
        speaker_map: {
          "S1" => "Errol"
        }
      }
    }

    expect(response).to redirect_to(workspace_meetings_path(workspace_slug: workspace.slug))
    expect(session.reload.transcript_text).to include("Errol")
    expect(private_page.blocks.active.count).to eq(1)
    expect(private_block.reload.search_text).to include("Private owner note")
    expect(private_page.blocks.active.pluck(:search_text).join("\n")).not_to include("Errol")
  end

  it "creates an upload session, links a meeting note, and queues processing" do
    user, workspace, event = build_stack(suffix: "upload-create")
    sign_in user

    Tempfile.create([ "meeting-capture", ".webm" ]) do |file|
      file.binmode
      file.write("not-real-audio-data")
      file.flush
      uploaded = Rack::Test::UploadedFile.new(file.path, "audio/webm")

      expect do
        post meeting_sessions_path(workspace_slug: workspace.slug), params: {
          meeting_session: {
            title: "Client discovery",
            capture_mode: "upload",
            provider: "local",
            kalendarium_event_id: event.id,
            capture_files: [ uploaded ],
            consent_warning_acknowledged: "1"
          }
        }
      end.to change(MeetingSession, :count).by(1)
    end

    expect(response).to redirect_to(workspace_meetings_path(workspace_slug: workspace.slug))
    session = MeetingSession.order(:created_at).last
    expect(session.page).to be_present
    expect(session.page.page_kind).to eq("meeting_note")
    expect(session.capture_files).to be_attached
    expect(session.status).to eq("uploading")
    expect(enqueued_jobs.map { |job| job[:job] }).to include(Meetings::ProcessSessionJob)
  end

  it "rejects creation of retired online bot sessions from the html workflow" do
    user, workspace, = build_stack(suffix: "online-create")
    sign_in user

    expect {
      post meeting_sessions_path(workspace_slug: workspace.slug), params: {
        meeting_session: {
          title: "Ops standup",
          capture_mode: "online_bot",
          provider: "google_meet",
          join_url: "https://meet.google.com/abc-defg-hij",
          consent_warning_acknowledged: "1"
        }
      }
    }.not_to change(MeetingSession, :count)

    expect(MeetingBotRun.count).to eq(0)

    expect(response).to redirect_to(workspace_meetings_path(workspace_slug: workspace.slug))
    expect(flash[:alert]).to include("retired")
  end

  it "hides manual restart controls for future scheduled sessions" do
    user, workspace, event = build_stack(suffix: "future-session-controls")
    MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      title: "Future scheduled session",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "scheduled",
      join_url: event.meeting_join_url,
      created_by: user,
      updated_by: user
    )
    sign_in user

    get workspace_meetings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    session_article = document.css(".notae-meetings-session-item").find { |node| node.text.include?("Future scheduled session") }
    expect(session_article).to be_present
    actions_text = session_article.css(".notae-meetings-session-actions").text
    expect(actions_text).not_to include("Start")
    expect(actions_text).not_to include("Restart")
  end

  it "serves json status updates for the meetings poller" do
    user, workspace, event = build_stack(suffix: "status-endpoint")
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      created_by: user,
      updated_by: user,
      title: "Polling session",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "joining",
      join_url: event.meeting_join_url
    )
    MeetingBotRun.create!(
      meeting_session: session,
      provider: "google_meet",
      status: "joining",
      last_heartbeat_at: Time.current
    )
    sign_in user

    get workspace_meetings_status_path(workspace_slug: workspace.slug), headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["X-Notae-Perf-Action"]).to eq("MeetingsController#status")
    expect(response.headers["X-Notae-Perf-Sql-Queries"]).to be_present
    payload = JSON.parse(response.body)
    expect(payload["active"]).to eq(true)
    expect(payload["html"]).to include("Live / Active Sessions")
    expect(payload["html"]).to include("Polling session")
    expect(payload["html"]).not_to include("Speaker mapping")
  end

  it "fails stale bot runs that are stuck waiting for heartbeat" do
    user, workspace, event = build_stack(suffix: "stale-heartbeat")
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      created_by: user,
      updated_by: user,
      title: "Stale heartbeat session",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "joining",
      join_url: event.meeting_join_url
    )
    run = MeetingBotRun.create!(
      meeting_session: session,
      provider: "google_meet",
      status: "joining",
      last_heartbeat_at: 10.minutes.ago
    )
    sign_in user

    get workspace_meetings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(run.reload.status).to eq("failed")
    expect(session.reload.status).to eq("failed")
    expect(session.error_message).to include("timed out")
  end

  it "rejects retired online bot session creation even when no join url is available" do
    user, workspace, event = build_stack(suffix: "online-missing-url")
    event.update!(metadata_json: {})
    sign_in user

    expect do
      post meeting_sessions_path(workspace_slug: workspace.slug), params: {
        meeting_session: {
          title: "Missing URL session",
          capture_mode: "online_bot",
          provider: "google_meet",
          join_url: "",
          consent_warning_acknowledged: "1"
        }
      }
    end.not_to change(MeetingSession, :count)

    expect(response).to redirect_to(workspace_meetings_path(workspace_slug: workspace.slug))
    expect(flash[:alert]).to include("retired")
  end
end
