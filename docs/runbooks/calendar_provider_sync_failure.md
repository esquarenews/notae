# Calendar Provider Sync Failure

Use this when provider calendars are missing, stale, not writable, or event changes do not propagate.

## 1. Identify the failure mode

Most calendar issues fall into one of these:

- connection sync is stale and provider calendars are not refreshing
- provider-backed event write failed
- the calendar exists but is not marked writable
- the app can edit a calendar in the UI, but external tooling cannot see it as writable yet

## 2. Check the scheduler

```bash
sudo systemctl status notae-kalendarium-sync.timer --no-pager
systemctl list-timers --all | rg kalendarium
```

The timer should be active and should show the next run.

## 3. Run a calendar sync cycle manually

```bash
sudo systemctl start notae-kalendarium-sync.service
sudo systemctl status notae-kalendarium-sync.service --no-pager
journalctl -u notae-kalendarium-sync.service -n 120 -l --no-pager -o cat
```

Expected:

- the oneshot service finishes successfully
- it enqueues `Kalendarium::SyncConnectionJob`

## 4. Check Sidekiq for calendar jobs

```bash
sudo systemctl status notae-sidekiq --no-pager
journalctl -u notae-sidekiq -n 300 --no-pager -o cat | rg 'Kalendarium::SyncConnectionJob|Kalendarium::SyncCalendarJob|Kalendarium|google|icloud|calendar' -C 4
```

Relevant jobs:

- `Kalendarium::SyncConnectionJob`
- `Kalendarium::SyncCalendarJob`

## 5. Inspect provider connection state from Rails

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  -p Environment=PATH=/home/esquarenews/.local/share/gem/ruby/3.4.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/bash -lc 'bundle exec rails runner - <<'"'"'RUBY'"'"'
KalendariumConnection.includes(:kalendarium_calendars).order(:provider, :created_at).find_each do |connection|
  writable = connection.kalendarium_calendars.select(&:writable?).count
  puts [
    "id=#{connection.id}",
    "provider=#{connection.provider}",
    "workspace=#{connection.workspace.slug}",
    "enabled=#{connection.enabled?}",
    "calendars=#{connection.kalendarium_calendars.size}",
    "writable=#{writable}"
  ].join(" | ")
end
RUBY'
```

## 6. Force a connection sync

If the provider calendar list is stale:

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  -p Environment=PATH=/home/esquarenews/.local/share/gem/ruby/3.4.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/bash -lc 'bundle exec rails runner "connection = KalendariumConnection.find(CONNECTION_ID); Kalendarium::SyncConnectionJob.perform_now(connection.id)"'
```

Replace `CONNECTION_ID` before running it.

## 7. Force a single calendar sync

If one known provider-backed calendar is stale:

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  -p Environment=PATH=/home/esquarenews/.local/share/gem/ruby/3.4.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/bash -lc 'bundle exec rails runner "calendar = KalendariumCalendar.find(CALENDAR_ID); Kalendarium::SyncCalendarJob.perform_later(calendar.id); puts calendar.id"'
```

Replace `CALENDAR_ID` before running it.

## 8. Confirm writable calendar visibility

If the UI can write to a calendar but external tooling cannot see it:

- re-run the connection sync
- inspect the connection in Operations settings, which reports writable calendar counts
- verify the MCP or API serializer now includes the calendar as writable

The production fix for this class of issue is code-level. External tools only see what the app exposes after provider sync and policy filtering.

## 9. Common failures

### Timer is healthy, but calendars still look stale

Check whether:

- `notae-kalendarium-sync.service` is enqueueing jobs
- `notae-sidekiq` is actually consuming them
- the affected connection is still enabled and not stuck in `sync_error`

### Provider auth expired

The connection will usually stay present but sync jobs will fail repeatedly. Reconnect the provider from settings, then run a connection sync.

### Calendar writes do not appear remotely

Inspect Sidekiq for provider adapter errors. A successful local save with a failed provider write usually points to `Kalendarium::ProviderEventSyncService` or the underlying provider adapter.

### Writable calendar count is zero

The provider may not expose writable targets for that account, or the sync code has not refreshed the calendar list yet.
