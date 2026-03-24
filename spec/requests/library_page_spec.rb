require "rails_helper"

RSpec.describe "Library page", type: :request do
  it "defaults to all documents, supports workspace filtering, and limits recents to the past week" do
    user = User.create!(email: "library-page-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Library Main", slug: "library-main")
    other_workspace = Workspace.create!(name: "Library Other", slug: "library-other")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Membership.create!(workspace: other_workspace, user: user, role: :owner)

    recent_page = Page.create!(workspace: workspace, created_by: user, title: "Product brief")
    old_page = Page.create!(workspace: workspace, created_by: user, title: "Quarterly archive")
    meeting_page = Page.create!(workspace: workspace, created_by: user, title: "Weekly meeting notes", page_kind: "meeting_note")
    main_database = Database.create!(workspace: workspace, name: "Roadmap DB")
    other_page = Page.create!(workspace: other_workspace, created_by: user, title: "Other workspace page")
    old_page.update_columns(updated_at: 9.days.ago, created_at: 9.days.ago)

    Favorite.create!(user: user, workspace: workspace, favoritable: meeting_page)
    Favorite.create!(user: user, workspace: workspace, favoritable: main_database)

    sign_in user

    get workspace_library_path(workspace_slug: workspace.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<h1 class=\"notae-tool-page-title\">Library</h1>")
    expect(response.body).to include("notae-topbar-page-icon-glyph")
    expect(response.body).to include("Workspaces")
    expect(response.body).to include("notae-sidebar-list is-indented")
    expect(main_content_classes(response.body)).to include("notae-content-wide")
    expect(library_tab_labels(response.body).first).to eq("All documents")
    expect(active_tab_label(response.body)).to eq("All documents")
    expect(library_headers(response.body)).to include("Workspace")
    expect(workspace_filter_options(response.body)).to include([ "All workspaces", "all" ], [ "Library Main", "library-main" ], [ "Library Other", "library-other" ])
    expect(workspace_filter_options(response.body)).not_to include([ "Current workspace", "current" ])
    expect(workspace_filter_onchange(response.body)).to eq("this.form.requestSubmit()")
    expect(source_filter_options(response.body)).to include([ "All sources", "all" ], [ "Notarum", "page" ], [ "Meetings", "meeting" ], [ "Grids", "database" ])
    expect(source_filter_options(response.body)).not_to include([ "Workspaces", "workspace" ])
    expect(library_row_classes(response.body).all? { |klass| klass.include?("notae-library-row") }).to be(true)
    expect(response.body).to include("Filters")
    expect(response.body).to include("Columns")

    default_titles = library_titles(response.body)
    expect(default_titles).to include("Product brief", "Quarterly archive", "Weekly meeting notes", "🗃️ Roadmap DB")
    expect(default_titles).to include("Other workspace page")
    expect(default_titles).not_to include(workspace.name)
    expect(library_row_text(response.body, "Other workspace page")).to include("Library Other")

    get workspace_library_path(workspace_slug: workspace.slug), params: { workspace_filter: workspace.slug }
    single_workspace_titles = library_titles(response.body)
    expect(single_workspace_titles).to include("Product brief", "Quarterly archive", "Weekly meeting notes", "🗃️ Roadmap DB")
    expect(single_workspace_titles).not_to include("Other workspace page")

    get workspace_library_path(workspace_slug: workspace.slug), params: { tab: "recents", workspace_filter: "all" }
    recents_titles = library_titles(response.body)
    expect(recents_titles).to include("Product brief", "Weekly meeting notes", "🗃️ Roadmap DB", "Other workspace page")
    expect(recents_titles).not_to include("Quarterly archive")

    get workspace_library_path(workspace_slug: workspace.slug), params: { workspace_filter: "all", source: "meeting" }
    source_titles = library_titles(response.body)
    expect(source_titles).to include("Weekly meeting notes")
    expect(source_titles).not_to include("Product brief")

    get workspace_library_path(workspace_slug: workspace.slug), params: { tab: "favorites" }
    favorite_titles = library_titles(response.body)
    expect(favorite_titles).to include("Weekly meeting notes", "🗃️ Roadmap DB")
    expect(favorite_titles).not_to include("Product brief")

    get workspace_library_path(workspace_slug: workspace.slug), params: { workspace_filter: "all", q: "Other workspace page" }
    expect(library_titles(response.body)).to include("Other workspace page")

    expect(recent_page).to be_present
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
    expect(headers).to include("Nota name", "Created by")
    expect(headers).not_to include("Workspace")
    expect(headers).not_to include("Source")
    expect(headers).not_to include("Last edited time")
  end

  it "paginates all documents with 50 records per page" do
    user = User.create!(email: "library-pagination-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Library pagination", slug: "library-pagination")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    52.times do |index|
      Page.create!(workspace: workspace, created_by: user, title: "Page #{index + 1}")
    end

    sign_in user
    get workspace_library_path(workspace_slug: workspace.slug)

    expect(library_row_count(response.body)).to eq(50)
    expect(pagination_meta(response.body)).to eq("Showing 1-50 of 52")
    expect(pagination_page(response.body)).to eq("Page 1 of 2")

    get workspace_library_path(workspace_slug: workspace.slug), params: { page: 2 }
    expect(library_row_count(response.body)).to eq(2)
    expect(pagination_meta(response.body)).to eq("Showing 51-52 of 52")
    expect(pagination_page(response.body)).to eq("Page 2 of 2")
  end

  def library_titles(html_body)
    Nokogiri::HTML(html_body).css(".notae-library-row-title").map { |node| node.text.strip }
  end

  def library_headers(html_body)
    Nokogiri::HTML(html_body).css(".notae-library-table thead th").map { |node| node.text.strip }
  end

  def workspace_filter_options(html_body)
    Nokogiri::HTML(html_body)
      .css(".notae-library-workspace-filter select[name='workspace_filter'] option")
      .map { |node| [ node.text.strip, node["value"] ] }
  end

  def source_filter_options(html_body)
    Nokogiri::HTML(html_body)
      .css(".notae-library-popover-panel select[name='source'] option")
      .map { |node| [ node.text.strip, node["value"] ] }
  end

  def workspace_filter_onchange(html_body)
    Nokogiri::HTML(html_body).at_css(".notae-library-workspace-filter select[name='workspace_filter']")&.[]("onchange")
  end

  def library_tab_labels(html_body)
    Nokogiri::HTML(html_body).css(".notae-library-tab").map { |node| node.text.strip }
  end

  def active_tab_label(html_body)
    Nokogiri::HTML(html_body).at_css(".notae-library-tab.active")&.text&.strip
  end

  def library_row_classes(html_body)
    Nokogiri::HTML(html_body).css(".notae-library-table tbody tr").map { |node| node["class"].to_s }
  end

  def library_row_count(html_body)
    Nokogiri::HTML(html_body).css(".notae-library-table tbody tr.notae-library-row").size
  end

  def library_row_text(html_body, title)
    row = Nokogiri::HTML(html_body).css(".notae-library-table tbody tr").find do |node|
      node.text.include?(title)
    end
    row&.text.to_s
  end

  def pagination_meta(html_body)
    Nokogiri::HTML(html_body).at_css(".notae-library-pagination-meta")&.text&.strip
  end

  def pagination_page(html_body)
    Nokogiri::HTML(html_body).at_css(".notae-library-pagination-page")&.text&.strip
  end

  def main_content_classes(html_body)
    Nokogiri::HTML(html_body).at_css("main")["class"].to_s.split
  end
end
