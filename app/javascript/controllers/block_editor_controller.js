import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"

const DEBOUNCE_MS = 300

const COMMANDS = {
  "/h1": { blockType: "heading_1", run: (editor) => editor.chain().focus().setHeading({ level: 1 }).run() },
  "/h2": { blockType: "heading_2", run: (editor) => editor.chain().focus().setHeading({ level: 2 }).run() },
  "/bullet": { blockType: "bullet_list", run: (editor) => editor.chain().focus().toggleBulletList().run() },
  "/number": { blockType: "ordered_list", run: (editor) => editor.chain().focus().toggleOrderedList().run() },
  "/quote": { blockType: "blockquote", run: (editor) => editor.chain().focus().toggleBlockquote().run() },
  "/code": { blockType: "code_block", run: (editor) => editor.chain().focus().toggleCodeBlock().run() }
}

export default class extends Controller {
  static targets = ["editor"]
  static values = {
    url: String,
    initialJson: String,
    blockType: String
  }

  connect() {
    this.currentBlockType = this.blockTypeValue || "paragraph"
    this.saveTimeout = null

    this.editor = new Editor({
      element: this.editorTarget,
      extensions: [StarterKit],
      content: this.parseContent(),
      onUpdate: ({ editor }) => {
        this.applySlashCommand(editor)
        this.scheduleSave()
      }
    })
  }

  disconnect() {
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

  applySlashCommand(editor) {
    const text = editor.getText().trimStart()
    const match = text.match(/^\/[a-z0-9]+/)
    if (!match) return

    const command = COMMANDS[match[0]]
    if (!command) return

    command.run(editor)
    this.currentBlockType = command.blockType
  }

  scheduleSave() {
    clearTimeout(this.saveTimeout)
    this.saveTimeout = setTimeout(() => this.save(), DEBOUNCE_MS)
  }

  async save() {
    const payload = {
      block: {
        content_json: this.editor.getJSON(),
        block_type: this.currentBlockType
      }
    }

    await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      },
      body: JSON.stringify(payload)
    })
  }
}
