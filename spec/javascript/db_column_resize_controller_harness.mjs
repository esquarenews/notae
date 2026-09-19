import fs from "node:fs"

const controllerPath = new URL("../../app/javascript/controllers/db_column_resize_controller.js", import.meta.url)
const source = fs.readFileSync(controllerPath, "utf8")
  .replace('import { Controller } from "@hotwired/stimulus"', "")
  .replace("export default class extends Controller", "class DbColumnResizeController extends Controller")

const ControllerClass = new Function("Controller", `${source}\nreturn DbColumnResizeController`)(class {})
const controller = Object.create(ControllerClass.prototype)
const noOpClassList = { add() {}, remove() {} }
const column = {
  dataset: { columnKey: "property_status" },
  style: {},
  getBoundingClientRect() { return { width: 2400 } }
}
const header = {
  dataset: { columnKey: "property_status" },
  style: {},
  getBoundingClientRect() { return { width: 240 } }
}

globalThis.document = { body: { classList: noOpClassList } }
controller.enabledValue = true
controller.columnTargets = [column]
controller.headerTargets = [header]
controller.element = { classList: noOpClassList }
controller.pendingWidths = {}
controller.addPointerListeners = () => {}

controller.startResize({
  clientX: 500,
  currentTarget: { closest: () => header },
  preventDefault() {}
})
controller.onPointerMove({ clientX: 525 })

if (controller.startWidth !== 240) {
  throw new Error(`Expected the rendered header width (240), got ${controller.startWidth}`)
}

if (column.style.width !== "265px" || header.style.width !== "265px") {
  throw new Error(`Expected the first 25px movement to produce 265px, got ${column.style.width}`)
}
