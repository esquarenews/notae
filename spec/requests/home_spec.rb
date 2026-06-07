require "rails_helper"

RSpec.describe "Home", type: :request do
  it "renders the root page with the base layout" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<title>Notae</title>")
    expect(response.body).to include("Sign in")
    expect(response.body).to include("Start a 7-day trial")
    expect(response.body).to include("Starter")
    expect(response.body).to include("Team")
    expect(response.body).to include("Business")
    expect(response.headers["Content-Security-Policy"]).to include("default-src 'self'")
    expect(response.headers["Content-Security-Policy"]).to include("frame-ancestors 'self'")
    expect(response.headers["X-Frame-Options"]).to eq("SAMEORIGIN")
    expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
    expect(response.headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin")
  end

  it "links the compiled application stylesheet from the base layout" do
    get root_path

    expect(response).to have_http_status(:ok)

    html = Nokogiri::HTML(response.body)
    asset_stylesheets = html.css("link[rel='stylesheet']").filter_map do |node|
      href = node["href"].to_s
      href if href.start_with?("/assets/")
    end

    expect(asset_stylesheets).to include(a_string_matching(%r{\A/assets/application(?:-[0-9a-f]+)?\.css\z}))
    expect(asset_stylesheets).not_to include(a_string_matching(%r{\A/assets/app(?:-[0-9a-f]+)?\.css\z}))
  end

  it "redirects authenticated users to their first policy-scoped workspace" do
    user = User.create!(email: "member@example.com", password: "password123")
    other_user = User.create!(email: "other@example.com", password: "password123")
    visible_workspace = Workspace.create!(name: "Visible", slug: "visible")
    hidden_workspace = Workspace.create!(name: "Hidden", slug: "hidden")

    Membership.create!(user: user, workspace: visible_workspace, role: :owner)
    Membership.create!(user: other_user, workspace: hidden_workspace, role: :owner)

    sign_in user
    get root_path

    expect(response).to redirect_to(workspace_path(visible_workspace.slug))
  end
end
