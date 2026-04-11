require "rails_helper"

RSpec.describe Page, type: :model do
  it "supports nested pages" do
    owner = User.create!(email: "page-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Docs", slug: "docs")
    parent = described_class.create!(workspace: workspace, created_by: owner, title: "Parent")
    child = described_class.create!(workspace: workspace, parent_page: parent, created_by: owner, title: "Child")

    expect(parent.child_pages).to include(child)
    expect(child.parent_page).to eq(parent)
  end

  it "builds a tab reference title for child tabs" do
    owner = User.create!(email: "page-tab-reference-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tab refs", slug: "tab-refs")
    parent = described_class.create!(workspace: workspace, created_by: owner, title: "Project")
    child = described_class.create!(workspace: workspace, parent_page: parent, created_by: owner, title: "Notes")

    expect(parent.tab_reference_title).to eq("Project")
    expect(child.tab_reference_title).to eq("Project / Notes")
  end

  it "defaults the root tab title without coupling it to the document title" do
    owner = User.create!(email: "page-root-tab-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Root tabs", slug: "root-tabs")
    root_page = described_class.create!(workspace: workspace, created_by: owner, title: "Project brief")
    child_page = described_class.create!(workspace: workspace, parent_page: root_page, created_by: owner, title: "Notes")

    expect(root_page.effective_tab_title).to eq("Tab 1")
    expect(child_page.effective_tab_title).to eq("Notes")

    root_page.update!(root_tab_title: "Overview")
    expect(root_page.reload.effective_tab_title).to eq("Overview")
    expect(root_page.title).to eq("Project brief")
  end

  it "archives and restores pages" do
    owner = User.create!(email: "page-archive-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Roadmap", slug: "roadmap")
    page = described_class.create!(workspace: workspace, created_by: owner, title: "Q1")

    page.archive!
    expect(page.reload.archived_at).to be_present

    page.restore!
    expect(page.reload.archived_at).to be_nil
  end

  it "updates a page when async indexing queue is unavailable" do
    owner = User.create!(email: "page-queue-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Queue safe", slug: "queue-safe")
    page = described_class.create!(workspace: workspace, created_by: owner, title: "Original")

    allow(Search::IndexPageJob).to receive(:perform_later).and_raise(Errno::ECONNREFUSED.new("Connection refused"))

    expect { page.update!(title: "Updated") }.not_to raise_error
    expect(page.reload.title).to eq("Updated")
  end

  it "supports explicit page kinds and meeting-note scope" do
    owner = User.create!(email: "page-kind-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page kind", slug: "page-kind")
    meeting_note = described_class.create!(workspace: workspace, created_by: owner, title: "Weekly sync", page_kind: "meeting_note")
    described_class.create!(workspace: workspace, created_by: owner, title: "Regular note", page_kind: "nota")

    expect(described_class.meeting_notes).to contain_exactly(meeting_note)
  end

  it "restricts tab colors to the supported palette" do
    owner = User.create!(email: "page-tab-color-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tab colors", slug: "tab-colors")
    page = described_class.new(workspace: workspace, created_by: owner, title: "Colored tab", tab_color: "infrared")

    expect(page).not_to be_valid
    expect(page.errors[:tab_color]).to include("is not included in the list")
  end
end
