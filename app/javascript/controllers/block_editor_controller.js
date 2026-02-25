import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import TaskList from "@tiptap/extension-task-list"
import TaskItem from "@tiptap/extension-task-item"

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
    category: "Structure",
    label: "Heading 3",
    keywords: ["h3", "section"],
    blockType: "heading_3",
    run: (editor) => editor.chain().focus().setHeading({ level: 3 }).run()
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
    category: "Lists",
    label: "To-do list",
    keywords: ["task", "todo", "checkbox"],
    blockType: "todo_list",
    run: (editor) => editor.chain().focus().toggleTaskList().run()
  },
  {
    category: "Lists",
    label: "Toggle list",
    keywords: ["toggle", "collapse"],
    blockType: "toggle_list",
    run: (editor) => editor.chain().focus().setParagraph().run()
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
  },
  {
    category: "Formatting",
    label: "Callout",
    keywords: ["callout", "note"],
    blockType: "callout",
    run: (editor) => editor.chain().focus().setParagraph().run()
  },
  {
    category: "Formatting",
    label: "Equation",
    keywords: ["math", "equation", "latex"],
    blockType: "equation",
    run: (editor) => editor.chain().focus().setParagraph().run()
  },
  {
    category: "Layout",
    label: "2 columns",
    keywords: ["columns", "layout", "2"],
    blockType: "columns_2",
    run: (editor) => editor.chain().focus().setParagraph().run()
  },
  {
    category: "Layout",
    label: "3 columns",
    keywords: ["columns", "layout", "3"],
    blockType: "columns_3",
    run: (editor) => editor.chain().focus().setParagraph().run()
  },
  {
    category: "Layout",
    label: "4 columns",
    keywords: ["columns", "layout", "4"],
    blockType: "columns_4",
    run: (editor) => editor.chain().focus().setParagraph().run()
  },
  {
    category: "Layout",
    label: "5 columns",
    keywords: ["columns", "layout", "5"],
    blockType: "columns_5",
    run: (editor) => editor.chain().focus().setParagraph().run()
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
      extensions: [
        StarterKit,
        TaskList,
        TaskItem.configure({
          nested: true
        })
      ],
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
        this.syncBlockTypeFromDocument(editor.getJSON())
        this.markEditingActive()
        this.scheduleSave()
      },
      onFocus: () => {
        this.setBlockFocused(true)
        this.markEditingActive()
      },
      onBlur: () => {
        this.setBlockFocused(false)
        this.markEditingInactive()
        this.hideSlashMenu()
      }
    })
  }

  disconnect() {
    clearTimeout(this.saveTimeout)
    clearTimeout(this.editingIdleTimeout)
    this.hideSlashMenu()
    this.setBlockFocused(false)
    window.removeEventListener("notae:block-remote-update", this.remoteUpdateHandler)
    this.markEditingInactive()

    if (this.editor) {
      this.editor.destroy()
    }
  }

  parseContent() {
    let parsedContent

    if (!this.initialJsonValue) {
      parsedContent = { type: "doc", content: [{ type: "paragraph" }] }
      return this.normalizeContentForCurrentBlockType(this.cleanDocument(parsedContent))
    }

    try {
      parsedContent = JSON.parse(this.initialJsonValue)
      return this.normalizeContentForCurrentBlockType(this.cleanDocument(parsedContent))
    } catch (_error) {
      parsedContent = { type: "doc", content: [{ type: "paragraph" }] }
      return this.normalizeContentForCurrentBlockType(this.cleanDocument(parsedContent))
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

  setBlockFocused(focused) {
    const block = this.element.closest("[data-block-id]")
    if (!block) return

    block.classList.toggle("is-focused", focused)
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
    if (command.blockType === "todo_list") {
      this.ensureTodoListStructure()
    }
    this.syncBlockTypeFromDocument(this.editor.getJSON())
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

  normalizeContentForCurrentBlockType(content) {
    if (this.currentBlockType !== "todo_list") return content
    if (this.documentContainsTaskList(content)) return content

    const blocks = Array.isArray(content?.content) ? content.content : []
    const taskItems = blocks
      .map((node) => this.nodeToTaskItem(node))
      .filter(Boolean)

    return {
      type: "doc",
      content: [
        {
          type: "taskList",
          content: taskItems.length > 0 ? taskItems : [this.nodeToTaskItem({ type: "paragraph" })]
        }
      ]
    }
  }

  syncBlockTypeFromDocument(content) {
    if (this.documentContainsTaskList(content)) {
      this.currentBlockType = "todo_list"
      return
    }

    if (this.currentBlockType === "todo_list") {
      this.currentBlockType = "paragraph"
    }
  }

  ensureTodoListStructure() {
    const currentDoc = this.editor.getJSON()
    if (this.documentContainsTaskList(currentDoc)) return

    this.currentBlockType = "todo_list"
    const normalized = this.normalizeContentForCurrentBlockType(currentDoc)
    this.editor.commands.setContent(normalized)
  }

  documentContainsTaskList(node) {
    if (!node || typeof node !== "object") return false
    if (node.type === "taskList") return true

    const children = Array.isArray(node.content) ? node.content : []
    return children.some((child) => this.documentContainsTaskList(child))
  }

  nodeToTaskItem(node) {
    const paragraph = this.nodeToParagraph(node)
    return {
      type: "taskItem",
      attrs: { checked: false },
      content: [paragraph]
    }
  }

  nodeToParagraph(node) {
    if (node?.type === "paragraph") {
      const cleanedContent = this.cleanInlineNodes(node.content)
      return {
        type: "paragraph",
        ...(cleanedContent.length > 0 ? { content: cleanedContent } : {})
      }
    }

    const text = this.flattenText(node).trim()
    if (!text) return { type: "paragraph" }

    return {
      type: "paragraph",
      content: [{ type: "text", text }]
    }
  }

  flattenText(node) {
    if (!node) return ""
    if (typeof node.text === "string") return node.text

    const children = Array.isArray(node.content) ? node.content : []
    return children.map((child) => this.flattenText(child)).join(" ")
  }

  cleanInlineNodes(nodes) {
    if (!Array.isArray(nodes)) return []

    return nodes
      .map((node) => this.cleanNode(node))
      .filter(Boolean)
  }

  cleanDocument(node) {
    const cleaned = this.cleanNode(node)

    if (!cleaned || cleaned.type !== "doc") {
      return { type: "doc", content: [{ type: "paragraph" }] }
    }

    const topLevel = Array.isArray(cleaned.content) ? cleaned.content : []
    if (topLevel.length === 0) {
      return { type: "doc", content: [{ type: "paragraph" }] }
    }

    return {
      ...cleaned,
      content: topLevel
    }
  }

  cleanNode(node) {
    if (!node || typeof node !== "object") return null

    if (node.type === "text") {
      if (typeof node.text !== "string") return null
      if (node.text.length === 0) return null
      return node
    }

    if (Array.isArray(node.content)) {
      const cleanedChildren = node.content
        .map((child) => this.cleanNode(child))
        .filter(Boolean)

      return {
        ...node,
        ...(cleanedChildren.length > 0 ? { content: cleanedChildren } : {})
      }
    }

    return node
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
