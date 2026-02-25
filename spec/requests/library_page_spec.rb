require "rails_helper"

RSpec.describe "Library page", type: :request do
  it "supports workspace/source/favorites/search filters and keeps sidebar workspace section" do
    user = User.create!(email: "library-page-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Library Main", slug: "library-main")
    other_workspace = Workspace.create!(name: "Library Other", slug: "library-other")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Membership.create!(workspace: other_workspace, user: user, role: :owner)

    doc_page = Page.create!(workspace: workspace, created_by: user, title: "Product brief")
    meeting_page = Page.create!(workspace: workspace, created_by: user, title: "Weekly meeting notes")
    main_database = Database.create!(workspace: workspace, name: "Roadmap DB")
    other_page = Page.create!(workspace: other_workspace, created_by: user, title: "Other workspace page")

    Favorite.create!(user: user, workspace: workspace, favoritable: meeting_page)
    Favorite.create!(user: user, workspace: workspace, favoritable: main_database)

    sign_in user

    get workspace_library_path(workspace_slug: workspace.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Workspaces")
    expect(response.body).to include("notae-sidebar-list is-indented")

    default_titles = library_titles(response.body)
    expect(default_titles).to include("Product brief", "Weekly meeting notes", "Roadmap DB", workspace.name)
    expect(default_titles).not_to include("Other workspace page")

    get workspace_library_path(workspace_slug: workspace.slug), params: { workspace_filter: "all", source: "meeting" }
    source_titles = library_titles(response.body)
    expect(source_titles).to include("Weekly meeting notes")
    expect(source_titles).not_to include("Product brief")

    get workspace_library_path(workspace_slug: workspace.slug), params: { tab: "favorites" }
    favorite_titles = library_titles(response.body)
    expect(favorite_titles).to include("Weekly meeting notes", "Roadmap DB")
    expect(favorite_titles).not_to include("Product brief")

    get workspace_library_path(workspace_slug: workspace.slug), params: { workspace_filter: "all", q: "Other workspace page" }
    expect(library_titles(response.body)).to include("Other workspace page")

    expect(doc_page).to be_present
  end

  it "allows property visibility selection for the library table" do
    user = User.create!(email: "library-column-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Library columns", slug: "library-columns")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Page.create!(workspace: workspace, created_by: user, title: "Column test page")

    sign_in user
    get workspace_library_path(workspace_slug: workspace.slug),
        params: { visible_columns: %w[page_name created_by] }

    headers = library_headers(response.body)
    expect(headers).to include("Page name", "Created by")
    expect(headers).not_to include("Source")
    expect(headers).not_to include("Last edited time")
  end

  def library_titles(html_body)
    Nokogiri::HTML(html_body).css(".notae-library-row-title").map { |node| node.text.strip }
  end

  def library_headers(html_body)
    Nokogiri::HTML(html_body).css(".notae-library-table thead th").map { |node| node.text.strip }
  end
end
