export function buildAbsoluteUrl(baseUrl, path) {
  return new URL(path, baseUrl).toString()
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

export function summarizeBodyText(value, maxLength = 400) {
  return normalizeText(value).slice(0, maxLength)
}

export function classifyGoogleMeetJoinText(value) {
  const text = normalizeText(value).toLowerCase()
  if (!text) return { state: "unknown", reason: null }

  if (/\b(leave call|hang up|turn on captions|turn off captions|more options)\b/i.test(text)) {
    return { state: "joined", reason: "in_meeting_controls_visible" }
  }

  if (/\b(waiting to be let in|waiting for someone to let you in|someone in the call should let you in|you'll join when someone lets you in|you’ll join when someone lets you in|asking to join|asked to join|request to join sent|you asked to join|host hasn't joined yet|host hasn’t joined yet|waiting for the host|meeting hasn't started|meeting hasn’t started yet)\b/i.test(text)) {
    return { state: "waiting", reason: "awaiting_admission" }
  }

  if (/\b(you can't join this video call|you can’t join this video call|your request to join was denied|you were denied entry|meeting not found|meeting code is invalid|this meeting has ended|this call has ended|meeting is unavailable|you are not allowed to join|removed you from the meeting)\b/i.test(text)) {
    return { state: "denied", reason: "explicit_denial_or_invalid_meeting" }
  }

  return { state: "unknown", reason: null }
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
