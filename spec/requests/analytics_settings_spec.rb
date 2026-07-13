require "rails_helper"
require "pdf/reader"

RSpec.describe "Analytics settings", type: :request do
  let(:user) { User.create!(email: "personal-analytics@example.com", password: "password123", time_zone: "Australia/Melbourne") }
  let(:workspace) { Workspace.create!(name: "Personal analytics", slug: "personal-analytics") }
  let(:other_workspace) { Workspace.create!(name: "Second workspace", slug: "second-analytics") }

  before do
    Membership.create!(workspace:, user:, role: :owner)
    Membership.create!(workspace: other_workspace, user:, role: :member)
    AnalyticsActivityBucket.create!(
      user:,
      workspace:,
      surface: "nota",
      bucket_started_at: Time.current.beginning_of_minute,
      duration_seconds: 30
    )
    AiConversation.create!(
      workspace:,
      user:,
      scope: "workspace",
      prompt: "Private prompt text",
      answer: "Private answer text",
      model: "gpt-4.1-mini"
    )
    sign_in user
  end

  it "renders a personal workspace dashboard with filters and accessible data" do
    get workspace_analytics_settings_path(workspace_slug: workspace.slug, period: "7d")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Personal analytics")
    expect(response.body).to include("Active time over the period")
    expect(response.body).to include("Where your time went")
    expect(response.body).to include("Calls and outcomes")
    expect(response.body).to include("View activity data")
    expect(response.body).to include("Export PDF")
    expect(response.body).to include("Embed in a Nota")
    expect(response.body).to include("notae-content-analytics")
    expect(response.body).not_to include("Private prompt text")
    expect(response.body).not_to include("Private answer text")

    document = Nokogiri::HTML(response.body)
    expect(document.at_css("select[name='scope'] option[value='all']")&.text).to eq("All my workspaces")
    expect(document.css(".notae-analytics-trend li").length).to eq(7)
    expect(document.at_css(".notae-analytics-data-table table")).to be_present
  end

  it "combines only workspaces the user can currently access" do
    outsider = User.create!(email: "analytics-outsider@example.com", password: "password123")
    hidden_workspace = Workspace.create!(name: "Hidden workspace", slug: "hidden-analytics")
    Membership.create!(workspace: hidden_workspace, user: outsider, role: :owner)
    AnalyticsActivityBucket.create!(
      user: outsider,
      workspace: hidden_workspace,
      surface: "ai",
      bucket_started_at: 2.minutes.ago.beginning_of_minute,
      duration_seconds: 30
    )

    get workspace_analytics_settings_path(workspace_slug: workspace.slug, scope: "all", period: "30d")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("All my workspaces")
    expect(response.body).to include(workspace.name)
    expect(response.body).to include(other_workspace.name)
    expect(response.body).not_to include(hidden_workspace.name)
    expect(response.body).to include("Creates a private snapshot in #{workspace.name}.")
  end

  it "excludes subscription-inaccessible workspaces from app-wide views and exports" do
    restricted_workspace = Workspace.create!(name: "Restricted analytics", slug: "restricted-analytics")
    Membership.create!(workspace: restricted_workspace, user: user, role: :owner)
    restricted_workspace.create_workspace_subscription!(
      plan_key: WorkspaceSubscription::PLAN_STARTER,
      status: WorkspaceSubscription::STATUS_CANCELED,
      billing_provider: WorkspaceSubscription::PROVIDER_STRIPE
    )
    AnalyticsActivityBucket.create!(
      user: user,
      workspace: restricted_workspace,
      surface: "nota",
      bucket_started_at: Time.current.beginning_of_minute,
      duration_seconds: 30
    )

    get workspace_analytics_settings_path(workspace_slug: workspace.slug, scope: "all", period: "30d")

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    workspace_names = document.css(".notae-analytics-workspace-name strong").map { |node| node.text.strip }
    expect(workspace_names).to include(workspace.name, other_workspace.name)
    expect(workspace_names).not_to include(restricted_workspace.name)

    get workspace_analytics_export_path(workspace_slug: workspace.slug, scope: "all", period: "30d", format: :pdf)

    expect(response).to have_http_status(:ok)
    pdf_text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
    expect(pdf_text).to include(workspace.name, other_workspace.name)
    expect(pdf_text).not_to include(restricted_workspace.name)
  end

  it "exports the selected snapshot as a readable two-page PDF" do
    get workspace_analytics_export_path(workspace_slug: workspace.slug, period: "7d", format: :pdf)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.headers["Content-Disposition"]).to include("notae-analytics-personal-analytics")

    reader = PDF::Reader.new(StringIO.new(response.body))
    text = reader.pages.map(&:text).join("\n")
    expect(reader.page_count).to eq(2)
    expect(text).to include("My activity")
    expect(text).to include("Activity breakdown")
    expect(text).to include("Personal analytics")
    expect(text).to include("30 sec")
    expect(text).to include("Privacy: foreground analytics")
    expect(text).to include(Analytics::DateRange.new(params: { period: "7d" }).label)
    expect(text).not_to include("Private prompt text")
    expect(text).not_to include("Private answer text")
  end

  it "embeds a static workspace snapshot in a private Nota" do
    expect do
      post workspace_analytics_nota_path(workspace_slug: workspace.slug),
           params: { scope: "workspace", period: "7d" }
    end.to change(Page, :count).by(1)

    page = Page.order(:created_at).last
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page).to be_private_page
    expect(page.created_by).to eq(user)
    expect(page.title).to start_with("My activity -")
    expect(page.blocks.pluck(:search_text).join(" ")).to include("Overview")
  end

  it "rolls the private Nota back when snapshot import fails" do
    allow(Pages::ImportMarkdownService).to receive(:call).and_raise(
      Pages::ImportMarkdownService::Error,
      "Snapshot could not be imported."
    )

    expect do
      post workspace_analytics_nota_path(workspace_slug: workspace.slug),
           params: { scope: "workspace", period: "7d" }
    end.not_to change(Page, :count)

    expect(response).to redirect_to(
      workspace_analytics_settings_path(
        workspace_slug: workspace.slug,
        scope: "workspace",
        period: "7d",
        start_date: 6.days.ago.to_date.iso8601,
        end_date: Time.zone.today.iso8601
      )
    )
    expect(flash[:alert]).to eq("Snapshot could not be imported.")
  end

  it "embeds an app-wide snapshot as a private Nota in the current workspace" do
    expect do
      post workspace_analytics_nota_path(workspace_slug: workspace.slug),
           params: { scope: "all", period: "30d" }
    end.to change(Page, :count).by(1)

    page = Page.order(:created_at).last
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page).to be_private_page
    expect(page.title).to start_with("App-wide activity -")
    expect(page.blocks.pluck(:search_text).join(" ")).to include("Workspace breakdown")
  end

  it "does not allow a user to view another workspace's analytics" do
    inaccessible = Workspace.create!(name: "Inaccessible", slug: "inaccessible-analytics")

    get workspace_analytics_settings_path(workspace_slug: inaccessible.slug)

    expect(response).to have_http_status(:not_found)
  end
end
