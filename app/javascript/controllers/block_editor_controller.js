import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"

const DEBOUNCE_MS = 300
const EDITING_IDLE_MS = 3000

const SLASH_COMMANDS = [
  {
    category: "Basic",
    label: "Text",
    keywords: ["paragraph", "plain"],
    blockType: "paragraph",
    run: (editor) => editor.chain().focus().setParagraph().run()
  },
  {
    category: "Structure",
    label: "Heading 1",
    keywords: ["title", "h1", "header"],
    blockType: "heading_1",
    run: (editor) => editor.chain().focus().setHeading({ level: 1 }).run()
  },
  {
    category: "Structure",
    label: "Heading 2",
    keywords: ["subtitle", "h2", "header"],
    blockType: "heading_2",
    run: (editor) => editor.chain().focus().setHeading({ level: 2 }).run()
  },
  {
    category: "Lists",
    label: "Bullet list",
    keywords: ["list", "unordered", "bullet"],
    blockType: "bullet_list",
    run: (editor) => editor.chain().focus().toggleBulletList().run()
  },
  {
    category: "Lists",
    label: "Numbered list",
    keywords: ["list", "ordered", "number"],
    blockType: "ordered_list",
    run: (editor) => editor.chain().focus().toggleOrderedList().run()
  },
  {
    category: "Formatting",
    label: "Quote",
    keywords: ["blockquote", "citation"],
    blockType: "blockquote",
    run: (editor) => editor.chain().focus().toggleBlockquote().run()
  },
  {
    category: "Formatting",
    label: "Code block",
    keywords: ["code", "snippet"],
    blockType: "code_block",
    run: (editor) => editor.chain().focus().toggleCodeBlock().run()
  }
].map((command) => ({
  ...command,
  searchableText: [command.label, ...command.keywords, command.category].join(" ").toLowerCase()
}))

export default class extends Controller {
  static targets = ["editor"]
  static values = {
    url: String,
    initialJson: String,
    blockType: String,
    blockId: String
  }

  connect() {
    this.currentBlockType = this.blockTypeValue || "paragraph"
    this.saveTimeout = null
    this.editingIdleTimeout = null
    this.suppressUpdateCycle = false
    this.lastKnownUpdatedAtMs = 0
    this.slashMenuElement = null
    this.slashContext = null
    this.filteredSlashCommands = []
    this.selectedSlashIndex = 0
    this.slashMenuMouseDownHandler = (event) => this.handleSlashMenuMouseDown(event)
    this.remoteUpdateHandler = (event) => this.applyRemoteUpdate(event.detail)
    window.addEventListener("notae:block-remote-update", this.remoteUpdateHandler)

    this.editor = new Editor({
      element: this.editorTarget,
      extensions: [StarterKit],
      content: this.parseContent(),
      editorProps: {
        handleKeyDown: (_view, event) => this.handleEditorKeydown(event)
      },
      onUpdate: ({ editor }) => {
        if (this.suppressUpdateCycle) {
          this.suppressUpdateCycle = false
          return
        }

        this.refreshSlashMenu(editor)
        this.markEditingActive()
        this.scheduleSave()
      },
      onFocus: () => this.markEditingActive(),
      onBlur: () => {
        this.markEditingInactive()
        this.hideSlashMenu()
      }
    })
  }

  disconnect() {
    clearTimeout(this.saveTimeout)
    clearTimeout(this.editingIdleTimeout)
    this.hideSlashMenu()
    window.removeEventListener("notae:block-remote-update", this.remoteUpdateHandler)
    this.markEditingInactive()

    if (this.editor) {
      this.editor.destroy()
    }
  }

  parseContent() {
    if (!this.initialJsonValue) {
      return { type: "doc", content: [{ type: "paragraph" }] }
    }

    try {
      return JSON.parse(this.initialJsonValue)
    } catch (_error) {
      return { type: "doc", content: [{ type: "paragraph" }] }
    }
  }

  scheduleSave() {
    clearTimeout(this.saveTimeout)
    this.saveTimeout = setTimeout(() => this.save(), DEBOUNCE_MS)
  }

  markEditingActive() {
    if (!this.hasBlockIdValue) return

    window.dispatchEvent(new CustomEvent("notae:block-editing", { detail: { blockId: this.blockIdValue, active: true } }))
    clearTimeout(this.editingIdleTimeout)
    this.editingIdleTimeout = setTimeout(() => this.markEditingInactive(), EDITING_IDLE_MS)
  }

  markEditingInactive() {
    if (!this.hasBlockIdValue) return

    clearTimeout(this.editingIdleTimeout)
    window.dispatchEvent(new CustomEvent("notae:block-editing", { detail: { blockId: this.blockIdValue, active: false } }))
  }

  applyRemoteUpdate(detail) {
    const block = detail?.block
    if (!block || String(block.id) !== String(this.blockIdValue) || !this.editor) return

    const incomingUpdatedAtMs = Date.parse(block.updated_at || "")
    if (Number.isFinite(incomingUpdatedAtMs) && this.lastKnownUpdatedAtMs > 0 && incomingUpdatedAtMs <= this.lastKnownUpdatedAtMs) {
      return
    }

    this.suppressUpdateCycle = true
    this.currentBlockType = block.block_type || this.currentBlockType
    this.editor.commands.setContent(block.content_json || { type: "doc", content: [{ type: "paragraph" }] })

    if (Number.isFinite(incomingUpdatedAtMs)) {
      this.lastKnownUpdatedAtMs = incomingUpdatedAtMs
    }
  }

  handleEditorKeydown(event) {
    if (!this.slashMenuOpen()) return false

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.moveSlashSelection(1)
      return true
    }

    if (event.key === "ArrowUp") {
      event.preventDefault()
      this.moveSlashSelection(-1)
      return true
    }

    if (event.key === "Enter") {
      event.preventDefault()
      this.executeSlashCommand(this.selectedSlashIndex)
      return true
    }

    if (event.key === "Escape") {
      event.preventDefault()
      this.hideSlashMenu()
      return true
    }

    return false
  }

  handleSlashMenuMouseDown(event) {
    const option = event.target.closest("[data-slash-index]")
    if (!option) return

    event.preventDefault()
    this.executeSlashCommand(Number(option.dataset.slashIndex))
  }

  refreshSlashMenu(editor) {
    const context = this.resolveSlashContext(editor)
    if (!context) {
      this.hideSlashMenu()
      return
    }

    const query = context.query.toLowerCase()
    this.filteredSlashCommands = SLASH_COMMANDS.filter((command) => command.searchableText.includes(query))
    if (this.filteredSlashCommands.length === 0) {
      this.hideSlashMenu()
      return
    }

    this.slashContext = context
    this.selectedSlashIndex = Math.min(this.selectedSlashIndex, this.filteredSlashCommands.length - 1)
    this.renderSlashMenu()
  }

  resolveSlashContext(editor) {
    const { state } = editor
    const { from, empty, $from } = state.selection
    if (!empty || !$from.parent.isTextblock) return null

    const textBefore = $from.parent.textBetween(0, $from.parentOffset, " ", " ")
    const match = textBefore.match(/(?:^|\s)\/([a-z0-9_-]*)$/i)
    if (!match) return null

    const leadingSpaceOffset = match[0].startsWith(" ") ? 1 : 0
    const parentOffset = match.index + leadingSpaceOffset

    return {
      query: match[1] || "",
      from: from - $from.parentOffset + parentOffset,
      to: from
    }
  }

  ensureSlashMenuElement() {
    if (this.slashMenuElement) return

    this.slashMenuElement = document.createElement("div")
    this.slashMenuElement.className = "notae-slash-menu"
    this.slashMenuElement.addEventListener("mousedown", this.slashMenuMouseDownHandler)
    this.element.appendChild(this.slashMenuElement)
  }

  renderSlashMenu() {
    this.ensureSlashMenuElement()

    const grouped = this.filteredSlashCommands.reduce((memo, command, index) => {
      if (!memo[command.category]) memo[command.category] = []
      memo[command.category].push({ command, index })
      return memo
    }, {})

    const html = Object.entries(grouped)
      .map(([category, entries]) => {
        const options = entries
          .map(({ command, index }) => {
            const selected = index === this.selectedSlashIndex ? " active" : ""
            return `<button type="button" class="notae-slash-option${selected}" data-slash-index="${index}">
                <span class="notae-slash-option-label">${this.escapeHtml(command.label)}</span>
                <span class="notae-slash-option-meta">/${this.escapeHtml(command.keywords[0])}</span>
              </button>`
          })
          .join("")

        return `<div class="notae-slash-group">
            <p class="notae-slash-category">${this.escapeHtml(category)}</p>
            ${options}
          </div>`
      })
      .join("")

    this.slashMenuElement.innerHTML = html
    this.slashMenuElement.classList.remove("is-hidden")
  }

  executeSlashCommand(index) {
    if (!this.editor) return

    const command = this.filteredSlashCommands[index]
    if (!command || !this.slashContext) return

    this.editor.chain().focus().deleteRange({ from: this.slashContext.from, to: this.slashContext.to }).run()
    command.run(this.editor)
    this.currentBlockType = command.blockType
    this.hideSlashMenu()
    this.scheduleSave()
  }

  moveSlashSelection(delta) {
    if (this.filteredSlashCommands.length === 0) return

    const next = this.selectedSlashIndex + delta
    if (next < 0) {
      this.selectedSlashIndex = this.filteredSlashCommands.length - 1
    } else if (next >= this.filteredSlashCommands.length) {
      this.selectedSlashIndex = 0
    } else {
      this.selectedSlashIndex = next
    }

    this.renderSlashMenu()
  }

  slashMenuOpen() {
    return Boolean(this.slashMenuElement && !this.slashMenuElement.classList.contains("is-hidden") && this.slashContext)
  }

  hideSlashMenu() {
    this.slashContext = null
    this.filteredSlashCommands = []
    this.selectedSlashIndex = 0

    if (this.slashMenuElement) {
      this.slashMenuElement.classList.add("is-hidden")
      this.slashMenuElement.innerHTML = ""
    }
  }

  escapeHtml(value) {
    return value
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }

  async save() {
    const payload = {
      block: {
        content_json: this.editor.getJSON(),
        block_type: this.currentBlockType
      }
    }

    const response = await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify(payload)
    })

    if (!response.ok) return

    const data = await response.json()
    const updatedAtMs = Date.parse(data.updated_at || "")
    if (Number.isFinite(updatedAtMs)) {
      this.lastKnownUpdatedAtMs = updatedAtMs
    }
  }
}
