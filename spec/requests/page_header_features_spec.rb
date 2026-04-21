require "rails_helper"

RSpec.describe "Page header features", type: :request do
  it "sets and clears a page icon, and renders it in topbar and sidebar page tree" do
    owner = User.create!(email: "page-header-icon-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Header Icon", slug: "header-icon")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Icon page")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { icon_action: "set", icon: "🧠" } }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.reload.icon).to eq("🧠")

    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css(".notae-page-icon-display .notae-icon-renderer-glyph")&.text&.strip).to eq("🧠")
    expect(html.at_css(".notae-topbar-page-icon .notae-icon-renderer-glyph")&.text&.strip).to eq("🧠")

    get workspace_path(workspace.slug)
    home_html = Nokogiri::HTML(response.body)
    page_card = home_html.at_css(".notae-workspace-page-card")
    expect(page_card.at_css(".notae-workspace-page-card-icon .notae-icon-renderer-glyph")&.text&.strip).to eq("🧠")
    expect(page_card.at_css(".notae-workspace-page-card-text strong")&.text&.strip).to eq("Icon page")

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { icon_action: "clear" } }
    expect(page.reload.icon).to be_nil
  end

  it "renders custom workspace emoji in the icon picker and overlaps the title icon over a cover" do
    owner = User.create!(email: "page-header-custom-emoji-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Header Emoji", slug: "header-emoji")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(
      workspace: workspace,
      created_by: owner,
      title: "Cover icon page",
      cover_preset_key: Page::COVER_PRESET_KEYS.first
    )

    Tempfile.create([ "custom-emoji", ".png" ]) do |file|
      file.write("fake-png-content")
      file.rewind

      emoji = workspace.custom_emojis.build
      emoji.name = "Party avocado"
      emoji.image.attach(Rack::Test::UploadedFile.new(file.path, "image/png"))
      emoji.save!
      page.update!(icon: emoji.icon_token)
    end

    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css(".notae-page-icon-display.is-over-cover .notae-icon-renderer.is-custom img")).to be_present
    picker_labels = html.css(".notae-emoji-picker-section summary").map { |summary| summary.text.squish }
    expect(picker_labels).to include("Custom emoji")
    expect(picker_labels).to include("Smileys & Emotion")
    search_field = html.at_css(".notae-emoji-picker input[type='search']")
    expect(search_field).to be_present
    expect(search_field["placeholder"]).to eq("Search")
    picker_children = html.at_css(".notae-emoji-picker").element_children.map { |element| element["class"].to_s }
    expect(picker_children.index("notae-emoji-picker-search")).to be < picker_children.index("notae-emoji-picker-remove-form")
    expect(picker_children.index("notae-emoji-picker-remove-form")).to be < picker_children.index("notae-emoji-picker-current")
    expect(html.at_css(".notae-emoji-picker-remove")&.text&.squish).to eq("Remove icon")
    custom_button = html.at_css(".notae-page-emoji-button.is-custom")
    expect(custom_button["data-search-text"]).to include("Party avocado")
  end

  it "styles the remove icon action as a red destructive row near the top of the picker" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-emoji-picker-remove {\n  width: 100%;")
    expect(stylesheet).to include("background: color-mix(in srgb, #fee2e2 80%, var(--notae-panel-elevated, #fff) 20%);")
    expect(stylesheet).to include("color: #b91c1c;")
  end

  it "shifts grid header icons to the right for visual balance" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-db-header > .notae-page-icon-display {\n  margin-left: 20px;\n}")
  end

  it "centers the Unsplash browser modal in the viewport" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-cover-unsplash-modal {\n  position: fixed;\n  inset: 0;\n  width: 100vw;\n  height: 100vh;")
    expect(stylesheet).to include(".notae-cover-unsplash-modal[open] {\n  display: grid;\n  place-items: center;\n}")
  end

  it "keeps Unsplash pagination on one centered line" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read
    template = Rails.root.join("app/views/shared/_cover_picker_panel.html.erb").read

    expect(stylesheet).to include(".notae-cover-unsplash-pagination {\n  display: grid;\n  grid-template-columns: fit-content(9.5rem) minmax(8.5rem, auto) fit-content(9.5rem);")
    expect(stylesheet).to include(".notae-cover-unsplash-page-label {\n  grid-column: 2;")
    expect(stylesheet).to include("min-width: 8.5rem;")
    expect(stylesheet).to include("white-space: nowrap;")
    expect(template).to include("Page 1 of 1")
  end

  it "renders cover attribution text and links in white on the right edge for readability" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-cover-attribution {\n  position: absolute;")
    expect(stylesheet).to include("right: 0.9rem;")
    expect(stylesheet).to include("max-width: calc(100% - 1.8rem);")
    expect(stylesheet).to include("text-align: right;")
    expect(stylesheet).to include(".notae-theme .notae-cover-attribution,\n.notae-theme .notae-cover-attribution a,\n.notae-theme .notae-cover-attribution a:visited,")
    expect(stylesheet).to include(".notae-theme .notae-cover-attribution a,\n.notae-theme .notae-cover-attribution a:visited,")
    expect(stylesheet).to include("color: #fff;")
    expect(stylesheet).to include(".notae-workspace-page-card-cover-attribution {\n  position: absolute;")
    expect(stylesheet).to include(".notae-workspace-page-card-cover-attribution a {")
  end

  it "supports random cover, upload cover, repositioning, and clearing" do
    owner = User.create!(email: "page-header-cover-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Header Cover", slug: "header-cover")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Cover page")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { cover_action: "random" } }
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(Page::COVER_PRESET_KEYS.size).to eq(60)
    expect(Page::COVER_PRESET_GROUPS.map { |group| group[:label] }).to eq(%w[Original Vector Pastel Bold Gradient])
    Page.asset_cover_preset_keys.each do |key|
      expect(Rails.root.join("app/assets/images/page_covers/#{key}.svg")).to exist
    end
    expect(Page::COVER_PRESET_KEYS).to include(page.reload.cover_preset_key)
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response.body).to include("notae-cover-picker-grid")
    expect(response.body).to include("notae-cover-picker-quick-actions")
    expect(response.body).to include("notae-cover-picker-upload-form")
    expect(response.body).to include("Browse Unsplash")
    expect(response.body).to include("notae-cover-unsplash-modal")
    expect(response.body).to include('enctype="multipart/form-data"')
    expect(response.body).to include('data-cover-carousel-target="uploadInput"')
    expect(response.body).to include('data-cover-carousel-target="uploadError"')
    expect(response.body).to include("data-controller=\"cover-carousel\"")
    expect(response.body).to include("Original")
    expect(response.body).to include("Vector")
    expect(response.body).to include("Pastel")
    expect(response.body).to include("Bold")
    expect(response.body).to include("Gradient")

    chosen_preset = "gradient-cosmos"
    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { cover_action: "preset", cover_preset_key: chosen_preset } }
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.reload.cover_preset_key).to eq(chosen_preset)

    previous_focal = page.cover_focal_y
    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { cover_shift: "down" } }
    expect(page.reload.cover_focal_y).to eq([ previous_focal + 10, 100 ].min)

    Tempfile.create([ "page-cover-upload", ".png" ]) do |file|
      file.write("fake-png-content")
      file.rewind
      uploaded_file = Rack::Test::UploadedFile.new(file.path, "image/png")

      patch page_path(workspace_slug: workspace.slug, id: page.id),
            params: { page: { cover_action: "upload", cover_image: uploaded_file } }
    end

    expect(page.reload.cover_image).to be_attached
    expect(page.cover_preset_key).to be_nil
    expect(workspace.cover_assets.where(created_by: owner, source_kind: "upload").count).to eq(1)

    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response.body).to include("Recent")

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { cover_action: "clear" } }
    expect(page.reload.cover_preset_key).to be_nil
    expect(page.cover_image).not_to be_attached
  end

  it "applies Unsplash covers remotely, records them for reuse, and renders attribution" do
    owner = User.create!(email: "page-header-unsplash-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Unsplash header", slug: "unsplash-header")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Unsplash page")
    sign_in owner

    client = instance_double(
      Unsplash::Client,
      photo: {
        id: "photo-77",
        alt: "Ocean dusk",
        preview_url: "https://images.unsplash.com/photo-77-small",
        full_url: "https://images.unsplash.com/photo-77-regular",
        artist_name: "Ava Artist",
        artist_url: "https://unsplash.com/@ava?utm_source=notae&utm_medium=referral",
        source_name: "Unsplash",
        source_url: "https://unsplash.com/?utm_source=notae&utm_medium=referral",
        download_location: "https://api.unsplash.com/photos/photo-77/download"
      }
    )
    allow(client).to receive(:register_download!).with("https://api.unsplash.com/photos/photo-77/download")
    allow(Unsplash::Client).to receive(:new).and_return(client)

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { cover_action: "unsplash", cover_remote_id: "photo-77" } }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.reload.cover_remote_url).to eq("https://images.unsplash.com/photo-77-regular")
    expect(page.cover_remote_thumb_url).to eq("https://images.unsplash.com/photo-77-small")
    expect(page.cover_artist_name).to eq("Ava Artist")
    expect(page.cover_source_name).to eq("Unsplash")
    expect(page.cover_image).not_to be_attached

    recent_asset = workspace.cover_assets.find_by!(created_by: owner, source_kind: "unsplash", external_id: "photo-77")
    expect(recent_asset.remote_image_url).to eq("https://images.unsplash.com/photo-77-regular")

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { cover_action: "recent", cover_asset_id: recent_asset.id } }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.reload.cover_remote_url).to eq("https://images.unsplash.com/photo-77-regular")

    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response.body).to include("Photo by")
    expect(response.body).to include("Ava Artist")
    expect(response.body).to include("Recent")
  end

  it "renders hover action affordances and topbar comments menu with existing comments" do
    owner = User.create!(email: "page-header-comment-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Header Comment", slug: "header-comment")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Comment page")
    Comment.create!(workspace: workspace, commentable: page, author: owner, body: "First page comment")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add icon")
    expect(response.body).to include("Add cover")
    expect(response.body).to include("Add comment")
    expect(response.body).to include("id=\"page-comments-menu\"")
    expect(response.body).to include("notae-comments-trigger")
    expect(response.body).to include("aria-label=\"Actions\"")
    expect(response.body).to include("aria-label=\"Options\"")
    html = Nokogiri::HTML(response.body)
    actions_menu = html.at_css("#page-actions-menu")
    expect(actions_menu).to be_present
    expect(actions_menu["data-controller"]).to include("lazy-panel")
    expect(actions_menu["data-lazy-panel-url-value"]).to eq(panel_page_path(workspace_slug: workspace.slug, id: page.id, panel: "actions", current_path: page_path(workspace_slug: workspace.slug, id: page.id)))
    options_menu = html.at_css("#page-options-menu")
    expect(options_menu).to be_present
    expect(options_menu["data-controller"]).to include("lazy-panel")
    expect(options_menu["data-lazy-panel-url-value"]).to eq(panel_page_path(workspace_slug: workspace.slug, id: page.id, panel: "options"))
    expect(response.body).to include("notae-actions-trigger-label")
    expect(response.body).not_to include("First page comment")
    expect(response.body).not_to include("Add a comment...")

    get panel_page_path(workspace_slug: workspace.slug, id: page.id, panel: "comments")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("First page comment")
    expect(response.body).to include("Add a comment...")
  end
end
