import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

const consumer = createConsumer()
const HEARTBEAT_MS = 15000
const EDITING_THROTTLE_MS = 1200

export default class extends Controller {
  static targets = ["presence"]
  static values = {
    workspaceSlug: String,
    pageId: String,
    currentUserId: String
  }

  connect() {
    this.heartbeatTimer = null
    this.lastEditingSentAt = 0
    this.lastEditingBlockId = null
    this.handleBlockEditingEvent = this.handleBlockEditingEvent.bind(this)

    window.addEventListener("notae:block-editing", this.handleBlockEditingEvent)

    this.subscription = consumer.subscriptions.create(
      {
        channel: "PageChannel",
        workspace_slug: this.workspaceSlugValue,
        page_id: this.pageIdValue
      },
      {
        connected: () => this.startHeartbeat(),
        disconnected: () => {
          this.stopHeartbeat()
          this.renderPresence([])
          this.renderEditing([])
        },
        received: (payload) => this.handlePayload(payload)
      }
    )
  }

  disconnect() {
    this.stopHeartbeat()
    window.removeEventListener("notae:block-editing", this.handleBlockEditingEvent)

    if (this.subscription) {
      consumer.subscriptions.remove(this.subscription)
      this.subscription = null
    }
  }

  startHeartbeat() {
    this.stopHeartbeat()
    this.heartbeatTimer = setInterval(() => {
      if (this.subscription) {
        this.subscription.perform("heartbeat")
      }
    }, HEARTBEAT_MS)
  }

  stopHeartbeat() {
    if (!this.heartbeatTimer) return

    clearInterval(this.heartbeatTimer)
    this.heartbeatTimer = null
  }

  handlePayload(payload) {
    switch (payload?.type) {
      case "presence":
        this.renderPresence(payload.users || [])
        break
      case "editing":
        this.renderEditing(payload.entries || [])
        break
      case "block_updated":
        this.forwardRemoteBlockUpdate(payload)
        break
      default:
        break
    }
  }

  handleBlockEditingEvent(event) {
    if (!this.subscription) return

    const blockId = event.detail?.blockId
    const active = Boolean(event.detail?.active)
    if (!blockId) return

    if (active) {
      const now = Date.now()
      if (this.lastEditingBlockId === blockId && now - this.lastEditingSentAt < EDITING_THROTTLE_MS) {
        return
      }

      this.lastEditingBlockId = blockId
      this.lastEditingSentAt = now
      this.subscription.perform("editing_start", { block_id: blockId })
      return
    }

    if (this.lastEditingBlockId && this.lastEditingBlockId !== blockId) return

    this.lastEditingBlockId = null
    this.subscription.perform("editing_stop", { block_id: blockId })
  }

  renderPresence(users) {
    if (!this.hasPresenceTarget) return

    const fragment = document.createDocumentFragment()

    const label = document.createElement("span")
    label.className = "text-xs text-stone-500"
    label.textContent = users.length > 0 ? "Active now" : "Only you here"
    fragment.appendChild(label)

    users.forEach((user) => {
      const chip = document.createElement("span")
      chip.className = "inline-flex h-7 w-7 items-center justify-center rounded-full bg-stone-900 text-xs font-medium text-white"
      chip.title = user.email
      chip.textContent = this.initials(user.email)
      fragment.appendChild(chip)
    })

    this.presenceTarget.replaceChildren(fragment)
  }

  renderEditing(entries) {
    const indicators = document.querySelectorAll("[data-editing-indicator-for]")
    indicators.forEach((node) => {
      node.classList.add("hidden")
      node.textContent = ""
    })

    const entriesByBlock = new Map()
    entries.forEach((entry) => {
      const blockId = entry?.block_id
      const email = entry?.user?.email
      const userId = entry?.user?.id
      if (!blockId || !email) return
      if (String(userId) === String(this.currentUserIdValue)) return

      const names = entriesByBlock.get(String(blockId)) || []
      names.push(email)
      entriesByBlock.set(String(blockId), names)
    })

    entriesByBlock.forEach((emails, blockId) => {
      const indicator = document.querySelector(`[data-editing-indicator-for="${blockId}"]`)
      if (!indicator) return

      const [firstEmail] = emails
      const suffix = emails.length > 1 ? ` +${emails.length - 1}` : ""
      indicator.textContent = `${firstEmail}${suffix} is editing...`
      indicator.classList.remove("hidden")
    })
  }

  forwardRemoteBlockUpdate(payload) {
    if (String(payload.actor_id) === String(this.currentUserIdValue)) return

    window.dispatchEvent(
      new CustomEvent("notae:block-remote-update", {
        detail: {
          actorId: payload.actor_id,
          block: payload.block
        }
      })
    )
  }

  initials(email) {
    const stem = String(email || "").split("@")[0]
    const compact = stem.replace(/[^a-zA-Z0-9]/g, "")
    return compact.slice(0, 2).toUpperCase() || "?"
  }
}
