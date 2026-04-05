require "rails_helper"

RSpec.describe "Workspace sidebar sections", type: :request do
  it "renders the fast shell with a lazy sidebar frame and loads the recent section bodies separately" do
    user = User.create!(email: "sidebar-sections-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Sidebar sections workspace", slug: "sidebar-sections-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Alpha note")
    database = Database.create!(workspace: workspace, name: "Projects", icon: "🧠")
    Favorite.create!(user: user, workspace: workspace, favoritable: page)
    Favorite.create!(user: user, workspace: workspace, favoritable: database)

    sign_in user
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)

    shell_document = Nokogiri::HTML(response.body)
    sidebar_frame = shell_document.at_css("turbo-frame#notae_sidebar_sections")
    expect(sidebar_frame).to be_present
    expect(sidebar_frame["src"]).to eq(workspace_sidebar_sections_path(workspace_slug: workspace.slug))
    expect(sidebar_frame.text).to include("Loading Notarum")
    expect(sidebar_frame.text).not_to include("Alpha note")
    expect(sidebar_frame.text).not_to include("Projects")

    get workspace_sidebar_sections_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Notae-Perf-Action"]).to eq("WorkspaceSidebarSectionsController#show")

    sections_document = Nokogiri::HTML(response.body)
    notes_section = sections_document.css(".notae-sidebar-section").find { |node| node.at_css(".notae-sidebar-label")&.text.to_s.strip == "Notarum" }
    grids_section = sections_document.css(".notae-sidebar-section").find { |node| node.at_css(".notae-sidebar-label")&.text.to_s.strip == "Grids" }
    favorites_section = sections_document.css(".notae-sidebar-section").find { |node| node.at_css(".notae-sidebar-label")&.text.to_s.strip == "Favorites" }
    workspace_section = sections_document.css(".notae-sidebar-section").find { |node| node.at_css(".notae-sidebar-label")&.text.to_s.strip == "Workspaces" }

    expect(workspace_section.css("a[data-turbo-frame='_top']")).not_to be_empty
    expect(notes_section.text).to include("Alpha note")
    expect(grids_section.text).to include("Projects")
    expect(grids_section.at_css(".notae-icon-renderer-glyph")&.text&.strip).to eq("🧠")
    expect(favorites_section.text).to include("Alpha note")
    expect(notes_section.css("form[data-turbo-frame='_top']")).not_to be_empty
    expect(grids_section.css("form[data-turbo-frame='_top']")).not_to be_empty
    expect(notes_section.css("a[data-turbo-frame='_top']")).not_to be_empty
    expect(grids_section.css("a[data-turbo-frame='_top']")).not_to be_empty
    expect(favorites_section.css("a[data-turbo-frame='_top']")).not_to be_empty
    favorite_links = favorites_section.css("a[href]").map { |node| node["href"] }
    expect(favorite_links).to include(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(favorite_links).to include(database_path(workspace_slug: workspace.slug, id: database.id))
  end
end
