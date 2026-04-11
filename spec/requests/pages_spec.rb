require "rails_helper"

RSpec.describe "Pages", type: :request do
  it "styles the active tab with stronger emphasis" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-page-tab-shell.is-active {\n  border-color: color-mix(in srgb, var(--notae-tab-accent) 56%, var(--notae-border));\n  background: color-mix(in srgb, var(--notae-tab-accent) 22%, var(--notae-surface-raised));\n  box-shadow: 0 8px 18px color-mix(in srgb, var(--notae-tab-accent) 18%, rgba(15, 23, 42, 0.18)), inset 0 1px 0 rgba(255, 255, 255, 0.42);\n  transform: translateY(-1px);")
  end

  it "pins the new tab action to the right edge of the tab strip" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-page-tabs {\n  display: flex;\n  align-items: flex-start;\n  gap: 0.72rem;")
    expect(stylesheet).to include(".notae-page-tabs-list {\n  display: flex;\n  align-items: center;\n  flex: 1 1 auto;\n  min-width: 0;")
    expect(stylesheet).to include(".notae-page-tab-create-form {\n  margin: 0 0 0 auto;\n  flex: 0 0 auto;")
  end

  it "renders the shared topbar as a translucent blurred surface" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-topbar {\n  min-height: 4rem;")
    expect(stylesheet).to include("  position: relative;\n  z-index: 140;\n  isolation: isolate;")
    expect(stylesheet).to include("  background-color: color-mix(in srgb, var(--notae-panel-bg) 24%, transparent);")
    expect(stylesheet).to include("  background:\n    linear-gradient(\n      180deg,\n      color-mix(in srgb, var(--notae-panel-elevated) 42%, transparent),\n      color-mix(in srgb, var(--notae-panel-bg) 26%, transparent)\n    );")
    expect(stylesheet).to include("  -webkit-backdrop-filter: blur(24px) saturate(1.18);")
    expect(stylesheet).to include("  backdrop-filter: blur(24px) saturate(1.18);")
    expect(stylesheet).to include(".notae-page-cover {\n  padding-top: 0.4rem;\n}")
    expect(stylesheet).to include(".notae-page-cover-frame {\n  margin: 0 clamp(0.9rem, 3vw, 1.4rem);\n  height: clamp(230px, 31vw, 360px);")
  end

  it "keeps the title save status above the cover controls without lifting the closed picker" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-page-title-form {\n  width: 100%;\n  position: relative;\n  z-index: 80;")
    expect(stylesheet).to include(".notae-page-title-form .notae-doc-muted {\n  position: relative;\n  z-index: 81;")
    expect(stylesheet).to include(".notae-page-cover-controls {\n  position: absolute;")
    expect(stylesheet).to include("  z-index: 32;")
    expect(stylesheet).to include(".notae-page-cover-controls:has(.notae-cover-picker[open]) {\n  z-index: var(--notae-layer-popover-region);\n}")
  end

  it "keeps the green flash notice above page controls and popovers" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include("--notae-layer-flash: 1400;")
    expect(stylesheet).to include(".notae-content.notae-content-page > #notae_flash_messages,\n.notae-content.notae-content-home > #notae_flash_messages {\n  position: sticky;\n  top: 0.65rem;\n  z-index: var(--notae-layer-flash);")
  end

  it "elevates shared context menu layers above page chrome while staying below flash" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include("--notae-layer-popover-region: 1080;")
    expect(stylesheet).to include("--notae-layer-popover-parent: 1100;")
    expect(stylesheet).to include("--notae-layer-popover: 1120;")
    expect(stylesheet).to include("--notae-layer-popover-floating: 1160;")
    expect(stylesheet).to include("--notae-layer-modal: 1200;")
    expect(stylesheet).to include("--notae-layer-flash: 1400;")
  end

  it "lifts open page and grid header tool menus above the title layer" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-page-header-tools:has(.notae-page-header-action[open]),\n.notae-page-header-tools:has(.notae-cover-picker[open]),\n.notae-page-header-tools:has(.notae-comments-menu[open]),\n.notae-db-header-tools:has(.notae-page-header-action[open]),\n.notae-db-header-tools:has(.notae-cover-picker[open]),\n.notae-db-header-tools:has(.notae-comments-menu[open]) {\n  position: relative;\n  z-index: var(--notae-layer-popover-parent);\n  isolation: isolate;\n}")
  end

  it "pushes overlapping title icons high into the cover area" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-page-icon-display.is-over-cover {\n  margin-top: calc(-1.18 * var(--notae-title-icon-size));")
    expect(stylesheet).to include("@media (max-width: 760px) {\n  .notae-emoji-picker-section .notae-page-emoji-grid {\n    grid-template-columns: repeat(6, minmax(0, 1fr));\n  }\n\n  .notae-page-icon-display.is-over-cover {\n    margin-top: calc(-1 * var(--notae-title-icon-size));")
  end

  it "styles quote blocks as larger serif pull quotes with a left rule" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-doc-editor.is-blockquote .ProseMirror {\n  margin: 0 0.85rem 0 0.65rem;\n  padding: 0.14rem 0 0.14rem 0.95rem;\n  border-left: 3px solid color-mix(in srgb, #78716c 58%, #d6d3d1);\n  color: rgba(68, 64, 60, 0.7);\n  font-family: Georgia, \"Times New Roman\", serif;\n  font-size: 1.3em;\n  font-style: italic;")
    expect(stylesheet).to include(".notae-doc-editor.is-blockquote .ProseMirror blockquote {\n  margin: 0;\n}")
  end

  it "styles heading 4 as a distinct smaller heading with muted emphasis" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-doc-editor.is-heading-4 .ProseMirror {\n  font-size: 1.08rem;\n  font-weight: 700;\n  color: rgba(68, 64, 60, 0.8);\n}")
  end

  it "restores the collapsed ai rail before turbo swaps the next shell into place" do
    application_js = Rails.root.join("app/javascript/application.js").read

    expect(application_js).to include('const AI_RAIL_COLLAPSED_CLASS = "is-ai-rail-collapsed"')
    expect(application_js).to include('syncAiRailCollapsedState(document)')
    expect(application_js).to include('document.addEventListener("turbo:before-render", (event) => {')
    expect(application_js).to include("syncAiRailCollapsedState(newBody)")
  end

  it "creates child tabs without surfacing them as standalone sidebar items" do
    owner = User.create!(email: "pages-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Knowledge", slug: "knowledge")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    parent = Page.create!(workspace: workspace, created_by: owner, title: "Parent Page")
    sign_in owner

    post pages_path(workspace_slug: workspace.slug), params: { page: { title: "Child Page", parent_page_id: parent.id } }

    expect(response).to have_http_status(:redirect)
    get workspace_path(workspace.slug)
    expect(response.body).to include("Parent Page")
    expect(response.body).not_to include("Child Page")
  end

  it "shows a default tab for a top-level page before any child tabs exist" do
    owner = User.create!(email: "pages-default-tab-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Default tabs", slug: "default-tabs")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Original note")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    labels = html.css(".notae-page-tabs .notae-page-tab-label").map(&:text).map(&:strip)
    active_link = html.at_css(%(.notae-page-tab.is-active[href="#{page_path(workspace_slug: workspace.slug, id: page.id)}"]))

    expect(labels).to eq([ "Tab 1" ])
    expect(active_link).to be_present
    expect(html.at_css(".notae-page-tab-create-form input[name='page[parent_page_id]']")["value"]).to eq(page.id)
  end

  it "renames the first nota tab without changing the document title" do
    owner = User.create!(email: "pages-root-tab-rename-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Root tab rename", slug: "root-tab-rename")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Client brief")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: {
            return_to: page_path(workspace_slug: workspace.slug, id: page.id),
            page: { root_tab_title: "Overview" }
          }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.reload.title).to eq("Client brief")
    expect(page.root_tab_title).to eq("Overview")

    get page_path(workspace_slug: workspace.slug, id: page.id)

    html = Nokogiri::HTML(response.body)
    expect(html.css(".notae-page-tab-label").map(&:text).map(&:strip)).to eq([ "Overview" ])
    expect(html.at_css(".notae-page-title-input")&.text&.strip).to eq("Client brief")
  end

  it "renders top-of-page tabs under the parent title for sibling notes and linked grids" do
    owner = User.create!(email: "pages-tabs-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page tabs", slug: "page-tabs")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    group_page = Page.create!(workspace: workspace, created_by: owner, title: "Project")
    note_tab = Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Research")
    grid_tab_page = Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Tasks anchor")
    grid_tab = Database.create!(workspace: workspace, created_by: owner, name: "Sprint Grid", linked_page: grid_tab_page)
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: note_tab.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    labels = html.css(".notae-page-tabs .notae-page-tab-label").map(&:text).map(&:strip)
    title_input = html.at_css(".notae-page-title-input")

    expect(labels).to eq([ "Tab 1", note_tab.title, grid_tab_page.title ])
    expect(title_input["aria-label"]).to eq("Page title")
    expect(title_input.text.strip).to eq(group_page.title)
    expect(html.at_css(%(.notae-page-tab[href="#{page_path(workspace_slug: workspace.slug, id: group_page.id)}"]))).to be_present
    expect(html.at_css(%(.notae-page-tab[href="#{page_path(workspace_slug: workspace.slug, id: note_tab.id)}"]))).to be_present
    expect(html.at_css(%(.notae-page-tab[href="#{database_path(workspace_slug: workspace.slug, id: grid_tab.id)}"]))).to be_present
    expect(html.at_css(".notae-page-tab-create-form input[name='page[parent_page_id]']")["value"]).to eq(group_page.id)
  end

  it "keeps the parent shell visible while switching context into a child tab" do
    owner = User.create!(email: "pages-shell-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Shell tabs", slug: "shell-tabs")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    group_page = Page.create!(
      workspace: workspace,
      created_by: owner,
      title: "Main document",
      icon: "🌿",
      cover_preset_key: Page::COVER_PRESET_KEYS.first
    )
    child_tab = Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Draft tab")
    sibling_tab = Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Second tab")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: child_tab.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    shell_titles = html.css(".notae-page-title-input").map(&:text).map(&:strip)
    tab_shells = html.css(".notae-page-tab-shell")
    tab_labels = html.css(".notae-page-tab-label").map(&:text).map(&:strip)

    expect(shell_titles).to include(group_page.title)
    expect(html.at_css(".notae-page-icon-display")&.text&.strip).to eq(group_page.icon)
    expect(html.at_css(".notae-page-cover-preset")).to be_present
    expect(tab_labels).to eq([ "Tab 1", child_tab.title, sibling_tab.title ])
    expect(tab_shells).not_to be_empty
    expect(tab_shells.all? { |node| node.at_css(".notae-page-tab-menu-trigger").present? }).to be(true)
    expect(html.at_css(%(.notae-page-tab.is-active[href="#{page_path(workspace_slug: workspace.slug, id: child_tab.id)}"]))).to be_present
  end

  it "redirects a new tab into the child context while preserving the parent shell" do
    owner = User.create!(email: "pages-new-tab-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "New child tab", slug: "new-child-tab")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    group_page = Page.create!(
      workspace: workspace,
      created_by: owner,
      title: "Parent shell",
      icon: "🧠",
      cover_preset_key: Page::COVER_PRESET_KEYS.first
    )
    sign_in owner

    post pages_path(workspace_slug: workspace.slug),
         params: { page: { title: "New tab", parent_page_id: group_page.id } }

    created_tab = workspace.pages.find_by!(parent_page: group_page, title: "New tab")
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: created_tab.id))
    expect(created_tab.icon).to eq(group_page.icon)
    expect(created_tab.cover_preset_key).to eq(group_page.cover_preset_key)

    get page_path(workspace_slug: workspace.slug, id: created_tab.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css(".notae-page-title-input")&.text&.strip).to eq(group_page.title)
    expect(html.at_css(".notae-page-icon-display")&.text&.strip).to eq(group_page.icon)
    expect(html.at_css(".notae-page-cover-preset")).to be_present
    expect(html.at_css(%(.notae-page-tab.is-active[href="#{page_path(workspace_slug: workspace.slug, id: created_tab.id)}"]))).to be_present
  end

  it "inherits an uploaded cover image and icon for a new child tab" do
    owner = User.create!(email: "pages-new-tab-upload-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "New child tab upload", slug: "new-child-tab-upload")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    group_page = Page.create!(
      workspace: workspace,
      created_by: owner,
      title: "Parent shell",
      icon: "🌅"
    )

    Tempfile.create([ "tab-parent-cover", ".png" ]) do |file|
      file.write("fake-png-content")
      file.rewind
      group_page.cover_image.attach(io: file, filename: "parent-cover.png", content_type: "image/png")
    end

    sign_in owner

    post pages_path(workspace_slug: workspace.slug),
         params: { page: { title: "New tab", parent_page_id: group_page.id } }

    created_tab = workspace.pages.find_by!(parent_page: group_page, title: "New tab")

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: created_tab.id))
    expect(created_tab.icon).to eq(group_page.icon)
    expect(created_tab.cover_image).to be_attached
    expect(created_tab.cover_image.blob_id).to eq(group_page.cover_image.blob_id)
  end

  it "marks the current child page tab as active" do
    owner = User.create!(email: "pages-active-tab-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Active tabs", slug: "active-tabs")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    group_page = Page.create!(workspace: workspace, created_by: owner, title: "Product")
    active_tab = Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Specs")
    Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Notes")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: active_tab.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    active_link = html.at_css(".notae-page-tabs .notae-page-tab.is-active .notae-page-tab-label")

    expect(active_link).to be_present
    expect(active_link.text.strip).to eq(active_tab.title)
    expect(html.at_css(".notae-page-tab-create-form input[name='page[parent_page_id]']")["value"]).to eq(group_page.id)
  end

  it "renames and recolors a tab without leaving the current page" do
    owner = User.create!(email: "pages-rename-tab-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Rename tabs", slug: "rename-tabs")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    group_page = Page.create!(workspace: workspace, created_by: owner, title: "Project Alpha")
    target_tab = Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Draft")
    current_tab = Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Current")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: target_tab.id),
          params: {
            return_to: page_path(workspace_slug: workspace.slug, id: current_tab.id),
            page: { title: "Released", tab_color: "purple" }
          }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: current_tab.id))
    expect(target_tab.reload.title).to eq("Released")
    expect(target_tab.tab_color).to eq("purple")
    expect(target_tab.parent_page_id).to eq(group_page.id)
  end

  it "shows markdown and pdf exports without the zip action in the options menu" do
    owner = User.create!(email: "pages-export-menu-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Export menu", slug: "export-menu")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Export menu page")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id, options_menu: "open")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-lazy-panel-url-value")
    expect(response.body).to include("panels/options")
    expect(response.body).not_to include("Build ZIP")

    get panel_page_path(workspace_slug: workspace.slug, id: page.id, panel: "options")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Markdown")
    expect(response.body).to include("PDF")
    expect(response.body).not_to include("Build ZIP")
  end

  it "archives a tab and clears any linked grid association" do
    owner = User.create!(email: "pages-delete-tab-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Delete tabs", slug: "delete-tabs")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    group_page = Page.create!(workspace: workspace, created_by: owner, title: "Ops")
    tab_page = Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Tracker")
    database = Database.create!(workspace: workspace, created_by: owner, name: "Tracker grid", linked_page: tab_page)
    sign_in owner

    patch remove_tab_page_path(workspace_slug: workspace.slug, id: tab_page.id),
          params: { return_to: page_path(workspace_slug: workspace.slug, id: group_page.id) }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: group_page.id))
    expect(tab_page.reload).to be_archived
    expect(database.reload.linked_page).to be_nil
  end

  it "returns to the surviving parent grid after deleting an active child grid tab" do
    owner = User.create!(email: "pages-delete-grid-tab-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Delete grid tab fallback", slug: "delete-grid-tab-fallback")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    parent_database = Database.create!(workspace: workspace, created_by: owner, name: "Tasks")
    Databases::EnsureLinkedPageService.call(database: parent_database, actor: owner)
    child_tab_page = Page.create!(
      workspace: workspace,
      parent_page: parent_database.linked_page,
      created_by: owner,
      title: "Later sprint"
    )
    child_database = Database.create!(
      workspace: workspace,
      created_by: owner,
      name: "Later sprint grid",
      linked_page: child_tab_page
    )
    sign_in owner

    patch remove_tab_page_path(workspace_slug: workspace.slug, id: child_tab_page.id),
          params: { return_to: database_path(workspace_slug: workspace.slug, id: child_database.id) }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: parent_database.id))
    expect(child_tab_page.reload).to be_archived
    expect(child_database.reload.linked_page).to be_nil
  end

  it "hides archived pages from workspace sidebar" do
    owner = User.create!(email: "pages-archive-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Private", slug: "private")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Archive me")
    sign_in owner

    patch archive_page_path(workspace_slug: workspace.slug, id: page.id)
    get workspace_path(workspace.slug)

    expect(response.body).not_to include("Archive me")
  end

  it "supports page-level permission overrides: private, workspace, specific users" do
    owner = User.create!(email: "page-perms-owner@example.com", password: "password123")
    member = User.create!(email: "page-perms-member@example.com", password: "password123")
    outsider = User.create!(email: "page-perms-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Perms", slug: "perms")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: outsider, role: :member)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Visibility Doc")

    sign_in owner
    patch permissions_page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { permission_mode: "private_page" } }
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(AuditEvent.recent_first.first.action).to eq("share")

    sign_out owner
    sign_in member
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:not_found)

    sign_out member
    sign_in owner
    patch permissions_page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { permission_mode: "shared_to_workspace" } }
    sign_out owner
    sign_in member
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:ok)

    sign_out member
    sign_in owner
    patch permissions_page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { permission_mode: "specific_users", shared_user_ids: [ member.id ] } }
    sign_out owner

    sign_in member
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:ok)

    sign_out member
    sign_in outsider
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:not_found)
  end

  it "blocks cross-workspace page access attempts" do
    owner = User.create!(email: "page-owner-cross@example.com", password: "password123")
    intruder = User.create!(email: "page-intruder-cross@example.com", password: "password123")
    workspace = Workspace.create!(name: "Cross", slug: "cross")
    other_workspace = Workspace.create!(name: "Other", slug: "other")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: intruder, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Protected")

    sign_in intruder
    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:not_found)
  end

  it "renders global shortcut UI containers on page view" do
    owner = User.create!(email: "page-shortcuts-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Shortcuts", slug: "shortcuts")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Shortcuts page")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-shell is-layout-hydrating")
    expect(response.body).to include("notae-sidebar-scroll")
    expect(response.body).to include("notae-content-scroll")
    expect(response.body).to include("notae-ai-rail")
    expect(response.body).to include("Quick switcher")
    expect(response.body).to include("Keyboard shortcuts")
    expect(response.body).to include("Cmd/Ctrl + K")
  end

  it "renders the create workspace dialog outside the sidebar container" do
    owner = User.create!(email: "page-workspace-dialog-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Workspace dialog", slug: "workspace-dialog")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Workspace dialog page")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    shell = html.at_css(".notae-shell")
    sidebar = html.at_css("aside.notae-sidebar")
    workspace_dialog = html.at_css("[data-shell-target='workspaceDialog']")

    expect(shell).to be_present
    expect(sidebar).to be_present
    expect(workspace_dialog).to be_present
    expect(workspace_dialog.parent).to eq(shell)
    expect(sidebar.at_css("[data-shell-target='workspaceDialog']")).to be_nil
  end

  it "renders mobile-ready page header action labels for icon-only controls" do
    owner = User.create!(email: "page-mobile-header-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Mobile page header", slug: "mobile-page-header")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Mobile page header")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('aria-label="Add icon"')
    expect(response.body).to include('aria-label="Add cover"')
    expect(response.body).to include('aria-label="Add comment"')
    expect(response.body).to include('class="notae-page-header-action-label"')
    expect(response.body).to include('class="notae-page-header-link-label"')
  end

  it "keeps mobile page titles wrapping and topbar menus mutually exclusive" do
    owner = User.create!(email: "page-mobile-title-wrap-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Mobile title wrap", slug: "mobile-title-wrap")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "A deliberately long mobile page title that should wrap cleanly")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    title_field = html.at_css("textarea.notae-page-title-input[name='page[title]']")

    expect(title_field).to be_present
    expect(title_field["wrap"]).not_to eq("off")
    expect(response.body).to include('data-action="toggle->shell#syncTopbarMenus lazy-panel:loaded->actions-menu#refresh"')
    expect(response.body).to include('data-action="toggle->shell#syncTopbarMenus lazy-panel:loaded->options-menu#refresh"')
    expect(response.body).to include('data-action="toggle->shell#syncTopbarMenus"')

    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-page-title-input {\n  height: auto;\n  min-height: calc(1.1em + 0.22rem);\n  white-space: normal;\n  overflow-wrap: anywhere;\n  word-break: break-word;\n}")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-doc-editor:not(.is-code-block) .ProseMirror {\n  max-width: 100%;\n  overflow-wrap: anywhere;\n  word-break: break-word;\n}")
    expect(stylesheet).to include(".notae-actions-mobile-nav-button-label {\n  flex: 1 1 auto;\n  display: block;\n  min-width: 0;\n  white-space: normal;\n  overflow-wrap: anywhere;\n  word-break: break-word;\n  line-height: 1.3;\n  color: inherit;\n  -webkit-text-fill-color: currentColor;\n}")
    expect(stylesheet).to include(".notae-options-mobile-nav-button-label {\n  flex: 1 1 auto;\n  display: block;\n  min-width: 0;\n  white-space: normal;\n  overflow-wrap: anywhere;\n  word-break: break-word;\n  line-height: 1.3;\n  color: inherit;\n  -webkit-text-fill-color: currentColor;\n}")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-actions-panel {\n  position: fixed;\n  left: auto;\n  right: 0.5rem;\n  top: calc(env(safe-area-inset-top, 0px) + 3.05rem);\n  width: min(17rem, calc(100vw - 1.5rem));")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-options-panel {\n  position: fixed;\n  left: auto;\n  right: 0.5rem;\n  top: calc(env(safe-area-inset-top, 0px) + 3.05rem);\n  width: min(17rem, calc(100vw - 1.5rem));")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-actions-panel.is-mobile-drilldown .notae-actions-mobile-panes {\n  display: grid;\n  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);\n  width: 200%;")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-options-panel.is-mobile-drilldown .notae-options-mobile-panes {\n  display: grid;\n  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);\n  width: 200%;")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-actions-panel.is-mobile-drilldown {\n  display: block;\n  overflow-x: clip;\n  overflow-y: auto;\n}")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-options-panel.is-mobile-drilldown {\n  display: block;\n  overflow-x: clip;\n  overflow-y: auto;\n}")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-actions-panel.is-mobile-drilldown .notae-actions-mobile-pane {\n  display: block;\n  min-width: 0;\n  max-width: 100%;\n  box-sizing: border-box;\n  overflow-x: hidden;\n}")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-options-panel.is-mobile-drilldown .notae-options-mobile-pane {\n  display: block;\n  min-width: 0;\n  max-width: 100%;\n  box-sizing: border-box;\n  overflow-x: hidden;\n}")
    expect(stylesheet).to include(".notae-block-menu-panel {\n  position: absolute;")
    expect(stylesheet).to include("  overscroll-behavior: contain;\n  -webkit-overflow-scrolling: touch;\n")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-block-menu-panel {\n  width: min(340px, calc(100vw - 1rem));")
    expect(stylesheet).to include("  touch-action: pan-y;\n}")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport.is-block-menu-open .notae-content-scroll {\n  overflow: hidden;\n  overscroll-behavior: none;\n}")
  end

  it "ships dark-theme editor overrides so focused nota text stays readable" do
    owner = User.create!(
      email: "page-dark-editor-owner@example.com",
      password: "password123",
      theme_preference: "dark"
    )
    workspace = Workspace.create!(name: "Dark editor", slug: "dark-editor")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Dark editor page")
    Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-theme-dark")
    document = Nokogiri::HTML.parse(response.body)
    expect(document.at_css(".notae-doc-editor")).to be_present

    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read
    expect(stylesheet).to include("body.notae-theme-dark .notae-doc-block.is-focused .notae-doc-editor .ProseMirror")
    expect(stylesheet).to include("body.notae-theme-dark .notae-doc-editor.is-callout .ProseMirror")
    expect(stylesheet).to include("body.notae-theme-dark .notae-doc-editor.is-color-blue .ProseMirror")
    expect(stylesheet).to include("body.notae-theme-system .notae-doc-block.is-focused .notae-doc-editor .ProseMirror")
  end

  it "keeps topbar menus above page cover controls" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-page-cover-controls {\n  position: absolute;")
    expect(stylesheet).to include("  z-index: var(--notae-layer-popover-region);")
    expect(stylesheet).to include(".notae-topbar:has(.notae-actions-menu[open]),\n.notae-topbar:has(.notae-options-menu[open]),\n.notae-topbar:has(.notae-comments-menu[open]) {\n  position: relative;\n  z-index: var(--notae-layer-popover-parent);")
  end

  it "uses darker label text for primary buttons in dark themes" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include("body.notae-theme-dark button[type=\"submit\"].notae-chip-button,\nbody.notae-theme-dark input[type=\"submit\"].notae-chip-button,\nbody.notae-theme-dark .notae-db-toolbar-new,\nbody.notae-theme-dark .notae-ai-compose button,\nbody.notae-theme-dark .notae-auth-submit {\n  color: #2b3437;")
    expect(stylesheet).to include("body.notae-theme-system button[type=\"submit\"].notae-chip-button,\n  body.notae-theme-system input[type=\"submit\"].notae-chip-button,\n  body.notae-theme-system .notae-db-toolbar-new,\n  body.notae-theme-system .notae-ai-compose button,\n  body.notae-theme-system .notae-auth-submit {\n    color: #2b3437;")
  end

  it "uses high-contrast hover text for dark topbar menus" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include("body.notae-theme-dark .notae-actions-row:not(.is-disabled) .notae-actions-row-button:hover,\nbody.notae-theme-dark .notae-actions-row:not(.is-disabled) .notae-actions-row-button:focus-visible,\nbody.notae-theme-dark .notae-actions-row:not(.is-disabled) .notae-actions-row-link:hover,\nbody.notae-theme-dark .notae-actions-row:not(.is-disabled) .notae-actions-row-link:focus-visible {\n  background: #262d35;\n  color: var(--notae-text-strong);")
    expect(stylesheet).to include("body.notae-theme-dark .notae-options-list-item:is(:hover, :focus-within) {\n  background: #242a31;\n  border-color: #36404b;\n  color: var(--notae-text-strong);")
    expect(stylesheet).to include("  body.notae-theme-system .notae-actions-row:not(.is-disabled) .notae-actions-row-button:hover,\n  body.notae-theme-system .notae-actions-row:not(.is-disabled) .notae-actions-row-button:focus-visible,\n  body.notae-theme-system .notae-actions-row:not(.is-disabled) .notae-actions-row-link:hover,\n  body.notae-theme-system .notae-actions-row:not(.is-disabled) .notae-actions-row-link:focus-visible {\n    background: #262d35;\n    color: var(--notae-text-strong);")
  end

  it "includes the compiled app stylesheet and keeps the tailwind entrypoint present" do
    tailwind_entrypoint = Rails.root.join("app/assets/tailwind/application.css")
    expect(tailwind_entrypoint).to exist
    expect(tailwind_entrypoint.read).to include('@import "tailwindcss";')

    owner = User.create!(email: "page-tailwind-layout-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tailwind layout", slug: "tailwind-layout")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Page.create!(workspace: workspace, created_by: owner, title: "Tailwind page")
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(%r{href="[^"]*/assets/application[^"]*\.css"})
  end

  it "renders sidebar create menu with Nota, grid, meeting, and workspace options plus icons" do
    owner = User.create!(email: "page-sidebar-create-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Sidebar create", slug: "sidebar-create")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Page.create!(workspace: workspace, created_by: owner, title: "Landing")
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("New Nota")
    expect(response.body).to include("New grid")
    expect(response.body).to include("New meeting")
    expect(response.body).to include("New Workspace")
    expect(response.body).to include("notae-create-menu")
    expect(response.body).to include("notae-create-menu-button")
    expect(response.body).to include("notae-create-menu-icon-page")
    expect(response.body).to include("notae-create-menu-icon-database")
    expect(response.body).to include("notae-create-menu-icon-meeting")
    expect(response.body).to include("notae-create-menu-icon-workspace")
    expect(response.body).to include("data-shell-target=\"workspaceDialog\"")
  end

  it "renders iconized sidebar links and collapsed dock quick links" do
    owner = User.create!(email: "page-sidebar-icon-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Sidebar icons", slug: "sidebar-icons")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-sidebar-link-content")
    expect(response.body).to include("notae-sidebar-nav-icon")
    expect(response.body).to include("notae-sidebar-link-label\">Home")
    expect(response.body).to include("notae-sidebar-link-label\">Kalendārium")
    expect(response.body).to include("notae-sidebar-link-label\">Meetings")
    expect(response.body).to include("notae-sidebar-link-label\">AI Conversation History")
    expect(response.body).to include("notae-sidebar-link-label\">Settings")
    expect(response.body).to include("notae-sidebar-link-label\">Trash")

    doc = Nokogiri::HTML.parse(response.body)
    dock_links = doc.css(".notae-sidebar-dock-link")
    expect(dock_links.size).to be >= 7
    expect(dock_links.map { |link| link["title"] }).to include("Home", "Search", "Library", "Kalendārium", "Meetings", "Settings")
    expect(dock_links).to all(satisfy { |link| link["data-turbo-prefetch"] == "false" })
    expect(doc.css(".notae-sidebar-link[href]")).to all(satisfy { |link| link["data-turbo-prefetch"] == "false" })
  end

  it "renders the mobile tabbar with primary workspace navigation links" do
    owner = User.create!(email: "page-mobile-tabbar-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Mobile nav", slug: "mobile-nav")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)

    doc = Nokogiri::HTML.parse(response.body)
    mobile_tabbar = doc.at_css(".notae-mobile-tabbar")
    expect(mobile_tabbar).to be_present

    tabbar_links = mobile_tabbar.css(".notae-mobile-tabbar-link[href]")
    expect(tabbar_links.map { |link| link.text.strip }).to include("Home", "Search", "Calendar", "Mail", "Library")
    expect(tabbar_links.map { |link| link["href"] }).to include(
      workspace_path(workspace.slug),
      workspace_search_path(workspace_slug: workspace.slug),
      kalendarium_path(workspace_slug: workspace.slug),
      workspace_epistularium_path(workspace_slug: workspace.slug),
      workspace_library_path(workspace_slug: workspace.slug)
    )
    expect(tabbar_links).to all(satisfy { |link| link["data-turbo-prefetch"] == "false" })
  end

  it "lists only explicit meeting-note pages in the sidebar meetings section" do
    owner = User.create!(email: "page-sidebar-meeting-kind-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Sidebar meeting kind", slug: "sidebar-meeting-kind")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Page.create!(workspace: workspace, created_by: owner, title: "Weekly meeting notes", page_kind: "meeting_note")
    Page.create!(workspace: workspace, created_by: owner, title: "Meeting prep checklist", page_kind: "nota")
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    get workspace_sidebar_sections_path(workspace_slug: workspace.slug)
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.parse(response.body)
    meetings_section = document.css(".notae-sidebar-section").find { |section| section.at_css(".notae-sidebar-label")&.text.to_s.strip == "Meetings" }
    expect(meetings_section).to be_present
    section_text = meetings_section.text
    expect(section_text).to include("Weekly meeting notes")
    expect(section_text).not_to include("Meeting prep checklist")
  end

  it "keeps create redirects working even if another workspace has a blank slug" do
    owner = User.create!(email: "page-create-blank-slug-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Create target", slug: "create-target")
    stale_workspace = Workspace.create!(name: "Stale workspace", slug: "stale-workspace")
    stale_workspace.update_column(:slug, "")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: stale_workspace, user: owner, role: :owner)
    sign_in owner

    post pages_path(workspace_slug: workspace.slug), params: { page: { title: "Created from menu" } }

    created_page = Page.order(created_at: :desc).first
    expect(created_page.title).to eq("Created from menu")
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: created_page.id))

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Created from menu")
  end

  it "renders grids in the sidebar with each grid icon appended to the title" do
    owner = User.create!(email: "page-sidebar-grid-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Sidebar grids", slug: "sidebar-grids")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Database.create!(workspace: workspace, name: "Campaign grid", icon: "🧠")
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Grids")

    get workspace_sidebar_sections_path(workspace_slug: workspace.slug)
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    grid_link = html.css(".notae-sidebar-section").find do |section|
      section.text.include?("Grids")
    end&.at_css("a[href='#{database_path(workspace_slug: workspace.slug, id: workspace.databases.first.id)}']")

    expect(grid_link).to be_present
    expect(grid_link.at_css(".notae-sidebar-page-title")&.text&.squish).to include("Campaign grid")
    expect(grid_link.at_css(".notae-icon-renderer-glyph")&.text&.strip).to eq("🧠")
  end

  it "renders collapsible sidebar sections with inline create actions where supported" do
    owner = User.create!(email: "page-sidebar-sections-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Sidebar sections", slug: "sidebar-sections")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Page.create!(workspace: workspace, created_by: owner, title: "Alpha note")
    Page.create!(workspace: workspace, created_by: owner, title: "Weekly meeting notes", page_kind: "meeting_note")
    Database.create!(workspace: workspace, name: "Projects")
    Workspace.create!(name: "Secondary workspace", slug: "secondary-workspace")
    Favorite.create!(user: owner, workspace: workspace, favoritable: workspace.pages.find_by!(title: "Alpha note"))
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.parse(response.body)

    {
      "Workspaces" => "#{workspace.slug}:workspaces",
      "Notarum" => "#{workspace.slug}:notarum",
      "Grids" => "#{workspace.slug}:grids",
      "Meetings" => "#{workspace.slug}:meetings",
      "Favorites" => "#{workspace.slug}:favorites"
    }.each do |label, key|
      section = document.css(".notae-sidebar-section").find do |node|
        node.at_css(".notae-sidebar-label")&.text.to_s.strip == label
      end
      expect(section).to be_present
      expect(section["data-controller"]).to include("sidebar-section")
      expect(section["data-sidebar-section-key-value"]).to eq(key)

      toggle = section.at_css(".notae-sidebar-section-toggle")
      expect(toggle).to be_present
      expect(toggle["data-action"]).to include("sidebar-section#toggle")
      expect(toggle["aria-expanded"]).to eq("true")
      expect(toggle.at_css(".notae-sidebar-section-chevron")&.text.to_s).to include("▾")

      create_button = section.at_css("button.notae-sidebar-section-create")
      if [ "Favorites" ].include?(label)
        expect(create_button).to be_nil
      else
        expect(create_button).to be_present
        expect(create_button.text).to eq("[+]")
      end
    end

    workspaces_section = document.css(".notae-sidebar-section").find { |node| node.at_css(".notae-sidebar-label")&.text.to_s.strip == "Workspaces" }
    workspaces_create_button = workspaces_section.at_css("button.notae-sidebar-section-create")
    expect(workspaces_create_button["data-action"]).to include("shell#openWorkspaceDialog")

    notes_section = document.css(".notae-sidebar-section").find { |node| node.at_css(".notae-sidebar-label")&.text.to_s.strip == "Notarum" }
    expect(notes_section.at_css("input[name='page[title]']")["value"]).to eq("Untitled")

    grids_section = document.css(".notae-sidebar-section").find { |node| node.at_css(".notae-sidebar-label")&.text.to_s.strip == "Grids" }
    expect(grids_section.at_css("input[name='quick_create']")["value"]).to eq("1")
    expect(grids_section.at_css("input[name='database[name]']")["value"]).to eq("Untitled grid")

    meetings_section = document.css(".notae-sidebar-section").find { |node| node.at_css(".notae-sidebar-label")&.text.to_s.strip == "Meetings" }
    expect(meetings_section.at_css("input[name='page[title]']")["value"]).to eq("Meeting notes")
    expect(meetings_section.at_css("input[name='page[page_kind]']")["value"]).to eq("meeting_note")

    get workspace_sidebar_sections_path(workspace_slug: workspace.slug)
    expect(response).to have_http_status(:ok)
    favorites_document = Nokogiri::HTML.parse(response.body)
    favorites_section = favorites_document.css(".notae-sidebar-section").find { |node| node.at_css(".notae-sidebar-label")&.text.to_s.strip == "Favorites" }
    expect(favorites_section.text).to include("Alpha note")
  end

  it "renders a document-first page canvas with topbar options menu" do
    owner = User.create!(email: "page-document-layout-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Document layout", slug: "document-layout")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "New page")
    parent_block = page.blocks.create!(workspace: workspace, created_by: owner, block_type: "paragraph")
    page.blocks.create!(workspace: workspace, created_by: owner, parent_block: parent_block, block_type: "todo_list")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Options")
    expect(response.body).to include("Actions")
    expect(response.body).to include("notae-actions-menu")
    expect(response.body).to include("notae-doc-canvas")
    expect(response.body).to include("notae-page-title-input")
    expect(response.body).to include("Turn into")
    expect(response.body).to include("Block equation")
    expect(response.body).to include("Synced block")
    expect(response.body).to include("Heading 4")
    expect(response.body).not_to include("Toggle heading 1")
    expect(response.body).not_to include("Toggle heading 2")
    expect(response.body).not_to include("Toggle heading 3")

    html = Nokogiri::HTML(response.body)
    title_field = html.at_css("textarea.notae-page-title-input[name='page[title]']")
    expect(title_field).to be_present
    expect(title_field["rows"]).to eq("1")
    expect(html.css("form.notae-doc-add-form").size).to eq(1)
    expect(html.at_css("form.notae-doc-add-form.is-child")).to be_nil
  end

  it "renders embedded page previews without full page chrome and keeps block actions embedded" do
    owner = User.create!(email: "page-embedded-preview-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Embedded page preview", slug: "embedded-page-preview")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Embedded page")
    block = page.blocks.create!(workspace: workspace, created_by: owner, block_type: "paragraph")
    page.update!(icon: "📘", cover_preset_key: Page::COVER_PRESET_KEYS.first)
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id, embedded: 1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-shell-embedded")
    expect(response.body).not_to include("--notae-workspace-color:")
    expect(response.body).not_to include("notae-topbar")
    expect(response.body).not_to include("notae-actions-menu")
    expect(response.body).not_to include("notae-options-menu")
    expect(response.body).not_to include("notae-page-cover")
    expect(response.body).not_to include("notae-doc-header")
    expect(response.body).not_to include("notae-page-title-input")
    expect(response.body).not_to include("notae-doc-backlinks")
    expect(response.body).not_to include("Change cover")
    expect(response.body).not_to include("notae-doc-add-form")
    expect(response.body).not_to include("notae-doc-handle")
    expect(response.body).not_to include("notae-block-menu-trigger")

    document = Nokogiri::HTML.parse(response.body)
    expect(document.css("form.notae-doc-add-form")).to be_empty
    expect(document.css(".notae-doc-handle")).to be_empty
    expect(document.css(".notae-block-menu-trigger")).to be_empty
    expect(response.body).to include(page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id, embedded: 1))
    expect(response.body).not_to include(command_page_block_path(workspace_slug: workspace.slug, page_id: page.id, id: block.id, embedded: 1))
  end

  it "truncates split pane titles and keeps split controls visible" do
    owner = User.create!(email: "page-split-pane-title-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page split pane title", slug: "page-split-pane-title")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    host_page = Page.create!(workspace: workspace, created_by: owner, title: "Host page")
    linked_page = Page.create!(workspace: workspace, created_by: owner, title: "Linked grid shell")
    database_name = "This grid title should truncate after thirty characters"
    database = Database.create!(workspace: workspace, name: database_name, linked_page: linked_page)
    sign_in owner

    get page_path(
      workspace_slug: workspace.slug,
      id: host_page.id,
      split_page_id: linked_page.id,
      split_source: "block"
    )

    expect(response).to have_http_status(:ok)

    html = Nokogiri::HTML.parse(response.body)
    split_title = html.at_css(".notae-db-split-pane-title")
    expect(split_title).to be_present
    expect(split_title["title"]).to eq(database_name)
    expect(split_title.text.squish).to include(ActionController::Base.helpers.truncate(database_name, length: 30))

    split_actions = html.at_css(".notae-db-split-pane-actions")
    expect(split_actions).to be_present
    expect(split_actions.text).to include("Open full")
    expect(split_actions.at_css("a[title='Close side peek']")).to be_present
    open_full_link = split_actions.at_css("a.notae-chip-button")
    expect(open_full_link).to be_present
    expect(open_full_link["href"]).to eq(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(open_full_link["target"]).to be_nil

    split_frame = html.at_css(".notae-db-split-frame")
    expect(split_frame).to be_present
    expect(split_frame["src"]).to eq(database_path(workspace_slug: workspace.slug, id: database.id, embedded: "1"))
  end

  it "keeps embedded page redirects when creating blocks from split previews" do
    owner = User.create!(email: "page-embedded-block-create-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Embedded block create", slug: "embedded-block-create")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Embedded block page")
    sign_in owner

    expect do
      post page_blocks_path(workspace_slug: workspace.slug, page_id: page.id, embedded: 1),
           params: { block: { block_type: "paragraph" } }
    end.to change { page.blocks.count }.by(1)

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id, embedded: 1))
  end

  it "updates actions settings on a page and duplicates the page with blocks" do
    owner = User.create!(email: "page-actions-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Actions", slug: "actions")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Action page")
    page.blocks.create!(workspace: workspace, created_by: owner, block_type: "paragraph")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: {
            page: {
              font_style: "mono",
              small_text: "true",
              full_width: "true",
              suggest_edits: "true",
              locked: "true"
            }
          }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.reload.font_style).to eq("mono")
    expect(page.small_text).to be(true)
    expect(page.full_width).to be(true)
    expect(page.suggest_edits).to be(true)
    expect(page.locked).to be(true)
    page.update!(root_tab_title: "Overview")

    expect do
      post duplicate_page_path(workspace_slug: workspace.slug, id: page.id)
    end.to change(Page, :count).by(1)
       .and change(Block, :count).by(1)

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: Page.order(:created_at).last.id))

    duplicated_page = Page.order(:created_at).last
    expect(duplicated_page.title).to eq("Action page (copy)")
    expect(duplicated_page.font_style).to eq("mono")
    expect(duplicated_page.root_tab_title).to eq("Overview")
    expect(duplicated_page.small_text).to be(true)
    expect(duplicated_page.full_width).to be(true)
    expect(duplicated_page.suggest_edits).to be(true)
    expect(duplicated_page.locked).to be(false)
    expect(duplicated_page.blocks.active.count).to eq(1)
  end

  it "keeps actions and options menus open when requested and renders options icon" do
    owner = User.create!(email: "page-menu-open-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Menu Open", slug: "menu-open")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Menu open page")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id, actions_menu: "open"),
          params: { page: { small_text: "true" } }
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id, actions_menu: "open"))
    follow_redirect!
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("#page-actions-menu[open]")).to be_present
    expect(response.body).to include('data-controller="actions-menu page-import lazy-panel"')
    expect(response.body).to include('data-controller="database-view-state page-collaboration"')
    expect(response.body).to include("data-lazy-panel-url-value")
    expect(response.body).not_to include("Current block as MD")
    expect(response.body).not_to include('href="/w/actions/pages/')
    expect(response.body).not_to include("Customize page")
    expect(response.body).not_to include("Turn into wiki")
    expect(response.body).not_to include("Open in Mac app")

    patch permissions_page_path(workspace_slug: workspace.slug, id: page.id, options_menu: "open"),
          params: { page: { permission_mode: "shared_to_workspace" } }
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id, options_menu: "open"))
    follow_redirect!
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("#page-options-menu[open]")).to be_present
    expect(response.body).to include("⚙")
    expect(response.body).to include('data-controller="options-menu lazy-panel"')
    expect(response.body).not_to include("Public share links")

    get panel_page_path(workspace_slug: workspace.slug, id: page.id, panel: "actions", current_path: page_path(workspace_slug: workspace.slug, id: page.id))
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Import")
    expect(response.body).to include("into Nota")
    expect(response.body).to include("Current block as MD")
    expect(response.body).to include("Version history")

    get panel_page_path(workspace_slug: workspace.slug, id: page.id, panel: "options")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Permissions")
    expect(response.body).to include("Public share links")
    expect(response.body).to include("Templates")
  end

  it "updates page title from the clean page header" do
    owner = User.create!(email: "page-title-update-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Title update", slug: "title-update")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Untitled")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { title: "Project brief" } }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.reload.title).to eq("Project brief")
  end

  it "renders redirect notices in the local page flash host instead of the shell top" do
    owner = User.create!(email: "page-inline-flash-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Inline page flash", slug: "inline-page-flash")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Untitled")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { title: "Project brief" } }

    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    follow_redirect!

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("#page_flash_messages .notae-flash.notice")&.text&.strip).to eq("Page updated.")
    expect(html.at_css("#notae_flash_messages .notae-flash")).to be_nil
  end

  it "updates page title through json endpoint for autosave" do
    owner = User.create!(email: "page-title-json-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Title json", slug: "title-json")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Untitled")
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { title: "Autosaved title" } },
          as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["title"]).to eq("Autosaved title")
    expect(page.reload.title).to eq("Autosaved title")
  end
end
