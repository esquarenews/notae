require "rails_helper"

RSpec.describe "Fat Zebra webhooks", type: :request do
  def stub_webhook_secret(value)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("FAT_ZEBRA_WEBHOOK_SECRET").and_return(value)
  end

  it "rejects requests when production authentication is required but no secret is configured" do
    stub_webhook_secret("")
    allow(Rails.env).to receive(:production?).and_return(true)

    post fat_zebra_webhook_path, params: { event: "payment_plan:active", payload: {} }.to_json, headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:service_unavailable)
    expect(FatZebraWebhookEvent.count).to eq(0)
  end

  it "rejects requests with a wrong webhook token" do
    stub_webhook_secret("expected-token")

    post fat_zebra_webhook_path(token: "wrong-token"),
         params: { event: "payment_plan:active", payload: {} }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
    expect(FatZebraWebhookEvent.count).to eq(0)
  end

  it "accepts and reconciles payment plan webhooks when the token matches" do
    stub_webhook_secret("expected-token")
    owner = User.create!(email: "fz-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Fat Zebra Billing", slug: "fat-zebra-billing")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    subscription = workspace.create_workspace_subscription!(
      provider_customer_id: "1486-C-9R9FY0FE",
      provider_subscription_id: "1486-PP-ECY8AH07",
      status: WorkspaceSubscription::STATUS_TRIALING
    )

    expect do
      post fat_zebra_webhook_path(token: "expected-token"),
           params: {
             event: "payment_plan:active",
             payload: {
               id: "1486-PP-ECY8AH07",
               customer: "1486-C-9R9FY0FE",
               reference: "Plan456",
               status: "Active",
               payments: [
                 { id: "1486-PT-ASASNHVE", scheduled_date: "2026-05-23", status: "Scheduled" }
               ]
             }
           }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
    end.to change(FatZebraWebhookEvent, :count).by(1)
      .and change(AdminAuditEvent, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("status" => FatZebraWebhookEvent::STATUS_PROCESSED)
    expect(subscription.reload.status).to eq(WorkspaceSubscription::STATUS_ACTIVE)
    expect(subscription.current_period_ends_at.to_date).to eq(Date.new(2026, 5, 23))
    expect(subscription.metadata_json.dig("last_fat_zebra_event", "event")).to eq("payment_plan:active")
    expect(FatZebraWebhookEvent.last).to be_verified
    expect(FatZebraWebhookEvent.last.headers_json.values).not_to include("expected-token")
  end

  it "returns success without reprocessing duplicate deliveries" do
    stub_webhook_secret("expected-token")
    owner = User.create!(email: "fz-duplicate-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Fat Zebra Duplicate", slug: "fat-zebra-duplicate")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    workspace.create_workspace_subscription!(provider_subscription_id: "787-PP-4745AS4X")
    payload = {
      event: "payment_plan_payment:declined",
      payload: {
        id: "787-PT-G1EBHXZR",
        payment_plan: "787-PP-4745AS4X",
        reference: "PPAPI-001-0400",
        status: "Declined",
        result: "Insufficient Funds"
      }
    }.to_json

    post fat_zebra_webhook_path(token: "expected-token"), params: payload, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:ok)

    expect do
      post fat_zebra_webhook_path(token: "expected-token"), params: payload, headers: { "CONTENT_TYPE" => "application/json" }
    end.not_to change(FatZebraWebhookEvent, :count)

    expect(response).to have_http_status(:ok)
    expect(AdminAuditEvent.where(action: "fat_zebra_webhook_processed").count).to eq(1)
    expect(workspace.workspace_subscription.reload.status).to eq(WorkspaceSubscription::STATUS_PAST_DUE)
  end

  it "persists invalid webhook payloads and returns bad request" do
    stub_webhook_secret("expected-token")

    expect do
      post fat_zebra_webhook_path(token: "expected-token"), params: {}.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    end.to change(FatZebraWebhookEvent, :count).by(1)

    expect(response).to have_http_status(:bad_request)
    expect(FatZebraWebhookEvent.last).to be_failed
    expect(FatZebraWebhookEvent.last.event_name).to eq("malformed")
  end
end
