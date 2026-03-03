require "rails_helper"

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
    expect(response.body).to include("Start Online Capture")
    expect(response.body).to include("In-Person Capture")
    expect(response.body).to include("Recent Sessions")
    expect(response.body).to include("Action Proposals")
    expect(response.body).to include("notae-sidebar-link-label\">Meetings")
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

  it "creates an online bot session and queues bot startup" do
    user, workspace, event = build_stack(suffix: "online-create")
    sign_in user

    expect do
      post meeting_sessions_path(workspace_slug: workspace.slug), params: {
        meeting_session: {
          title: "Ops standup",
          capture_mode: "online_bot",
          provider: "google_meet",
          kalendarium_event_id: event.id,
          join_url: "https://meet.google.com/abc-defg-hij",
          consent_warning_acknowledged: "1"
        }
      }
    end.to change(MeetingSession, :count).by(1)
       .and change(MeetingBotRun, :count).by(1)

    expect(response).to redirect_to(workspace_meetings_path(workspace_slug: workspace.slug))
    session = MeetingSession.order(:created_at).last
    expect(session.status).to eq("joining")
    expect(enqueued_jobs.map { |job| job[:job] }).to include(Meetings::StartBotRunJob)
  end
end
