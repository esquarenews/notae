require "rails_helper"

RSpec.describe "Import settings", type: :request do
  def uploaded_file(name, content)
    file = Tempfile.new([ File.basename(name, ".*"), File.extname(name) ])
    file.binmode
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/octet-stream", original_filename: name)
  end

  it "renders import settings with warning note about potential formatting loss" do
    owner = User.create!(email: "import-settings-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Import settings", slug: "import-settings")
    other_workspace = Workspace.create!(name: "Import settings alt", slug: "import-settings-alt")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: owner, role: :owner)
    sign_in owner

    get workspace_import_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Import")
    expect(response.body).to include("Format warning")
    expect(response.body).to include("some structure, styling")
    expect(response.body).to include("CSV files import as grids by default.")
    expect(response.body).to include('data-controller="import-status"')
    expect(response.body).to include('data-action="submit-&gt;import-status#validateSelection')
    expect(response.body).to include("Select files")
    expect(response.body).to include("Import ready")

    document = Nokogiri::HTML(response.body)
    file_input = document.at_css("#workspace_import_files")
    picker_label = document.at_css("label.notae-import-file-picker-button")
    expect(file_input["name"]).to eq("import[files][]")
    expect(file_input["data-import-status-target"]).to eq("fileInput")
    expect(picker_label["for"]).to eq("workspace_import_files")

    workspace_picker = document.at_css(".notae-settings-workspace-picker select[name='workspace_nav_picker']")
    expect(workspace_picker).to be_present
    picker_options = workspace_picker.css("option").map { |option| [ option.text.strip, option["value"] ] }
    expect(picker_options).to include(
      [ workspace.name, workspace_import_settings_path(workspace_slug: workspace.slug, settings_workspace_slug: workspace.slug) ],
      [ other_workspace.name, workspace_import_settings_path(workspace_slug: other_workspace.slug, settings_workspace_slug: other_workspace.slug) ]
    )
    selected_option = workspace_picker.css("option").find { |option| option["selected"].present? }
    expect(selected_option&.[]("value")).to eq(workspace_import_settings_path(workspace_slug: workspace.slug, settings_workspace_slug: workspace.slug))
  end

  it "redirects with a clear error when import is submitted without a selected file" do
    owner = User.create!(email: "import-settings-empty-upload@example.com", password: "password123")
    workspace = Workspace.create!(name: "Import empty upload", slug: "import-empty-upload")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    expect do
      post workspace_import_settings_path(workspace_slug: workspace.slug),
           params: { import: { files: { "0" => "" } } }
    end.not_to change(Page, :count)

    expect(response).to redirect_to(workspace_import_settings_path(workspace_slug: workspace.slug))
    expect(flash[:alert]).to eq("Select at least one file to import.")
  end

  it "imports uploaded files into pages" do
    owner = User.create!(email: "import-settings-upload@example.com", password: "password123")
    workspace = Workspace.create!(name: "Import upload", slug: "import-upload")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    markdown = uploaded_file("notes.md", "# Sprint plan\n- Ship import flow\n- Add tests")
    text = uploaded_file("summary.txt", "Plain summary paragraph")

    expect do
      post workspace_import_settings_path(workspace_slug: workspace.slug),
           params: { import: { files: [ markdown, text ] } }
    end.to change(Page, :count).by(2)

    expect(response).to redirect_to(workspace_import_settings_path(workspace_slug: workspace.slug))
    expect(flash[:notice]).to include("Imported 2 Notarum.")
    expect(workspace.pages.where(title: "notes")).to exist
    expect(workspace.pages.where(title: "summary")).to exist
  end

  it "imports html into a page and csv into a grid" do
    owner = User.create!(email: "import-settings-html-csv@example.com", password: "password123")
    workspace = Workspace.create!(name: "Import html csv", slug: "import-html-csv")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    html = uploaded_file("overview.html", "<h1>Overview</h1><p>Content section</p>")
    csv = uploaded_file("table.csv", "name,value\nalpha,1\nbeta,2\n")

    expect do
      post workspace_import_settings_path(workspace_slug: workspace.slug),
           params: { import: { files: [ html, csv ] } }
    end.to change(Page, :count).by(1).and change(Database, :count).by(1)

    expect(response).to redirect_to(workspace_import_settings_path(workspace_slug: workspace.slug))
    expect(flash[:notice]).to include("Imported 1 Nota and 1 Grid.")
    expect(workspace.pages.where(title: "overview")).to exist
    expect(workspace.databases.where(name: "table")).to exist

    follow_redirect!
    expect(response.body).to include("Import complete")
    expect(response.body).to include("Imported 1 Nota and 1 Grid.")
  end

  it "imports malformed pdf without crashing and creates a fallback page" do
    owner = User.create!(email: "import-settings-pdf-fallback@example.com", password: "password123")
    workspace = Workspace.create!(name: "Import pdf fallback", slug: "import-pdf-fallback")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    pdf = uploaded_file("broken.pdf", "%PDF-not-really-a-valid-document")

    expect do
      post workspace_import_settings_path(workspace_slug: workspace.slug),
           params: { import: { files: [ pdf ] } }
    end.to change(Page, :count).by(1)

    expect(response).to redirect_to(workspace_import_settings_path(workspace_slug: workspace.slug))
    expect(flash[:notice]).to include("Imported 1 Nota.")
    page = workspace.pages.order(created_at: :desc).first
    expect(page.title).to eq("broken")
    expect(page.blocks.first.content_json.to_s).to include("PDF")
  end
end
