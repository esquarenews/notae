import os from "node:os"
import fs from "node:fs/promises"
import path from "node:path"
import process from "node:process"
import { chromium } from "playwright"
import { buildAbsoluteUrl, sleep, truncateError, TranscriptCollector } from "./lib/core.mjs"

const config = {
  baseUrl: env("MEETING_BOT_BASE_URL"),
  internalToken: env("MEETING_BOT_INTERNAL_TOKEN"),
  displayName: env("MEETING_BOT_DISPLAY_NAME", "Notae Bot"),
  workerId: env("MEETING_BOT_WORKER_ID", `${os.hostname()}-${process.pid}`),
  pollIntervalMs: numberEnv("MEETING_BOT_POLL_INTERVAL_MS", 5000),
  heartbeatIntervalMs: numberEnv("MEETING_BOT_HEARTBEAT_INTERVAL_MS", 15000),
  joinTimeoutMs: numberEnv("MEETING_BOT_JOIN_TIMEOUT_MS", 10 * 60 * 1000),
  headed: env("MEETING_BOT_HEADED", "false") === "true",
  slowMoMs: numberEnv("MEETING_BOT_SLOW_MO_MS", 0),
  once: env("MEETING_BOT_RUN_ONCE", "false") === "true",
  artifactDir: env("MEETING_BOT_ARTIFACT_DIR", path.resolve(process.cwd(), "output/playwright/meeting_bot_worker"))
}

main().catch((error) => {
  console.error(`[meeting-bot] fatal: ${truncateError(error)}`)
  process.exitCode = 1
})

async function main() {
  assertConfig()
  console.log(`[meeting-bot] worker ${config.workerId} started`)

  while (true) {
    const run = await claimNextRun()
    if (!run) {
      if (config.once) break
      await sleep(config.pollIntervalMs)
      continue
    }

    await handleRun(run).catch(async (error) => {
      console.error(`[meeting-bot] run ${run.id} failed: ${truncateError(error)}`)
      await postJson(run.failed_path, {
        error_message: truncateError(error),
        metadata: error?.metadata || {}
      })
    })

    if (config.once) break
  }
}

async function handleRun(run) {
  if (run.provider !== "google_meet") {
    await postJson(run.failed_path, {
      error_message: `Provider ${run.provider} is not implemented by the bot worker yet.`
    })
    return
  }

  const collector = new TranscriptCollector()
  const browser = await chromium.launch({
    headless: !config.headed,
    slowMo: config.slowMoMs,
    args: [
      "--disable-dev-shm-usage",
      "--use-fake-ui-for-media-stream",
      "--disable-features=Translate,MediaRouter"
    ]
  })

  let heartbeatTimer = null
  let shouldContinue = true
  let currentStatus = "joining"
  let page = null
  let joinStage = "launching"

  try {
    const context = await browser.newContext({
      viewport: { width: 1440, height: 960 },
      ignoreHTTPSErrors: true
    })
    page = await context.newPage()

    heartbeatTimer = setInterval(() => {
      void sendHeartbeat(run, currentStatus, page, { join_stage: joinStage }).then((result) => {
        if (result && result.continue === false) shouldContinue = false
      }).catch((error) => {
        console.warn(`[meeting-bot] heartbeat failed for run ${run.id}: ${truncateError(error)}`)
      })
    }, config.heartbeatIntervalMs)

    await sendHeartbeat(run, currentStatus, page, { join_stage: joinStage })
    console.log(`[meeting-bot] run ${run.id}: opening ${run.join_url}`)
    await page.goto(run.join_url, { waitUntil: "domcontentloaded", timeout: 60_000 })

    const joinStartedAt = Date.now()
    while (shouldContinue) {
      const joinState = await progressGoogleMeet(page, joinStartedAt, joinStage)
      joinStage = joinState.stage || joinStage
      if (joinState.joined) {
        currentStatus = "recording"
        console.log(`[meeting-bot] run ${run.id}: joined meeting, entering recording state`)
        await sendHeartbeat(run, currentStatus, page, { join_stage: joinStage })
        break
      }
      if (joinState.failure) {
        const artifacts = await captureArtifacts(page, run, "join_failure")
        throw new Error(joinState.failureWithArtifacts(artifacts))
      }
      await sleep(1500)
    }

    while (shouldContinue) {
      await ensureCaptionsEnabled(page)
      collector.addEntries(await scrapeGoogleMeetCaptions(page))

      if (await meetingEnded(page)) {
        shouldContinue = false
        break
      }

      await sleep(1200)
    }

    if (collector.hasContent()) {
      await postJson(run.transcript_complete_path, collector.payload({
        worker_id: config.workerId,
        capture_mode: "captions"
      }))
      console.log(`[meeting-bot] run ${run.id} submitted transcript with ${collector.utterances.length} utterances`)
      return
    }

    const artifacts = await captureArtifacts(page, run, "no_transcript")
    await postJson(run.failed_path, {
      error_message: appendArtifactMessage("Meeting ended or was stopped before any transcript captions were captured.", artifacts),
      metadata: artifactMetadata(artifacts, joinStage, page)
    })
  } catch (error) {
    const artifacts = await captureArtifacts(page, run, "run_error")
    const wrapped = new Error(appendArtifactMessage(truncateError(error), artifacts))
    wrapped.metadata = artifactMetadata(artifacts, joinStage, page)
    throw wrapped
  } finally {
    if (heartbeatTimer) clearInterval(heartbeatTimer)
    await browser.close().catch(() => {})
  }
}

async function progressGoogleMeet(page, joinStartedAt, previousStage) {
  await dismissInterstitials(page)
  await fillDisplayNameIfNeeded(page, config.displayName)
  await ensureMicAndCameraOff(page)

  if (await joinedGoogleMeet(page)) {
    return { joined: true, stage: "joined" }
  }

  if (Date.now() - joinStartedAt > config.joinTimeoutMs) {
    return failureState("Timed out waiting to join the meeting.", previousStage || "join_timeout")
  }

  if (await clickJoinButton(page)) {
    console.log("[meeting-bot] join/request button clicked")
    await sleep(2500)
    return { joined: false, stage: "requested_join" }
  }

  if (await detectJoinDenied(page)) {
    return failureState("Meeting join request was denied or the meeting is unavailable.", "join_denied")
  }

  return { joined: false, stage: previousStage || "waiting_room" }
}

async function dismissInterstitials(page) {
  await clickIfVisible(page, [
    /Got it/i,
    /Continue anyway/i,
    /Dismiss/i,
    /Close/i
  ])
}

async function fillDisplayNameIfNeeded(page, displayName) {
  const inputs = page.locator("input")
  const count = await inputs.count()

  for (let index = 0; index < count; index += 1) {
    const input = inputs.nth(index)
    if (!(await input.isVisible().catch(() => false))) continue
    const metadata = await input.evaluate((element) => ({
      ariaLabel: element.getAttribute("aria-label") || "",
      placeholder: element.getAttribute("placeholder") || "",
      value: element.value || ""
    })).catch(() => null)
    if (!metadata) continue

    const descriptor = `${metadata.ariaLabel} ${metadata.placeholder}`.toLowerCase()
    if (!descriptor.match(/name|guest/i)) continue
    if (String(metadata.value || "").trim().length > 0) return true

    await input.fill(displayName).catch(() => {})
    return true
  }

  return false
}

async function ensureMicAndCameraOff(page) {
  await clickIfVisible(page, [
    /Turn off microphone/i,
    /Turn off mic/i
  ])
  await clickIfVisible(page, [
    /Turn off camera/i,
    /Turn off video/i
  ])
}

async function clickJoinButton(page) {
  return clickIfVisible(page, [
    /Ask to join/i,
    /Request to join/i,
    /Join now/i,
    /^Join$/i
  ])
}

async function ensureCaptionsEnabled(page) {
  if (await hasVisibleControl(page, [ /Turn off captions/i ])) return true
  return clickIfVisible(page, [ /Turn on captions/i, /^Captions$/i ])
}

async function joinedGoogleMeet(page) {
  return hasVisibleControl(page, [
    /Leave call/i,
    /Hang up/i,
    /Turn on captions/i,
    /Turn off captions/i,
    /More options/i
  ])
}

async function detectJoinDenied(page) {
  const bodyText = await page.locator("body").innerText().catch(() => "")
  return /denied|cannot join|can't join|meeting ended|not allowed|someone removed you/i.test(bodyText)
}

async function meetingEnded(page) {
  const bodyText = await page.locator("body").innerText().catch(() => "")
  return /you left the meeting|meeting has ended|call ended|no one else is here/i.test(bodyText)
}

async function scrapeGoogleMeetCaptions(page) {
  return page.evaluate(() => {
    const roots = Array.from(document.querySelectorAll('[aria-live="polite"], [aria-live="assertive"]'))
    const seen = new Map()

    for (const root of roots) {
      const text = String(root.innerText || "").trim()
      if (!text || text.length > 800) continue

      const lines = text.split("\n").map((line) => line.trim()).filter(Boolean)
      if (lines.length < 2) continue

      const speaker = lines[0]
      const spoken = lines.slice(1).join(" ").trim()
      if (!speaker || !spoken) continue
      if (/turn on captions|turn off captions|you left the meeting|ask to join/i.test(`${speaker} ${spoken}`)) continue

      const key = `${speaker}::${spoken}`
      if (!seen.has(key)) {
        seen.set(key, { speaker_name: speaker, text: spoken })
      }
    }

    return Array.from(seen.values())
  }).catch(() => [])
}

async function clickIfVisible(page, patterns) {
  const element = await findVisibleClickable(page, patterns)
  if (!element) return false

  try {
    await element.click({ timeout: 2000 })
    return true
  } catch {
    return false
  }
}

async function hasVisibleControl(page, patterns) {
  return Boolean(await findVisibleClickable(page, patterns))
}

async function findVisibleClickable(page, patterns) {
  const candidates = page.locator("button, [role='button']")
  const count = await candidates.count()

  for (let index = 0; index < count; index += 1) {
    const candidate = candidates.nth(index)
    const visible = await candidate.isVisible().catch(() => false)
    if (!visible) continue

    const description = await candidate.evaluate((element) => {
      return [element.getAttribute("aria-label"), element.textContent].filter(Boolean).join(" ")
    }).catch(() => "")

    if (patterns.some((pattern) => pattern.test(description))) return candidate
  }

  return null
}

async function sendHeartbeat(run, status, page, metadata = {}) {
  const payloadMetadata = {
    ...metadata,
    page_title: page ? await page.title().catch(() => null) : null
  }

  const response = await postJson(run.heartbeat_path, {
    status,
    worker_id: config.workerId,
    metadata: payloadMetadata
  }, { allowConflict: true })

  if (response.status === 409) {
    return response.json || { continue: false }
  }

  return response.json || { continue: true }
}

async function captureArtifacts(page, run, label) {
  if (!page) return null

  const timestamp = new Date().toISOString().replace(/[:.]/g, "-")
  const dir = path.join(config.artifactDir, String(run.id))
  await fs.mkdir(dir, { recursive: true })

  const screenshotPath = path.join(dir, `${label}-${timestamp}.png`)
  const htmlPath = path.join(dir, `${label}-${timestamp}.html`)

  await page.screenshot({ path: screenshotPath, fullPage: true }).catch(() => {})
  const html = await page.content().catch(() => null)
  if (html) {
    await fs.writeFile(htmlPath, html).catch(() => {})
  }

  console.log(`[meeting-bot] artifacts saved for run ${run.id}: ${screenshotPath}`)
  return { screenshotPath, htmlPath }
}

function artifactMetadata(artifacts, joinStage, page) {
  return {
    join_stage: joinStage,
    artifact_screenshot_path: artifacts?.screenshotPath || null,
    artifact_html_path: artifacts?.htmlPath || null,
    page_url: page?.url?.() || null
  }
}

function appendArtifactMessage(message, artifacts) {
  if (!artifacts?.screenshotPath) return message
  return `${message} (artifact: ${artifacts.screenshotPath})`
}

function failureState(message, stage) {
  return {
    joined: false,
    stage,
    failure: message,
    failureWithArtifacts(artifacts) {
      return appendArtifactMessage(message, artifacts)
    }
  }
}

async function claimNextRun() {
  const response = await postJson("/internal/meeting_bot_runs/claim", { worker_id: config.workerId }, { allowNoContent: true })
  if (response.status === 204) return null
  return response.json?.data || null
}

async function postJson(path, payload, { allowNoContent = false, allowConflict = false } = {}) {
  const response = await fetch(buildAbsoluteUrl(config.baseUrl, path), {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${config.internalToken}`,
      "Content-Type": "application/json",
      "Accept": "application/json"
    },
    body: JSON.stringify(payload)
  })

  if (allowNoContent && response.status === 204) {
    return { status: 204, json: null }
  }

  const text = await response.text()
  const json = text ? JSON.parse(text) : null

  if (allowConflict && response.status === 409) {
    return { status: 409, json }
  }

  if (!response.ok) {
    const message = json?.error?.message || `${response.status} ${response.statusText}`
    throw new Error(message)
  }

  return { status: response.status, json }
}

function assertConfig() {
  const missing = []
  if (!config.baseUrl) missing.push("MEETING_BOT_BASE_URL")
  if (!config.internalToken) missing.push("MEETING_BOT_INTERNAL_TOKEN")
  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(", ")}`)
  }
}

function env(name, fallback = "") {
  return process.env[name] || fallback
}

function numberEnv(name, fallback) {
  const value = Number(process.env[name])
  return Number.isFinite(value) && value > 0 ? value : fallback
}
