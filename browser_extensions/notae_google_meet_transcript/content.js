class NotaeMeetTranscriptCollector {
  constructor() {
    this.active = false
    this.utterances = []
    this.speakerKeys = {}
    this.startedAtMs = 0
    this.lastEntrySignature = null
    this.lastEntrySeenAt = 0
    this.snapshotTimer = null
    this.scanTimer = null
    this.observer = null

    chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
      if (message?.type === "notae-meet-start") {
        this.start()
        sendResponse({ ok: true, snapshot: this.snapshot() })
        return true
      }

      if (message?.type === "notae-meet-stop") {
        const snapshot = this.stop()
        sendResponse({ ok: true, snapshot })
        return true
      }

      return false
    })

    window.addEventListener("beforeunload", () => {
      if (!this.active) return
      this.sendSnapshot(true)
    })
  }

  start() {
    this.active = true
    this.utterances = []
    this.speakerKeys = {}
    this.startedAtMs = Date.now()
    this.lastEntrySignature = null
    this.lastEntrySeenAt = 0
    this.disconnectObserver()

    this.observer = new MutationObserver(() => this.scan())
    this.observer.observe(document.body || document.documentElement, {
      childList: true,
      subtree: true,
      characterData: true
    })

    this.scanTimer = window.setInterval(() => this.scan(), 1200)
    this.scan()
  }

  stop() {
    const snapshot = this.snapshot()
    this.active = false
    this.disconnectObserver()
    return snapshot
  }

  disconnectObserver() {
    if (this.observer) this.observer.disconnect()
    this.observer = null
    if (this.scanTimer) window.clearInterval(this.scanTimer)
    this.scanTimer = null
    if (this.snapshotTimer) window.clearTimeout(this.snapshotTimer)
    this.snapshotTimer = null
  }

  scan() {
    if (!this.active) return

    let changed = false
    for (const entry of this.extractEntries()) {
      changed = this.appendEntry(entry) || changed
    }

    if (changed) this.queueSnapshot()
  }

  extractEntries() {
    const signatures = new Set()
    const entries = []
    const regions = Array.from(document.querySelectorAll('[aria-live="polite"], [aria-live="assertive"]'))

    for (const region of regions) {
      if (!this.visible(region)) continue

      const candidates = [ region, ...Array.from(region.querySelectorAll("div, span, p")) ]
      for (const candidate of candidates) {
        const entry = this.entryFromElement(candidate)
        if (!entry) continue

        const signature = `${entry.speakerName}|${entry.text}`
        if (signatures.has(signature)) continue

        signatures.add(signature)
        entries.push(entry)
      }
    }

    return entries
  }

  entryFromElement(element) {
    if (!(element instanceof HTMLElement) || !this.visible(element)) return null

    const rawText = this.normalizeMultilineText(element.innerText || element.textContent || "")
    if (!rawText) return null

    const lines = rawText.split("\n").map((line) => line.trim()).filter(Boolean)
    let speakerName = ""
    let text = ""

    if (lines.length >= 2 && this.plausibleSpeaker(lines[0])) {
      speakerName = lines[0]
      text = lines.slice(1).join(" ")
    } else {
      const match = rawText.match(/^([^:\n]{1,60}):\s+(.+)$/)
      if (!match || !this.plausibleSpeaker(match[1])) return null

      speakerName = match[1].trim()
      text = match[2].trim()
    }

    text = this.normalizeInlineText(text)
    if (!this.plausibleTranscriptText(text)) return null

    return { speakerName, text }
  }

  appendEntry(entry) {
    const speakerName = entry.speakerName.trim()
    const text = entry.text.trim()
    const nowMs = Math.max(Date.now() - this.startedAtMs, 0)
    const signature = `${speakerName}|${text}`

    if (signature === this.lastEntrySignature && nowMs - this.lastEntrySeenAt < 2500) {
      return false
    }

    const lastUtterance = this.utterances[this.utterances.length - 1]
    if (lastUtterance && lastUtterance.speaker_name === speakerName) {
      const mergedText = this.longerVariant(lastUtterance.text, text)
      if (mergedText === lastUtterance.text || mergedText === text) {
        const changed = mergedText !== lastUtterance.text
        lastUtterance.text = mergedText
        lastUtterance.ended_ms = nowMs
        this.lastEntrySignature = signature
        this.lastEntrySeenAt = nowMs
        return changed
      }
    }

    this.utterances.push({
      position: this.utterances.length,
      started_ms: nowMs,
      ended_ms: nowMs + 1000,
      speaker_key: this.speakerKeyFor(speakerName),
      speaker_name: speakerName,
      text,
      confidence: 0.8
    })
    this.lastEntrySignature = signature
    this.lastEntrySeenAt = nowMs
    return true
  }

  speakerKeyFor(name) {
    if (!this.speakerKeys[name]) {
      this.speakerKeys[name] = `S${Object.keys(this.speakerKeys).length + 1}`
    }

    return this.speakerKeys[name]
  }

  queueSnapshot() {
    if (this.snapshotTimer) return

    this.snapshotTimer = window.setTimeout(() => {
      this.snapshotTimer = null
      this.sendSnapshot(false)
    }, 700)
  }

  sendSnapshot(final) {
    chrome.runtime.sendMessage({
      type: "notae-meet-transcript-snapshot",
      snapshot: this.snapshot(),
      final: Boolean(final)
    }).catch(() => {})
  }

  snapshot() {
    const utterances = this.utterances.map((utterance) => ({ ...utterance }))
    return {
      title: this.meetingTitle(),
      joinUrl: window.location.href,
      utterances,
      transcriptText: utterances.map((utterance) => {
        const seconds = Math.max(Math.floor(Number(utterance.started_ms || 0) / 1000), 0)
        const minutesPart = String(Math.floor(seconds / 60)).padStart(2, "0")
        const secondsPart = String(seconds % 60).padStart(2, "0")
        return `[${minutesPart}:${secondsPart}] ${utterance.speaker_name}: ${utterance.text}`
      }).join("\n")
    }
  }

  meetingTitle() {
    const title = String(document.title || "").replace(/\s*-\s*Google Meet\s*$/i, "").trim()
    return title || "Google Meet transcript"
  }

  visible(element) {
    if (!(element instanceof HTMLElement)) return false
    if (element.offsetParent === null && getComputedStyle(element).position !== "fixed") return false
    if (element.getAttribute("aria-hidden") === "true") return false

    const rect = element.getBoundingClientRect()
    return rect.width > 0 && rect.height > 0
  }

  plausibleSpeaker(value) {
    const text = value.trim()
    if (text.length === 0 || text.length > 60) return false
    if (/captions?|google meet|meeting details|presenting/i.test(text)) return false
    return /[A-Za-z]/.test(text)
  }

  plausibleTranscriptText(value) {
    const text = value.trim()
    if (text.length < 2 || text.length > 320) return false
    if (/turn on captions|you left the meeting|meeting details/i.test(text)) return false
    return /[A-Za-z0-9]/.test(text)
  }

  normalizeInlineText(value) {
    return value.replace(/\s+/g, " ").trim()
  }

  normalizeMultilineText(value) {
    return value
      .replace(/\r/g, "\n")
      .split("\n")
      .map((line) => line.replace(/\s+/g, " ").trim())
      .filter(Boolean)
      .join("\n")
      .trim()
  }

  longerVariant(left, right) {
    const normalizedLeft = this.normalizeInlineText(left)
    const normalizedRight = this.normalizeInlineText(right)

    if (normalizedLeft === normalizedRight) return normalizedLeft
    if (normalizedRight.startsWith(normalizedLeft)) return normalizedRight
    if (normalizedLeft.startsWith(normalizedRight)) return normalizedLeft

    return normalizedRight
  }
}

window.notaeMeetTranscriptCollector ||= new NotaeMeetTranscriptCollector()
