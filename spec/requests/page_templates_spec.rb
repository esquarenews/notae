require "rails_helper"

RSpec.describe "Page templates", type: :request do
  it "saves a page as template and creates a new page from it" do
    owner = User.create!(email: "page-template-request-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Template requests", slug: "template-requests")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Source page")

    parent_block = Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "paragraph",
      content_json: { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Parent" } ] } ] }
    )
    Block.create!(
      workspace: workspace,
      page: page,
      parent_block: parent_block,
      created_by: owner,
      block_type: "paragraph",
      content_json: { "type" => "doc", "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Child" } ] } ] }
    )
    sign_in owner

    post save_as_template_page_path(workspace_slug: workspace.slug, id: page.id),
         params: { page_template: { name: "Weekly notes" } }

    template = PageTemplate.find_by!(name: "Weekly notes")
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(template.snapshot_json["blocks"].size).to eq(2)

    post instantiate_page_template_path(workspace_slug: workspace.slug, id: template.id),
         params: { page_template: { title: "Weekly notes copy" } }

    expect(response).to redirect_to(/\/w\/#{workspace.slug}\/pages\//)

    new_page = Page.order(:created_at).last
    expect(new_page.title).to eq("Weekly notes copy")
    expect(new_page.id).not_to eq(page.id)
    expect(new_page.blocks.active.count).to eq(2)

    new_parent = new_page.blocks.active.find_by(parent_block_id: nil)
    new_child = new_page.blocks.active.find_by(parent_block_id: new_parent.id)
    expect(new_parent).to be_present
    expect(new_child).to be_present
  end

  it "blocks guests and outsiders from template management" do
    owner = User.create!(email: "page-template-policy-owner@example.com", password: "password123")
    guest = User.create!(email: "page-template-policy-guest@example.com", password: "password123")
    outsider = User.create!(email: "page-template-policy-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Template policy requests", slug: "template-policy-requests")
    other_workspace = Workspace.create!(name: "Template policy other", slug: "template-policy-other")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: guest, role: :guest)
    Membership.create!(workspace: other_workspace, user: outsider, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Source")
    template = PageTemplates::CreateFromPageService.call(page: page, created_by: owner, name: "Private template")

    sign_in guest
    post save_as_template_page_path(workspace_slug: workspace.slug, id: page.id),
         params: { page_template: { name: "Guest template" } }
    expect(response).to redirect_to(root_path)
    expect(PageTemplate.find_by(name: "Guest template")).to be_nil

    sign_out guest
    sign_in outsider

    post instantiate_page_template_path(workspace_slug: workspace.slug, id: template.id)

    expect(response).to have_http_status(:not_found)
  end
end
