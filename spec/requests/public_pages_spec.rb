require "rails_helper"

RSpec.describe "Public pages", type: :request do
  it "renders a shared page in read-only mode and logs access" do
    owner = User.create!(email: "public-page-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Public workspace", slug: "public-workspace")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Shared document")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Hello public world" } ] } ] }
    )
    share_link = ShareLink.create!(workspace: workspace, page: page, created_by: owner)

    get public_share_path(token: share_link.token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Shared document")
    expect(response.body).to include("Hello public world")
    expect(response.body).not_to include("Add block")
    view_event = ShareLinkView.recent_first.first
    expect(view_event.share_link_id).to eq(share_link.id)
    expect(view_event.ip_address).to be_present
    expect(view_event.viewed_at).to be_present
    expect(share_link.reload.last_viewed_at).to be_present
  end

  it "preserves public nota formatting for paragraphs, line breaks, headings, lists, quotes, and links" do
    owner = User.create!(email: "public-page-formatting-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Public formatting", slug: "public-formatting")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Formatted shared document")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "heading",
            "attrs" => { "level" => 2 },
            "content" => [
              { "type" => "text", "text" => "Public heading" }
            ]
          },
          {
            "type" => "paragraph",
            "content" => [
              { "type" => "text", "text" => "First line" },
              { "type" => "hardBreak" },
              { "type" => "text", "text" => "Second line" }
            ]
          },
          {
            "type" => "bulletList",
            "content" => [
              {
                "type" => "listItem",
                "content" => [
                  {
                    "type" => "paragraph",
                    "content" => [
                      { "type" => "text", "text" => "Visit " },
                      {
                        "type" => "text",
                        "text" => "Notae",
                        "marks" => [
                          { "type" => "link", "attrs" => { "href" => "https://example.com" } }
                        ]
                      }
                    ]
                  }
                ]
              }
            ]
          },
          {
            "type" => "blockquote",
            "content" => [
              {
                "type" => "paragraph",
                "content" => [
                  { "type" => "text", "text" => "Quoted paragraph" }
                ]
              }
            ]
          }
        ]
      }
    )
    share_link = ShareLink.create!(workspace: workspace, page: page, created_by: owner)

    get public_share_path(token: share_link.token)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    content = html.at_css(".notae-public-rich-text")

    expect(content.at_css("h2")&.text).to eq("Public heading")
    paragraph = content.at_css("p")
    expect(paragraph.text).to eq("First lineSecond line")
    expect(paragraph.css("br").size).to eq(1)
    expect(content.at_css("ul li")&.text).to include("Visit Notae")
    expect(content.at_css("a[href='https://example.com']")&.text).to eq("Notae")
    expect(content.at_css("blockquote")&.text).to include("Quoted paragraph")
  end

  it "returns 404 for invalid, expired, or revoked tokens" do
    owner = User.create!(email: "public-page-invalid-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Invalid share workspace", slug: "invalid-share-workspace")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Invalid token page")
    expired = ShareLink.create!(workspace: workspace, page: page, created_by: owner, expires_at: 1.minute.ago)
    revoked = ShareLink.create!(workspace: workspace, page: page, created_by: owner)
    revoked.revoke!

    get public_share_path(token: "missing-token")
    expect(response).to have_http_status(:not_found)

    get public_share_path(token: expired.token)
    expect(response).to have_http_status(:not_found)

    get public_share_path(token: revoked.token)
    expect(response).to have_http_status(:not_found)
  end
end
