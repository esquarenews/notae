## Meeting Bot Worker

This worker claims queued online meeting runs from Rails and attempts to join Google Meet as a guest using Playwright.

### Current scope

- Supported now: `google_meet`
- Not yet supported: `zoom`, `teams`
- Transcript source: live captions scraped from the meeting page

### Required environment

```bash
export MEETING_BOT_BASE_URL="https://your-notae-host.example"
export MEETING_BOT_INTERNAL_TOKEN="same-token-used-by-rails"
```

### Optional environment

```bash
export MEETING_BOT_DISPLAY_NAME="Notae Bot"
export MEETING_BOT_WORKER_ID="meeting-bot-1"
export MEETING_BOT_POLL_INTERVAL_MS="5000"
export MEETING_BOT_HEARTBEAT_INTERVAL_MS="15000"
export MEETING_BOT_JOIN_TIMEOUT_MS="600000"
export MEETING_BOT_HEADED="false"
export MEETING_BOT_SLOW_MO_MS="0"
export MEETING_BOT_ARTIFACT_DIR="./output/playwright/meeting_bot_worker"
```

### Start

```bash
cd services/meeting_bot_worker
npm install
npx playwright install chromium
npm start
```

### Notes

- Rails only queues meeting bot runs. This worker must be running for scheduled online capture to actually join a meeting.
- When the app stops a meeting, the worker exits on the next heartbeat conflict and submits any collected captions as transcript input before stopping.
- Failed join attempts write browser artifacts to `MEETING_BOT_ARTIFACT_DIR/<run-id>/` so you can inspect the actual meeting page state.

### Production service

There is a systemd template at:

```bash
deploy/systemd/notae-meeting-bot-worker.service.example
```

Typical setup:

```bash
cd /path/to/notae/services/meeting_bot_worker
cp .env.production.example .env.production
# edit values

npm install
npx playwright install chromium

sudo cp /path/to/notae/deploy/systemd/notae-meeting-bot-worker.service.example /etc/systemd/system/notae-meeting-bot-worker.service
# replace {{APP_ROOT}}, {{APP_USER}}, {{APP_GROUP}} in the copied service file

sudo systemctl daemon-reload
sudo systemctl enable --now notae-meeting-bot-worker
sudo systemctl status notae-meeting-bot-worker --no-pager
```
