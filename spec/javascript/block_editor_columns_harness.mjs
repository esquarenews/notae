import fs from "node:fs"

const controllerPath = new URL("../../app/javascript/controllers/block_editor_controller.js", import.meta.url)
const source = fs.readFileSync(controllerPath, "utf8")
  .replace('import { Controller } from "@hotwired/stimulus"', "")
  .replace("export default class extends Controller", "class BlockEditorController extends Controller")

const ControllerClass = new Function("Controller", `${source}\nreturn BlockEditorController`)(class {})
const controller = Object.create(ControllerClass.prototype)
controller.currentBlockType = "columns_3"

const normalized = controller.normalizeColumnContent({
  type: "doc",
  content: [
    { type: "paragraph", content: [{ type: "text", text: "First paragraph" }] },
    { type: "paragraph", content: [{ type: "text", text: "Second paragraph" }] }
  ]
})

if (normalized.content.length !== 3 || normalized.content.some((node) => node.type !== "columnCell")) {
  throw new Error("Expected exactly three column containers")
}

if (normalized.content[0].content.length !== 2 || normalized.content[0].content[1].content[0].text !== "Second paragraph") {
  throw new Error("Expected existing paragraphs to remain together in the first column")
}

const repairedAfterEdit = controller.normalizeColumnContent({
  type: "doc",
  content: normalized.content.slice(0, 2)
})

if (repairedAfterEdit.content.length !== 3 || repairedAfterEdit.content[2].type !== "columnCell") {
  throw new Error("Expected a trailing empty column to be restored after an editor update")
}

let selectedPosition = null
let focused = false
const nodes = [5, 4, 3].map((nodeSize) => ({ nodeSize, type: { name: "columnCell" } }))
controller.editor = {
  state: {
    selection: { $from: { index: () => 0 } },
    doc: {
      childCount: nodes.length,
      child: (index) => nodes[index]
    }
  },
  commands: { setTextSelection: (position) => { selectedPosition = position } },
  view: { focus: () => { focused = true } }
}

if (!controller.moveColumnSelection(1) || selectedPosition !== 7 || !focused) {
  throw new Error(`Expected Tab to focus the second column at position 7, got ${selectedPosition}`)
}
