export function buildAbsoluteUrl(baseUrl, path) {
  return new URL(path, baseUrl).toString()
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

export function truncateError(error, maxLength = 500) {
  const value = error instanceof Error ? `${error.name}: ${error.message}` : String(error || "Unknown error")
  return value.slice(0, maxLength)
}

export class TranscriptCollector {
  constructor({ startedAt = Date.now() } = {}) {
    this.startedAt = startedAt
    this.utterances = []
    this.lastSeenByKey = new Map()
  }

  addEntries(entries, now = Date.now()) {
    for (const entry of Array.from(entries || [])) {
      const speakerName = String(entry?.speaker_name || entry?.speakerName || entry?.speaker || "").trim()
      const text = normalizeText(entry?.text)
      if (!speakerName || !text) continue

      const dedupeKey = `${speakerName}::${text.toLowerCase()}`
      const lastSeenAt = this.lastSeenByKey.get(dedupeKey)
      if (lastSeenAt && now - lastSeenAt < 10_000) continue

      const previous = this.utterances[this.utterances.length - 1]
      if (previous && previous.speaker_name === speakerName && text.startsWith(previous.text) && now - (this.startedAt + previous.started_ms) < 8_000) {
        previous.text = text
        previous.ended_ms = Math.max(previous.ended_ms, now - this.startedAt)
        previous.confidence = Math.max(previous.confidence, 0.72)
        this.lastSeenByKey.set(dedupeKey, now)
        continue
      }

      const startedMs = Math.max(now - this.startedAt, 0)
      this.utterances.push({
        position: this.utterances.length,
        started_ms: startedMs,
        ended_ms: startedMs + 1500,
        speaker_key: speakerKeyForIndex(this.utterances.length),
        speaker_name: speakerName,
        text,
        confidence: 0.72
      })
      this.lastSeenByKey.set(dedupeKey, now)
    }
  }

  hasContent() {
    return this.utterances.length > 0
  }

  transcriptText() {
    return this.utterances.map((utterance) => {
      return `[${millisecondsToClock(utterance.started_ms)}] ${utterance.speaker_name}: ${utterance.text}`
    }).join("\n")
  }

  payload(metadata = {}) {
    return {
      transcript_text: this.transcriptText(),
      utterances: this.utterances.map((utterance) => ({ ...utterance })),
      metadata
    }
  }
}

export function millisecondsToClock(value) {
  const seconds = Math.max(Math.floor(Number(value || 0) / 1000), 0)
  const minutes = Math.floor(seconds / 60)
  const remaining = seconds % 60
  return `${String(minutes).padStart(2, "0")}:${String(remaining).padStart(2, "0")}`
}

function speakerKeyForIndex(index) {
  return `S${Number(index || 0) + 1}`
}

function normalizeText(value) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .trim()
}
