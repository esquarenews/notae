require "rails_helper"

RSpec.describe "Analytics activity buckets", type: :request do
  let(:user) { User.create!(email: "activity-recorder@example.com", password: "password123") }
  let(:workspace) { Workspace.create!(name: "Activity workspace", slug: "activity-workspace") }

  before do
    Membership.create!(workspace:, user:, role: :member)
    sign_in user
  end

  it "records an authorized foreground activity sample" do
    expect do
      post analytics_activity_path,
           params: {
             activity: {
               workspace_slug: workspace.slug,
               surface: "nota",
               bucket_started_at: Time.current.beginning_of_minute.iso8601,
               duration_seconds: 24,
               sample_id: "request-sample-123"
             }
           }
    end.to change(AnalyticsActivityBucket, :count).by(1)

    expect(response).to have_http_status(:no_content)
    bucket = AnalyticsActivityBucket.find_by!(user:, sample_id: "request-sample-123", segment_index: 0)
    expect(bucket).to have_attributes(user_id: user.id, workspace_id: workspace.id, surface: "nota", duration_seconds: 24)
  end

  it "rejects unknown surfaces without recording content from the request" do
    expect do
      post analytics_activity_path,
           params: {
             activity: {
               workspace_slug: workspace.slug,
               surface: "secret-document-title",
               bucket_started_at: Time.current.iso8601,
               duration_seconds: 30
             }
           }
    end.not_to change(AnalyticsActivityBucket, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "does not record samples when workspace analytics are disabled" do
    workspace.update!(analytics_enabled: false)

    expect do
      post analytics_activity_path,
           params: {
             activity: {
               workspace_slug: workspace.slug,
               surface: "grid",
               bucket_started_at: Time.current.iso8601,
               duration_seconds: 30
             }
           }
    end.not_to change(AnalyticsActivityBucket, :count)

    expect(response).to have_http_status(:no_content)

    get workspace_path(workspace.slug)
    expect(response).to have_http_status(:ok)
    body = Nokogiri::HTML(response.body).at_css("body")
    expect(body["data-controller"].to_s.split).not_to include("analytics-tracker")
    expect(response.body).not_to include('data-analytics-tracker-endpoint-value="/analytics/activity"')
  end

  it "does not expose or record an inaccessible workspace" do
    hidden_workspace = Workspace.create!(name: "Hidden activity", slug: "hidden-activity")

    expect do
      post analytics_activity_path,
           params: {
             activity: {
               workspace_slug: hidden_workspace.slug,
               surface: "home",
               bucket_started_at: Time.current.iso8601,
               duration_seconds: 30
             }
           }
    end.not_to change(AnalyticsActivityBucket, :count)

    expect(response).to have_http_status(:not_found)
  end
end
