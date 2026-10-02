require "rails_helper"

RSpec.describe "Public legal pages", type: :request do
  it "makes both policies accessible without signing in and links them from the homepage" do
    get root_path
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("a[href='#{privacy_policy_path}']").text).to eq("Privacy Policy")
    expect(html.at_css("a[href='#{terms_of_use_path}']").text).to eq("Terms of Use")

    get privacy_policy_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Google Calendar", "Limited Use", "read-only calendar-list access", "AI provider", "account deletion request")
    expect(Nokogiri::HTML(response.body).at_css("a[href='#{terms_of_use_path}']")).to be_present

    get terms_of_use_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Terms of Use", "Australian Consumer Law", "You retain ownership", "cancel subscriptions")

    get new_user_registration_path
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("a[href='#{privacy_policy_path}']")).to be_present
    expect(html.at_css("a[href='#{terms_of_use_path}']")).to be_present
  end

  it "allows signed-in users to read the public policies without workspace redirects" do
    user = User.create!(email: "legal-reader@example.com", password: "password123")
    sign_in user

    [ privacy_policy_path, terms_of_use_path ].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("notae-shell")
    end
  end
end
