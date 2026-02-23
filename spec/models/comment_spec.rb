require "rails_helper"

RSpec.describe Comment, type: :model do
  it "persists comments on pages and blocks and supports resolve/unresolve" do
    author = User.create!(email: "comment-author@example.com", password: "password123")
    resolver = User.create!(email: "comment-resolver@example.com", password: "password123")
    workspace = Workspace.create!(name: "Comments", slug: "comments")
    page = Page.create!(workspace: workspace, created_by: author, title: "Page")
    block = Block.create!(workspace: workspace, page: page, created_by: author, block_type: "paragraph")

    page_comment = described_class.create!(commentable: page, author: author, workspace: workspace, body: "Page comment")
    block_comment = described_class.create!(commentable: block, author: author, workspace: workspace, body: "Block comment")

    expect(page.comments).to include(page_comment)
    expect(block.comments).to include(block_comment)

    page_comment.resolve!(by: resolver)
    expect(page_comment.reload).to be_resolved
    expect(page_comment.resolved_by).to eq(resolver)

    page_comment.unresolve!
    expect(page_comment.reload).not_to be_resolved
  end
end
