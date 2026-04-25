require "rails_helper"

RSpec.describe "Archive game", type: :request do
  it "renders the hidden archive game for workspace members" do
    owner = User.create!(email: "archive-game-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Archive Game", slug: "archive-game")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    get workspace_archive_game_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("The Archive")
    expect(response.body).to include('data-controller="archive-game"')
    expect(response.body).to include("notae-archive-game-canvas")
    expect(response.body).to include("Recover the lost fragments.")
    expect(response.body).to include('data-archive-game-target="level"')
    expect(response.body).to include('data-archive-game-target="soundButton"')
    expect(response.body).to include("Sound off")
    expect(response.body).to include("Enter the Index to open the next faster level.")
    expect(response.body).to include("Tap, drag, or swipe to move.")
  end

  it "does not expose the archive game through visible workspace navigation" do
    owner = User.create!(email: "archive-game-hidden-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Hidden Archive Game", slug: "hidden-archive-game")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    visible_links = document.css("a").map { |link| link["href"].to_s }

    expect(visible_links).not_to include(workspace_archive_game_path(workspace_slug: workspace.slug))
    expect(document.text).not_to include("Recovered fragments unlock the Index")
  end

  it "does not allow non-members to open another workspace archive" do
    owner = User.create!(email: "archive-game-real-owner@example.com", password: "password123")
    outsider = User.create!(email: "archive-game-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Private Archive Game", slug: "private-archive-game")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in outsider

    get workspace_archive_game_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:not_found)
  end
end
