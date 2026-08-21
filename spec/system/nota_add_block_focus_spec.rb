require "rails_helper"
require "capybara/rspec"
require "warden/test/helpers"

RSpec.describe "Adding a block to a long Nota", type: :system do
  include Warden::Test::Helpers

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 900 ]
  end

  after do
    Warden.test_reset!
  end

  it "keeps the new block in view and moves the insertion point into it" do
    user = User.create!(email: "nota-add-block-focus@example.com", password: "password123")
    workspace = Workspace.create!(name: "Nota block focus", slug: "nota-block-focus")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    nota = Page.create!(workspace: workspace, created_by: user, title: "Long Nota")

    existing_blocks = 30.times.map do |index|
      Block.create!(
        workspace: workspace,
        page: nota,
        created_by: user,
        block_type: "paragraph",
        content_json: {
          type: "doc",
          content: [ { type: "paragraph", content: [ { type: "text", text: "Section #{index + 1}" } ] } ]
        }
      )
    end

    login_as user, scope: :user
    visit page_path(workspace_slug: workspace.slug, id: nota.id)
    add_button = find(".notae-doc-add-button")
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", add_button.native)
    scroll_top_before = page.evaluate_script('document.querySelector(".notae-content-scroll").scrollTop')

    add_button.click

    autofocus_editor = find("[data-block-editor-autofocus-value='true']", wait: 8)
    created_block_id = autofocus_editor.find(:xpath, "ancestor::*[@data-block-id][1]")["data-block-id"]
    created_block = nota.blocks.find(created_block_id)
    expect(existing_blocks.map(&:id)).not_to include(created_block.id)
    expect(page).to have_css("#block_#{created_block.id} .ProseMirror:focus", wait: 8)

    result = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const scroller = document.querySelector(".notae-content-scroll")
        const block = document.querySelector("#block_#{created_block.id}")
        const activeBlock = document.activeElement?.closest?.("[data-block-id]")
        const blockRect = block.getBoundingClientRect()
        const scrollerRect = scroller.getBoundingClientRect()

        return {
          activeBlockId: activeBlock?.dataset?.blockId || null,
          contenteditableFocused: document.activeElement?.classList?.contains("ProseMirror") || false,
          scrollTop: scroller.scrollTop,
          visible: blockRect.bottom > scrollerRect.top && blockRect.top < scrollerRect.bottom
        }
      })()
    JAVASCRIPT

    expect(result.fetch("activeBlockId")).to eq(created_block.id.to_s)
    expect(result.fetch("contenteditableFocused")).to be(true)
    expect(result.fetch("visible")).to be(true)
    expect(result.fetch("scrollTop")).to be >= scroll_top_before - 2
  end
end
