require "rails_helper"

RSpec.describe DbRowPolicy::Scope do
  it "returns rows only in workspaces available to the user" do
    owner = User.create!(email: "db-row-owner@example.com", password: "password123")
    outsider = User.create!(email: "db-row-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Rows", slug: "rows")
    other_workspace = Workspace.create!(name: "Other Rows", slug: "other-rows")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: outsider, role: :owner)
    db1 = Database.create!(workspace: workspace, name: "Main")
    db2 = Database.create!(workspace: other_workspace, name: "Other")
    visible = DbRow.create!(workspace: workspace, database: db1, title: "Visible", data_json: { a: "1" })
    hidden = DbRow.create!(workspace: other_workspace, database: db2, title: "Hidden", data_json: { a: "1" })

    resolved_scope = described_class.new(owner, DbRow.all).resolve

    expect(resolved_scope).to include(visible)
    expect(resolved_scope).not_to include(hidden)
  end
end
