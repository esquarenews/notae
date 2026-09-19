import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const controllerPath = process.argv[2]
const clock = { now: 0 }
let documentFocused = true

class FakeDate extends Date {
  static now() {
    return clock.now
  }
}

const context = {
  Date: FakeDate,
  Element: class Element {},
  document: {
    visibilityState: "visible",
    hasFocus: () => documentFocused,
    querySelector: () => null
  },
  window: {}
}

const source = fs.readFileSync(controllerPath, "utf8")
  .replace(/^import \{ Controller \} from "@hotwired\/stimulus"\s*$/m, "class Controller {}")
  .replace("export default class extends Controller", "class AnalyticsTracker extends Controller")

vm.createContext(context)
vm.runInContext(`${source}\nglobalThis.AnalyticsTracker = AnalyticsTracker`, context)

function trackerAtStart() {
  const tracker = new context.AnalyticsTracker()
  tracker.tracking = true
  tracker.activeSurface = "nota"
  tracker.surfaceValue = "nota"
  tracker.intervalValue = 30_000
  tracker.idleAfterValue = 120_000
  tracker.lastInteractionAt = 0
  tracker.lastSampleAt = 0
  tracker.samples = []
  tracker.sendSample = (durationSeconds, timestamp) => tracker.samples.push({ durationSeconds, timestamp })
  return tracker
}

const idleTracker = trackerAtStart()
clock.now = 150_000
idleTracker.captureInterval()
assert.equal(idleTracker.lastSampleAt, 150_000)

clock.now = 179_000
idleTracker.recordInteraction({ target: null })
assert.equal(idleTracker.lastSampleAt, 179_000)

clock.now = 180_000
idleTracker.captureInterval()
assert.deepEqual(idleTracker.samples, [])

clock.now = 209_000
idleTracker.captureInterval()
assert.deepEqual(idleTracker.samples, [ { durationSeconds: 30, timestamp: 209_000 } ])

const focusTracker = trackerAtStart()
clock.now = 10_000
documentFocused = false
focusTracker.windowBlurred()
assert.deepEqual(focusTracker.samples, [ { durationSeconds: 10, timestamp: 10_000 } ])

clock.now = 29_000
documentFocused = true
focusTracker.windowFocused()

clock.now = 30_000
focusTracker.captureInterval()
assert.equal(focusTracker.samples.length, 1)

clock.now = 59_000
focusTracker.captureInterval()
assert.deepEqual(focusTracker.samples, [
  { durationSeconds: 10, timestamp: 10_000 },
  { durationSeconds: 30, timestamp: 59_000 }
])
