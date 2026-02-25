require "rails_helper"

RSpec.describe "Workspace home", type: :request do
  it "shows only the 3 most recently updated pages and databases" do
    user = User.create!(email: "home-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Home test", slug: "home-test")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    old_page = Page.create!(workspace: workspace, created_by: user, title: "Page 1 old")
    mid_page = Page.create!(workspace: workspace, created_by: user, title: "Page 2 mid")
    newer_page = Page.create!(workspace: workspace, created_by: user, title: "Page 3 newer")
    latest_page = Page.create!(workspace: workspace, created_by: user, title: "Page 4 latest")

    old_page.touch(time: 4.days.ago)
    mid_page.touch(time: 3.days.ago)
    newer_page.touch(time: 2.days.ago)
    latest_page.touch(time: 1.day.ago)

    old_db = Database.create!(workspace: workspace, name: "DB 1 old")
    mid_db = Database.create!(workspace: workspace, name: "DB 2 mid")
    newer_db = Database.create!(workspace: workspace, name: "DB 3 newer")
    latest_db = Database.create!(workspace: workspace, name: "DB 4 latest")

    old_db.touch(time: 4.days.ago)
    mid_db.touch(time: 3.days.ago)
    newer_db.touch(time: 2.days.ago)
    latest_db.touch(time: 1.day.ago)

    sign_in user
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)

    page_titles = html.css(".notae-workspace-page-grid .notae-workspace-page-card-text strong").map(&:text)
    expect(page_titles).to eq([ "Page 4 latest", "Page 3 newer", "Page 2 mid" ])

    database_titles = html.css(".notae-auth-card .notae-workspace-home-link-grid .notae-home-workspace-item strong").map(&:text)
    expect(database_titles).to include("DB 4 latest", "DB 3 newer", "DB 2 mid")
    expect(database_titles).not_to include("DB 1 old")
    expect(database_titles.count).to eq(3)
  end

  it "renders the workspace library page for members" do
    user = User.create!(email: "library-member@example.com", password: "password123")
    workspace = Workspace.create!(name: "Library test", slug: "library-test")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    sign_in user
    get workspace_library_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Library")
  end
end
