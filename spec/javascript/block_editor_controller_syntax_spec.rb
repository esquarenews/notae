require "rails_helper"
require "open3"

RSpec.describe "BlockEditorController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/block_editor_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "guards the editor against block reorder drag payloads" do
    source = Rails.root.join("app/javascript/controllers/block_editor_controller.js").read

    expect(source).to include("handleDOMEvents")
    expect(source).to include("handleBlockReorderDragOver")
    expect(source).to include("handleBlockReorderDrop")
    expect(source).to include("application/x-notae-block-id")
  end

  it "dispatches tab-based block reparent requests" do
    source = Rails.root.join("app/javascript/controllers/block_editor_controller.js").read

    expect(source).to include('event.key === "Tab"')
    expect(source).to include("notae:block-reparent")
    expect(source).to include('direction: event.shiftKey ? "outdent" : "indent"')
    expect(source).to include("focusEditor: true")
  end

  it "flushes pending editor saves before a block reparent happens" do
    source = Rails.root.join("app/javascript/controllers/block_editor_controller.js").read

    expect(source).to include("notae:block-flush-save")
    expect(source).to include("handleFlushSaveRequest(event)")
    expect(source).to include("event.detail.promise = this.flushSave()")
    expect(source).to include("flushSave()")
    expect(source).to include("if (!this.hasPendingChanges) return true")
  end

  it "keeps the serialized block JSON in sync after saves and remote updates" do
    source = Rails.root.join("app/javascript/controllers/block_editor_controller.js").read

    expect(source).to include("syncStoredBlockState(content, blockType = this.currentBlockType)")
    expect(source).to include("this.initialJsonValue = JSON.stringify(content)")
    expect(source).to include("this.syncStoredBlockState(content, this.currentBlockType)")
    expect(source).to include("this.syncStoredBlockState(data.content_json || payload.block.content_json, data.block_type || this.currentBlockType)")
    expect(source).to include('"X-Notae-Client-Session": this.clientSessionId')
    expect(source).to include('const storageKey = "notae-client-session-id"')
  end

  it "loads the Tiptap link extension for block-linked split previews" do
    source = Rails.root.join("app/javascript/controllers/block_editor_controller.js").read

    expect(source).to include('import Link from "@tiptap/extension-link"')
    expect(source).to include("Link.configure({")
    expect(source).to include("openOnClick: false")
  end

  it "offers heading 4 in the slash command list" do
    source = Rails.root.join("app/javascript/controllers/block_editor_controller.js").read

    expect(source).to include('label: "Heading 4"')
    expect(source).to include('blockType: "heading_4"')
    expect(source).to include("setHeading({ level: 4 })")
  end

  it "keeps block-linked split preview clicks in the current pane" do
    source = Rails.root.join("app/javascript/controllers/block_editor_controller.js").read

    expect(source).to include("click: (_view, event) => this.handleEditorClick(event)")
    expect(source).to include("handleEditorClick(event)")
    expect(source).to include("splitPreviewLink(url)")
    expect(source).to include('url.searchParams.get("split_source") === "block"')
    expect(source).to include('Boolean(url.searchParams.get("split_page_id"))')
    expect(source).to include("event.preventDefault()")
    expect(source).to include("visitSplitPreview(url)")
    expect(source).to include("hostWindow()")
    expect(source).to include("window.top")
    expect(source).to include("visitWindow.Turbo.visit(url.toString())")
  end

  it "turns copied gantt embed payloads into live Nota blocks" do
    source = Rails.root.join("app/javascript/controllers/block_editor_controller.js").read

    expect(source).to include("handlePaste: (_view, event) => this.handleEditorPaste(event)")
    expect(source).to include("handleEditorPaste(event)")
    expect(source).to include("ganttEmbedPayloadFromClipboard(event)")
    expect(source).to include("data-notae-gantt-embed='1'")
    expect(source).to include("/gantt_embed$/")
    expect(source).to include('formData.append("block[block_type]", "gantt_embed")')
    expect(source).to include("window.Turbo.renderStreamMessage(responseText)")
  end

  it "turns copied graph embed payloads into live Nota blocks" do
    source = Rails.root.join("app/javascript/controllers/block_editor_controller.js").read

    expect(source).to include("graphEmbedPayloadFromClipboard(event)")
    expect(source).to include("data-notae-graph-embed='1'")
    expect(source).to include("/graph_embed$/")
    expect(source).to include('formData.append("block[block_type]", "graph_embed")')
    expect(source).to include("window.Turbo.renderStreamMessage(responseText)")
  end

  it "falls back to explicit navigation for non-split links when tiptap link clicks are disabled" do
    source = Rails.root.join("app/javascript/controllers/block_editor_controller.js").read

    expect(source).to include("standardNavigableLink(event, clickedLink)")
    expect(source).to include("followStandardLink(clickedLink, url, event)")
    expect(source).to include('clickedLink.getAttribute("target") === "_blank"')
    expect(source).to include('window.open(url.toString(), "_blank", "noopener")')
    expect(source).to include("window.location.assign(url.toString())")
  end
end
