require "rails_helper"

RSpec.describe PagePolicy do
  it "allows owner/admin/member to create and blocks guest, auditor, and automation agent from creating pages" do
    workspace = Workspace.create!(name: "Page Policy", slug: "page-policy")
    owner = User.create!(email: "page-pol-owner@example.com", password: "password123")
    admin = User.create!(email: "page-pol-admin@example.com", password: "password123")
    member = User.create!(email: "page-pol-member@example.com", password: "password123")
    guest = User.create!(email: "page-pol-guest@example.com", password: "password123")
    auditor = User.create!(email: "page-pol-auditor@example.com", password: "password123")
    automation_agent = User.create!(email: "page-pol-agent@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: admin, role: :admin)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: guest, role: :guest)
    Membership.create!(workspace: workspace, user: auditor, role: :auditor)
    Membership.create!(workspace: workspace, user: automation_agent, role: :automation_agent)

    new_page = Page.new(workspace: workspace, created_by: owner, title: "X")

    expect(described_class.new(owner, new_page).create?).to be(true)
    expect(described_class.new(admin, new_page).create?).to be(true)
    expect(described_class.new(member, new_page).create?).to be(true)
    expect(described_class.new(guest, new_page).create?).to be(false)
    expect(described_class.new(auditor, new_page).create?).to be(false)
    expect(described_class.new(automation_agent, new_page).create?).to be(false)
  end

  it "enforces private and specific user visibility modes" do
    workspace = Workspace.create!(name: "Visibility Policy", slug: "visibility-policy")
    owner = User.create!(email: "vis-owner@example.com", password: "password123")
    member = User.create!(email: "vis-member@example.com", password: "password123")
    other = User.create!(email: "vis-other@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: other, role: :member)

    private_page = Page.create!(workspace: workspace, created_by: owner, title: "Private", permission_mode: :private_page)
    specific_page = Page.create!(workspace: workspace, created_by: owner, title: "Specific", permission_mode: :specific_users)
    PageShare.create!(page: specific_page, user: member, created_by: owner)

    expect(described_class.new(member, private_page).show?).to be(false)
    expect(described_class.new(owner, private_page).show?).to be(true)
    expect(described_class.new(member, specific_page).show?).to be(true)
    expect(described_class.new(other, specific_page).show?).to be(false)
  end

  it "blocks member updates on locked pages while still allowing admin and owner" do
    workspace = Workspace.create!(name: "Locked policy", slug: "locked-policy")
    owner = User.create!(email: "locked-owner@example.com", password: "password123")
    admin = User.create!(email: "locked-admin@example.com", password: "password123")
    member = User.create!(email: "locked-member@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: admin, role: :admin)
    Membership.create!(workspace: workspace, user: member, role: :member)

    locked_page = Page.create!(workspace: workspace, created_by: owner, title: "Locked", locked: true)

    expect(described_class.new(member, locked_page).update?).to be(false)
    expect(described_class.new(admin, locked_page).update?).to be(true)
    expect(described_class.new(owner, locked_page).update?).to be(true)
  end

  it "memoizes workspace membership lookups across repeated policy checks" do
    workspace = Workspace.create!(name: "Memoized membership", slug: "memoized-membership")
    member = User.create!(email: "memoized-member@example.com", password: "password123")
    owner = User.create!(email: "memoized-owner@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)

    page = Page.new(workspace: workspace, created_by: owner, title: "Memoized page")

    membership_queries = []
    sql_probe = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql].to_s
      next if payload[:name].to_s == "SCHEMA"
      next unless sql.match?(/FROM\s+["`]memberships["`]/i)

      membership_queries << sql
    end

    ActiveSupport::Notifications.subscribed(sql_probe, "sql.active_record") do
      5.times { expect(described_class.new(member, page).create?).to be(true) }
    end

    expect(membership_queries.size).to be <= 1
  end

  it "scope returns only visible pages in accessible workspaces" do
    workspace = Workspace.create!(name: "Page scope policy", slug: "page-scope-policy")
    other_workspace = Workspace.create!(name: "Other page scope", slug: "other-page-scope")
    owner = User.create!(email: "page-scope-owner@example.com", password: "password123")
    member = User.create!(email: "page-scope-member@example.com", password: "password123")
    outsider = User.create!(email: "page-scope-outsider@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: other_workspace, user: outsider, role: :owner)

    shared_page = Page.create!(workspace: workspace, created_by: owner, title: "Shared", permission_mode: :shared_to_workspace)
    own_private_page = Page.create!(workspace: workspace, created_by: member, title: "Own private", permission_mode: :private_page)
    visible_specific_page = Page.create!(workspace: workspace, created_by: owner, title: "Visible specific", permission_mode: :specific_users)
    hidden_private_page = Page.create!(workspace: workspace, created_by: owner, title: "Hidden private", permission_mode: :private_page)
    hidden_specific_page = Page.create!(workspace: workspace, created_by: owner, title: "Hidden specific", permission_mode: :specific_users)
    outside_page = Page.create!(workspace: other_workspace, created_by: outsider, title: "Outside", permission_mode: :shared_to_workspace)

    PageShare.create!(page: visible_specific_page, user: member, created_by: owner)

    resolved_ids = described_class::Scope.new(member, Page).resolve.pluck(:id)

    expect(resolved_ids).to contain_exactly(
      shared_page.id,
      own_private_page.id,
      visible_specific_page.id
    )
    expect(resolved_ids).not_to include(hidden_private_page.id, hidden_specific_page.id, outside_page.id)
  end
end
