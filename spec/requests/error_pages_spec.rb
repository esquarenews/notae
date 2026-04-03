require "rails_helper"

RSpec.describe "Error pages", type: :request do
  it "ships a disco-themed 404 page with workspace recovery actions" do
    error_page = Rails.root.join("public/404.html").read

    expect(error_page).to include("This page left the dancefloor.")
    expect(error_page).to include("The link is stale, the page moved, or this route never made it past soundcheck.")
    expect(error_page).to include("Back to workspace")
    expect(error_page).to include("Open notifications")
    expect(error_page).to include("Search Notae")
    expect(error_page).to include("Requested path")
    expect(error_page).to include("window.location.pathname")
    expect(error_page).to include('path.match(/^\\/w\\/([^/]+)/)')
  end
end
