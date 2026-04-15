require "rails_helper"

RSpec.describe Pages::RenderContextBuilder, type: :service do
  it "preloads block assets for page rendering" do
    owner = User.create!(email: "page-render-context-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Render context", slug: "render-context")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    page = Page.create!(workspace: workspace, created_by: owner, title: "Source page")
    media_block = page.blocks.create!(workspace: workspace, created_by: owner, block_type: "image")
    media_block.asset.attach(
      io: StringIO.new("image-bytes"),
      filename: "preview.png",
      content_type: "image/png"
    )

    result = described_class.new(
      page: page,
      block_scope: Block.all
    ).call

    queries = []
    sql_probe = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql].to_s
      next if payload[:name].to_s == "SCHEMA"
      next if payload[:cached]

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(sql_probe, "sql.active_record") do
      expect(result.active_blocks.find { |block| block.id == media_block.id }&.asset&.attached?).to be(true)
    end

    expect(queries).to be_empty
  end
end
