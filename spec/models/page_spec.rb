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
end
