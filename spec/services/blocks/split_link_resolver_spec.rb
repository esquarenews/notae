require "rails_helper"

RSpec.describe Blocks::SplitLinkResolver, type: :service do
  it "resolves the linked split-preview target page from block content" do
    owner = User.create!(email: "split-link-resolver-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Split link resolver", slug: "split-link-resolver")
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Source")
    target_page = Page.create!(workspace: workspace, created_by: owner, title: "Target")

    content_json = {
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            {
              "type" => "text",
              "text" => "Target",
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

    expect(described_class.target_page_id(content_json: content_json)).to eq(target_page.id.to_s)
    expect(described_class.target_page(content_json: content_json, workspace: workspace)).to eq(target_page)
  end

  it "removes split-preview links while preserving other links and text" do
    owner = User.create!(email: "split-link-resolver-unlink-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Split unlink resolver", slug: "split-unlink-resolver")
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Source")
    target_page = Page.create!(workspace: workspace, created_by: owner, title: "Target")

    content_json = {
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            {
              "type" => "text",
              "text" => "Target",
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
            },
            { "type" => "text", "text" => " and " },
            {
              "type" => "text",
              "text" => "external",
              "marks" => [
                {
                  "type" => "link",
                  "attrs" => { "href" => "https://example.com" }
                }
              ]
            }
          ]
        }
      ]
    }

    result = described_class.unlink(content_json: content_json)

    expect(result.dig("content", 0, "content", 0, "text")).to eq("Target")
    expect(result.dig("content", 0, "content", 0, "marks")).to be_nil
    expect(result.dig("content", 0, "content", 2, "marks")).to eq(
      [ { "type" => "link", "attrs" => { "href" => "https://example.com" } } ]
    )
  end
end
