require "rails_helper"

RSpec.describe "Nota Maze game", type: :request do
  it "renders the hidden Nota Maze game for workspace members" do
    owner = User.create!(email: "nota-maze-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Nota Maze", slug: "nota-maze")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    get workspace_nota_maze_game_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nota Maze")
    expect(response.body).to include('data-controller="nota-maze-game"')
    expect(response.body).to include("notae-nota-maze-canvas")
    expect(response.body).to include("Collect every fragment.")
    expect(response.body).to include('data-nota-maze-game-target="soundButton"')
    expect(response.body).to include("Sound Off")
    expect(response.body).to include("Gold AI sparks let you resolve bugs")
    expect(response.body).to include("Swipe or tap a direction on touch screens.")
  end

  it "does not expose Nota Maze through visible workspace navigation" do
    owner = User.create!(email: "nota-maze-hidden-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Hidden Nota Maze", slug: "hidden-nota-maze")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    visible_links = document.css("a").map { |link| link["href"].to_s }

    expect(visible_links).not_to include(workspace_nota_maze_game_path(workspace_slug: workspace.slug))
    expect(document.text).not_to include("Fragments clear the maze")
  end

  it "does not allow non-members to open another workspace Nota Maze" do
    owner = User.create!(email: "nota-maze-real-owner@example.com", password: "password123")
    outsider = User.create!(email: "nota-maze-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Private Nota Maze", slug: "private-nota-maze")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in outsider

    get workspace_nota_maze_game_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:not_found)
  end
end
