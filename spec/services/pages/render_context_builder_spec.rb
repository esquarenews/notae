require "rails_helper"

RSpec.describe Pages::RenderContextBuilder, type: :service do
  it "preloads block assets and split-linked target pages for page rendering" do
    owner = User.create!(email: "page-render-context-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Render context", slug: "render-context")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    page = Page.create!(workspace: workspace, created_by: owner, title: "Source page")
    target_page = Page.create!(workspace: workspace, created_by: owner, title: "Target nota")
    target_grid_page = Page.create!(workspace: workspace, created_by: owner, title: "Target grid page")
    target_database = Database.create!(workspace: workspace, created_by: owner, name: "Target grid", linked_page: target_grid_page)

    page.blocks.create!(
      workspace: workspace,
      created_by: owner,
      block_type: "paragraph",
      content_json: split_link_content_json(workspace: workspace, source_page: page, target_page: target_page)
    )
    page.blocks.create!(
      workspace: workspace,
      created_by: owner,
      block_type: "paragraph",
      content_json: split_link_content_json(workspace: workspace, source_page: page, target_page: target_grid_page)
    )
    media_block = page.blocks.create!(workspace: workspace, created_by: owner, block_type: "image")
    media_block.asset.attach(
      io: StringIO.new("image-bytes"),
      filename: "preview.png",
      content_type: "image/png"
    )

    result = described_class.new(
      page: page,
      workspace: workspace,
      block_scope: Block.all,
      page_scope: Page.all
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
      expect(result.linked_target_pages_by_id.fetch(target_page.id.to_s).title).to eq("Target nota")
      expect(result.linked_target_pages_by_id.fetch(target_grid_page.id.to_s).linked_database&.id).to eq(target_database.id)
    end

    expect(queries).to be_empty
  end

  def split_link_content_json(workspace:, source_page:, target_page:)
    {
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            {
              "type" => "text",
              "text" => target_page.title,
              "marks" => [
                {
                  "type" => "link",
                  "attrs" => {
                    "href" => Rails.application.routes.url_helpers.page_path(
                      workspace_slug: workspace.slug,
                      id: source_page.id,
                      split_page_id: target_page.id,
                      split_source: "block"
                    )
                  }
                }
              ]
            }
          ]
        }
      ]
    }
  end
end
