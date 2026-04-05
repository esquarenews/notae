require "rails_helper"

RSpec.describe "Favorites", type: :request do
  it "allows members to favorite and unfavorite pages and databases" do
    user = User.create!(email: "favorites-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Favorites workspace", slug: "favorites-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Starred page")
    database = Database.create!(workspace: workspace, name: "Starred database")
    sign_in user

    post page_favorite_path(workspace_slug: workspace.slug, page_id: page.id)
    post database_favorite_path(workspace_slug: workspace.slug, database_id: database.id)

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(Favorite.exists?(user: user, workspace: workspace, favoritable: page)).to be(true)
    expect(Favorite.exists?(user: user, workspace: workspace, favoritable: database)).to be(true)

    get workspace_path(workspace.slug)
    expect(response).to have_http_status(:ok)
    get workspace_sidebar_sections_path(workspace_slug: workspace.slug)
    favorites_links = favorites_section_links(response.body)
    expect(favorites_links).to include(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(favorites_links).to include(database_path(workspace_slug: workspace.slug, id: database.id))

    delete page_favorite_path(workspace_slug: workspace.slug, page_id: page.id)
    delete database_favorite_path(workspace_slug: workspace.slug, database_id: database.id)

    expect(Favorite.exists?(user: user, workspace: workspace, favoritable: page)).to be(false)
    expect(Favorite.exists?(user: user, workspace: workspace, favoritable: database)).to be(false)
  end

  it "filters out favorites for private pages a member can no longer read" do
    owner = User.create!(email: "favorites-filter-owner@example.com", password: "password123")
    member = User.create!(email: "favorites-filter-member@example.com", password: "password123")
    workspace = Workspace.create!(name: "Favorites filter", slug: "favorites-filter")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)

    visible_page = Page.create!(workspace: workspace, created_by: owner, title: "Visible favorite")
    hidden_page = Page.create!(workspace: workspace, created_by: owner, title: "Hidden favorite", permission_mode: :private_page)

    Favorite.create!(user: member, workspace: workspace, favoritable: visible_page)
    Favorite.create!(user: member, workspace: workspace, favoritable: hidden_page)

    sign_in member
    get workspace_path(workspace.slug)
    get workspace_sidebar_sections_path(workspace_slug: workspace.slug)

    links = favorites_section_links(response.body)
    expect(links).to include(page_path(workspace_slug: workspace.slug, id: visible_page.id))
    expect(links).not_to include(page_path(workspace_slug: workspace.slug, id: hidden_page.id))
  end

  it "returns not found when trying to favorite records outside the policy scope" do
    owner = User.create!(email: "favorites-scope-owner@example.com", password: "password123")
    outsider = User.create!(email: "favorites-scope-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Favorites scope", slug: "favorites-scope")
    other_workspace = Workspace.create!(name: "Favorites scope other", slug: "favorites-scope-other")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: outsider, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Scoped page")
    database = Database.create!(workspace: workspace, name: "Scoped database")
    sign_in outsider

    post page_favorite_path(workspace_slug: workspace.slug, page_id: page.id)
    expect([ 302, 404 ]).to include(response.status)

    post database_favorite_path(workspace_slug: workspace.slug, database_id: database.id)
    expect([ 302, 404 ]).to include(response.status)
    expect(Favorite.where(user: outsider).count).to eq(0)
  end

  def favorites_section_links(html_body)
    document = Nokogiri::HTML(html_body)
    favorites_section = document.css(".notae-sidebar-section").find do |node|
      node.at_css(".notae-sidebar-label")&.text&.strip == "Favorites"
    end
    return [] unless favorites_section

    favorites_section.css("a").map { |node| node["href"] }
  end
end
