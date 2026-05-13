require "rails_helper"
require "zip"

RSpec.describe "General settings", type: :request do
  include ActiveJob::TestHelper

  it "renders workspace controls in general settings" do
    user = User.create!(email: "general-settings-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Zulu settings", slug: "general-settings")
    other_workspace = Workspace.create!(name: "Alpha settings", slug: "general-settings-alt")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Membership.create!(workspace: other_workspace, user: user, role: :owner)
    sign_in user

    get workspace_general_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Workspace settings")
    expect(response.body).to include("Workspace name")
    expect(response.body).to include("Save and display page view analytics")
    expect(response.body).to include("Desktop notification bar")
    expect(response.body).to include("Delete workspace")
    expect(response.body).to include("Workspace ID")
    expect(response.body).to include(workspace.id)
    expect(response.body).to include("Workspace colour")
    expect(response.body).to include("Backup my data")
    expect(response.body).to include("notae-workspace-color-option")
    expect(response.body).to include("Final confirmation")
    expect(response.body).to include("Favicon Lab")
    expect(response.body).to include('id="settings_flash_messages"')
    expect(response.body).to include("notae-settings-inline-flash-host")
    expect(response.body).to include("Internal")
    expect(response.body).not_to include(workspace_favicon_settings_path(workspace_slug: workspace.slug, settings_workspace_slug: workspace.slug))
    expect(response.body).not_to include('id="notae_flash_messages"')

    document = Nokogiri::HTML(response.body)
    workspace_picker = document.at_css(".notae-settings-workspace-picker select[name='workspace_nav_picker']")
    expect(workspace_picker).to be_present
    expect(workspace_picker["onchange"]).to be_nil
    expect(workspace_picker["data-action"]).to eq("change->auto-submit#navigate")
    picker_options = workspace_picker.css("option").map { |option| [ option.text.strip, option["value"] ] }
    expect(picker_options.first.first).to eq("Alpha settings")
    expect(picker_options.second.first).to eq("Zulu settings")
    expect(picker_options).to include(
      [ workspace.name, workspace_general_settings_path(workspace_slug: workspace.slug, settings_workspace_slug: workspace.slug) ],
      [ other_workspace.name, workspace_general_settings_path(workspace_slug: other_workspace.slug, settings_workspace_slug: other_workspace.slug) ]
    )
    selected_option = workspace_picker.css("option").find { |option| option["selected"].present? }
    expect(selected_option&.[]("value")).to eq(workspace_general_settings_path(workspace_slug: workspace.slug, settings_workspace_slug: workspace.slug))
  end

  it "hides the favicon lab navigation item in production" do
    user = User.create!(email: "general-settings-production@example.com", password: "password123")
    workspace = Workspace.create!(name: "Production settings", slug: "production-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

    get workspace_general_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Favicon Lab")
    expect(response.body).not_to include("Internal")
  end

  it "renders workspace name and colour for the selected workspace context" do
    user = User.create!(email: "general-settings-context@example.com", password: "password123")
    primary_workspace = Workspace.create!(name: "Primary Workspace", slug: "general-settings-context-primary", workspace_color: Workspace::WORKSPACE_COLOR_OPTIONS.first.fetch(:value))
    selected_workspace = Workspace.create!(name: "Selected Workspace", slug: "general-settings-context-selected", workspace_color: Workspace::WORKSPACE_COLOR_OPTIONS.second.fetch(:value))
    Membership.create!(workspace: primary_workspace, user: user, role: :owner)
    Membership.create!(workspace: selected_workspace, user: user, role: :owner)
    sign_in user

    get workspace_general_settings_path(workspace_slug: selected_workspace.slug, settings_workspace_slug: selected_workspace.slug)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    name_input = document.at_css(".notae-general-name-input")
    expect(name_input&.[]("value")).to eq("Selected Workspace")
    active_colour = document.at_css(".notae-general-color-form .notae-workspace-color-option.is-active input[name='workspace[workspace_color]']")
    expect(active_colour&.[]("value")).to eq(Workspace::WORKSPACE_COLOR_OPTIONS.second.fetch(:value))
  end

  it "renders the workspace colour heading above the palette without the old helper copy" do
    user = User.create!(email: "general-settings-colour-layout@example.com", password: "password123")
    workspace = Workspace.create!(name: "Colour layout", slug: "general-settings-colour-layout")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_general_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    colour_row = document.at_css(".notae-general-color-form")&.ancestors(".notae-pref-row")&.first
    colour_heading = document.at_css(".notae-general-color-form .notae-pref-label")

    expect(colour_row&.[]("class")).to include("notae-pref-row--stacked")
    expect(colour_heading&.text&.strip).to eq("Workspace colour")
    expect(response.body).not_to include("Shown in the sidebar next to the workspace name and as the page-top border.")
  end

  it "renders the selected settings workspace even if the route workspace slug is stale" do
    user = User.create!(email: "general-settings-stale-route@example.com", password: "password123")
    first_workspace = Workspace.create!(name: "First Workspace", slug: "general-settings-first", workspace_color: Workspace::WORKSPACE_COLOR_OPTIONS.first.fetch(:value))
    selected_workspace = Workspace.create!(name: "Second Workspace", slug: "general-settings-second", workspace_color: Workspace::WORKSPACE_COLOR_OPTIONS.third.fetch(:value))
    Membership.create!(workspace: first_workspace, user: user, role: :owner)
    Membership.create!(workspace: selected_workspace, user: user, role: :owner)
    sign_in user

    get workspace_general_settings_path(workspace_slug: first_workspace.slug, settings_workspace_slug: selected_workspace.slug)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    name_input = document.at_css(".notae-general-name-input")
    active_colour = document.at_css(".notae-general-color-form .notae-workspace-color-option.is-active input[name='workspace[workspace_color]']")

    expect(name_input&.[]("value")).to eq("Second Workspace")
    expect(active_colour&.[]("value")).to eq(Workspace::WORKSPACE_COLOR_OPTIONS.third.fetch(:value))
  end

  it "updates workspace name, colour, analytics settings, and notification bar mode" do
    user = User.create!(email: "general-settings-update@example.com", password: "password123")
    workspace = Workspace.create!(name: "Original workspace", slug: "general-settings-update")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_general_settings_path(workspace_slug: workspace.slug),
          params: {
            workspace: {
              name: "Disco HQ",
              workspace_color: Workspace::WORKSPACE_COLOR_OPTIONS.last.fetch(:value),
              analytics_enabled: "0",
              shell_status_bar_mode: "alerts_only"
            }
          }

    expect(response).to redirect_to(workspace_general_settings_path(workspace_slug: workspace.slug, settings_workspace_slug: workspace.slug))

    workspace.reload
    expect(workspace.name).to eq("Disco HQ")
    expect(workspace.workspace_color).to eq(Workspace::WORKSPACE_COLOR_OPTIONS.last.fetch(:value))
    expect(workspace.analytics_enabled).to be(false)
    expect(workspace.shell_status_bar_mode).to eq("alerts_only")
  end

  it "returns a local turbo stream flash instead of redirecting for auto-save updates" do
    user = User.create!(email: "general-settings-turbo@example.com", password: "password123")
    workspace = Workspace.create!(name: "General turbo", slug: "general-settings-turbo")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_general_settings_path(workspace_slug: workspace.slug),
          params: { workspace: { name: "General turbo renamed" } },
          headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('turbo-stream action="replace" target="settings_flash_messages"')
    expect(response.body).to include("General settings updated.")
  end

  it "requires exact name to archive workspace" do
    user = User.create!(email: "general-settings-delete-name-check@example.com", password: "password123")
    workspace = Workspace.create!(name: "Delete check", slug: "general-settings-delete-name-check")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    delete workspace_general_settings_path(workspace_slug: workspace.slug),
           params: { workspace: { confirm_name: "wrong name" } }

    expect(response).to redirect_to(workspace_general_settings_path(workspace_slug: workspace.slug, settings_workspace_slug: workspace.slug))
    expect(workspace.reload.archived_at).to be_nil
  end

  it "allows owners to archive the workspace from danger zone" do
    user = User.create!(email: "general-settings-delete-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Delete me", slug: "general-settings-delete-owner")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    delete workspace_general_settings_path(workspace_slug: workspace.slug),
           params: { workspace: { confirm_name: workspace.name } }

    expect(response).to redirect_to(root_path)
    expect(workspace.reload.archived_at).to be_present
  end

  it "queues a workspace backup export and downloads workspace data as a zip" do
    user = User.create!(email: "general-settings-backup@example.com", password: "password123")
    workspace = Workspace.create!(name: "Backup workspace", slug: "general-settings-backup")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    page = Page.create!(workspace:, created_by: user, title: "Backup Page")
    Block.create!(
      workspace:,
      page:,
      created_by: user,
      block_type: "text",
      content_json: {
        "type" => "doc",
        "content" => [
          { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Important note" } ] }
        ]
      }
    )

    database = Database.create!(workspace:, created_by: user, name: "Project tracker")
    property = DbProperty.create!(workspace:, database:, name: "Status")
    active_row = DbRow.create!(workspace:, database:, title: "Active row")
    archived_row = DbRow.create!(workspace:, database:, title: "Archived row", archived_at: 1.day.ago)
    DbCell.create!(workspace:, db_row: active_row, db_property: property, value_text: "Open")
    DbCell.create!(workspace:, db_row: archived_row, db_property: property, value_text: "Done")

    calendar = KalendariumCalendar.create!(
      workspace:,
      created_by: user,
      name: "Family",
      color_hex: "#3B82F6",
      time_zone: "Australia/Melbourne",
      source_kind: "local"
    )
    KalendariumEvent.create!(
      workspace:,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Movie night",
      starts_at_utc: Time.utc(2026, 4, 20, 2, 30),
      ends_at_utc: Time.utc(2026, 4, 20, 4, 30),
      metadata_json: { "meeting_join_url" => "https://example.com/join/movie-night" }
    )

    account = EpistulariumAccount.create!(
      workspace:,
      owner: workspace,
      created_by: user,
      provider: "imap",
      label: "Shared inbox",
      provider_username: "backup@example.com",
      provider_password: "password123",
      settings_json: { "imap_host" => "imap.example.com", "imap_port" => 993 }
    )
    EpistulariumMessage.create!(
      workspace:,
      epistularium_account: account,
      provider_message_id: "message-1",
      mailbox: "inbox",
      subject: "Quarterly update",
      from_name: "Sender",
      from_email: "sender@example.com",
      to_recipients_json: [ { "email" => "backup@example.com", "name" => "Backup" } ],
      received_at: Time.utc(2026, 4, 19, 23, 15),
      unread: true,
      snippet: "Important mail",
      body_text: "Important mail body"
    )

    expect do
      post workspace_backup_exports_path(workspace_slug: workspace.slug),
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    end.to have_enqueued_job(WorkspaceExports::BuildZipJob)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('turbo-stream action="replace" target="workspace_backup_exports_panel"')

    workspace_export = WorkspaceExport.order(created_at: :desc).first
    perform_enqueued_jobs(only: WorkspaceExports::BuildZipJob)
    workspace_export.reload

    expect(workspace_export).to be_downloadable

    get workspace_backup_download_path(workspace_slug: workspace.slug, token: workspace_export.token)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/zip")

    entries = {}
    Zip::File.open_buffer(StringIO.new(response.body)) do |zip_file|
      zip_file.each do |entry|
        entries[entry.name] = entry.get_input_stream.read
      end
    end

    page_entry = entries.keys.find { |name| name.start_with?("pages/active/backup-page-") && name.end_with?(".md") }
    database_entry = entries.keys.find { |name| name.start_with?("databases/active/project-tracker-") && name.end_with?(".csv") }

    expect(entries["workspace.md"]).to include("Workspace backup")
    expect(entries["workspace.md"]).to include(workspace.slug)
    expect(page_entry).to be_present
    expect(entries.fetch(page_entry)).to include("# Backup Page")
    expect(entries.fetch(page_entry)).to include("Important note")
    expect(database_entry).to be_present
    expect(entries.fetch(database_entry)).to include("Archived at")
    expect(entries.fetch(database_entry)).to include("Active row")
    expect(entries.fetch(database_entry)).to include("Archived row")
    expect(entries.fetch("kalendarium/events.csv")).to include("Movie night")
    expect(entries.fetch("epistularium/messages.csv")).to include("Quarterly update")
    expect(entries.fetch("epistularium/messages.csv")).to include("Important mail body")
  end

  it "prevents non-admin members from creating or downloading workspace exports" do
    owner = User.create!(email: "general-settings-backup-owner@example.com", password: "password123")
    member = User.create!(email: "general-settings-backup-member@example.com", password: "password123")
    workspace = Workspace.create!(name: "Backup controls", slug: "general-settings-backup-controls")
    Membership.create!(workspace:, user: owner, role: :owner)
    Membership.create!(workspace:, user: member, role: :member)

    workspace_export = WorkspaceExport.create!(workspace:, requested_by: owner)

    sign_in member

    post workspace_backup_exports_path(workspace_slug: workspace.slug)
    expect(response).to have_http_status(:forbidden)

    get workspace_backup_download_path(workspace_slug: workspace.slug, token: workspace_export.token)
    expect(response).to have_http_status(:not_found)
  end
end
