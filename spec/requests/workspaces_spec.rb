require "rails_helper"

RSpec.describe "Workspaces", type: :request do
  def missing_table_error(table_name)
    ActiveRecord::StatementInvalid.new("PG::UndefinedTable: ERROR: relation \"#{table_name}\" does not exist")
  end

  it "renders new workspace when optional AI tables are unavailable" do
    user = User.create!(email: "workspace-new-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Existing", slug: "existing")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    allow(AiConversation).to receive(:for_user).and_raise(missing_table_error("ai_conversations"))
    allow(AiUsageLog).to receive(:for_user_and_workspace).and_raise(missing_table_error("ai_usage_logs"))

    get new_workspace_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Create Workspace")
  end

  it "lets an authenticated user create a workspace and become owner" do
    user = User.create!(email: "owner@example.com", password: "password123")
    sign_in user

    expect do
      post workspaces_path, params: { workspace: { name: "Product", slug: "product-team" } }
    end.to change(Workspace, :count).by(1)

    workspace = Workspace.find_by!(slug: "product-team")

    expect(response).to redirect_to(workspace_path("product-team"))
    expect(Membership.find_by!(workspace: workspace, user: user).role).to eq("owner")
  end

  it "restricts workspace access to members" do
    owner = User.create!(email: "ws-owner@example.com", password: "password123")
    outsider = User.create!(email: "outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Engineering", slug: "engineering")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    sign_in outsider
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:not_found)
  end
end
