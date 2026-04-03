require "rails_helper"

RSpec.describe "Workspace cover browser", type: :request do
  it "returns Unsplash browse results for the current workspace" do
    user = User.create!(email: "cover-browser@example.com", password: "password123")
    workspace = Workspace.create!(name: "Cover browser", slug: "cover-browser")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    client = instance_double(
      Unsplash::Client,
      list_photos: {
        photos: [
          {
            id: "photo-1",
            alt: "Forest path",
            preview_url: "https://images.unsplash.com/photo-1-small",
            full_url: "https://images.unsplash.com/photo-1-regular",
            artist_name: "Pat Photographer",
            artist_url: "https://unsplash.com/@pat",
            source_name: "Unsplash",
            source_url: "https://unsplash.com/?utm_source=notae&utm_medium=referral",
            download_location: "https://api.unsplash.com/photos/photo-1/download"
          }
        ],
        page: 2,
        total_pages: 8
      }
    )
    allow(Unsplash::Client).to receive(:new).and_return(client)

    get workspace_cover_unsplash_path(workspace_slug: workspace.slug), params: { page: 2, per_page: 12 }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include(
      "page" => 2,
      "total_pages" => 8
    )
    expect(JSON.parse(response.body).fetch("photos").first).to include(
      "id" => "photo-1",
      "artist_name" => "Pat Photographer"
    )
  end
end
