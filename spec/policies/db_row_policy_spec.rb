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

  it "returns only rows from databases visible to the user" do
    workspace = Workspace.create!(name: "Row database visibility", slug: "row-database-visibility")
    owner = User.create!(email: "db-row-vis-owner@example.com", password: "password123")
    member = User.create!(email: "db-row-vis-member@example.com", password: "password123")
    other = User.create!(email: "db-row-vis-other@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: other, role: :member)

    shared_database = Database.create!(workspace: workspace, created_by: owner, name: "Shared rows", permission_mode: :shared_to_workspace)
    hidden_database = Database.create!(workspace: workspace, created_by: owner, name: "Hidden rows", permission_mode: :private_database)
    specific_database = Database.create!(workspace: workspace, created_by: owner, name: "Specific rows", permission_mode: :specific_users)
    DatabaseShare.create!(database: specific_database, user: member, created_by: owner)

    visible_shared = DbRow.create!(workspace: workspace, database: shared_database, title: "Visible shared")
    visible_specific = DbRow.create!(workspace: workspace, database: specific_database, title: "Visible specific")
    hidden_private = DbRow.create!(workspace: workspace, database: hidden_database, title: "Hidden private")

    resolved_ids = described_class.new(member, DbRow).resolve.pluck(:id)

    expect(resolved_ids).to contain_exactly(visible_shared.id, visible_specific.id)
    expect(described_class.new(other, DbRow).resolve).not_to include(visible_specific, hidden_private)
  end
end

RSpec.describe DbPropertyPolicy::Scope do
  it "returns only properties from databases visible to the user" do
    workspace = Workspace.create!(name: "Property database visibility", slug: "property-database-visibility")
    owner = User.create!(email: "db-property-vis-owner@example.com", password: "password123")
    member = User.create!(email: "db-property-vis-member@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)

    shared_database = Database.create!(workspace: workspace, created_by: owner, name: "Shared properties", permission_mode: :shared_to_workspace)
    hidden_database = Database.create!(workspace: workspace, created_by: owner, name: "Hidden properties", permission_mode: :private_database)
    visible_property = DbProperty.create!(workspace: workspace, database: shared_database, name: "Visible")
    hidden_property = DbProperty.create!(workspace: workspace, database: hidden_database, name: "Hidden")

    resolved_scope = described_class.new(member, DbProperty).resolve

    expect(resolved_scope).to include(visible_property)
    expect(resolved_scope).not_to include(hidden_property)
  end
end

RSpec.describe DbCellPolicy::Scope do
  it "returns only cells from rows in databases visible to the user" do
    workspace = Workspace.create!(name: "Cell database visibility", slug: "cell-database-visibility")
    owner = User.create!(email: "db-cell-vis-owner@example.com", password: "password123")
    member = User.create!(email: "db-cell-vis-member@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)

    shared_database = Database.create!(workspace: workspace, created_by: owner, name: "Shared cells", permission_mode: :shared_to_workspace)
    hidden_database = Database.create!(workspace: workspace, created_by: owner, name: "Hidden cells", permission_mode: :private_database)
    visible_property = DbProperty.create!(workspace: workspace, database: shared_database, name: "Visible")
    hidden_property = DbProperty.create!(workspace: workspace, database: hidden_database, name: "Hidden")
    visible_row = DbRow.create!(workspace: workspace, database: shared_database, title: "Visible")
    hidden_row = DbRow.create!(workspace: workspace, database: hidden_database, title: "Hidden")
    visible_cell = DbCell.create!(workspace: workspace, db_row: visible_row, db_property: visible_property, value_text: "visible")
    hidden_cell = DbCell.create!(workspace: workspace, db_row: hidden_row, db_property: hidden_property, value_text: "hidden")

    resolved_scope = described_class.new(member, DbCell).resolve

    expect(resolved_scope).to include(visible_cell)
    expect(resolved_scope).not_to include(hidden_cell)
  end
end
