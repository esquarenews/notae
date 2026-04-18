require "rails_helper"

RSpec.describe "Session authentication resilience", type: :request do
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  it "logs diagnostics and resets the session when csrf validation fails" do
    user = User.create!(email: "csrf-session@example.com", password: "password123", time_zone: "Australia/Melbourne")
    workspace = Workspace.create!(name: "CSRF Test", slug: "csrf-test")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = workspace.pages.create!(title: "Test page", created_by: user, page_kind: "nota")

    sign_in user

    events = []
    subscription = ActiveSupport::Notifications.subscribe(Notae::SessionDiagnostics::EVENT_NAME) do |_name, _start, _finish, _id, payload|
      events << payload
    end

    post page_comments_path(workspace_slug: workspace.slug, page_id: page.id),
         params: { comment: { body: "This should fail csrf." } }

    expect(response).to redirect_to(new_user_session_path)
    follow_redirect!
    expect(response.body).to include("Please sign in again.")

    event = events.find { |payload| payload[:reason] == "invalid_authenticity_token" }
    expect(event).to be_present
    expect(event[:user_id]).to eq(user.id.to_s)
    expect(event[:path]).to include("/w/#{workspace.slug}/pages/#{page.id}/comments")
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end
end
