# Email Sync Failure

Use this when Gmail, IMAP, or Amazon WorkMail mailboxes stop refreshing or backfill appears stalled.

## 1. Check the scheduler

```bash
sudo systemctl status notae-epistularium-sync.timer --no-pager
systemctl list-timers --all | rg epistularium
```

The timer should be active and should show the next run.

## 2. Run a sync cycle manually

```bash
sudo systemctl start notae-epistularium-sync.service
sudo systemctl status notae-epistularium-sync.service --no-pager
journalctl -u notae-epistularium-sync.service -n 120 -l --no-pager -o cat
```

Expected:

- the oneshot service finishes successfully
- it enqueues `Epistularium::SyncConnectionJob`

## 3. Confirm Sidekiq is consuming the queued jobs

```bash
sudo systemctl status notae-sidekiq --no-pager
journalctl -u notae-sidekiq -n 300 --no-pager -o cat | rg 'Epistularium::SyncConnectionJob|Sidekiq|This message cannot be decoded|full_backfill|incremental' -C 4
```

## 4. Read the sync state from the app model

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  -p Environment=PATH=/home/esquarenews/.local/share/gem/ruby/3.4.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/bash -lc 'bundle exec rails runner - <<'"'"'RUBY'"'"'
EpistulariumAccount.enabled.order(:email).find_each do |account|
  puts [
    account.email,
    "provider=#{account.provider}",
    "fresh=#{account.last_fresh_sync_at || "-"}",
    "backfill=#{account.last_backfill_sync_at || "-"}",
    "pending_backfill=#{account.full_backfill_pending?}",
    "last_synced=#{account.last_synced_at || "-"}"
  ].join(" | ")
end
RUBY'
```

Interpretation:

- `last_fresh_sync_at` is the freshness scheduler source of truth
- `last_backfill_sync_at` tracks the low-priority history pass
- `full_backfill_pending?` means the trailing 12-month backfill is not done yet

## 5. Force a single account refresh

Use this when one mailbox is stale but the scheduler is otherwise healthy.

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  -p Environment=PATH=/home/esquarenews/.local/share/gem/ruby/3.4.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/bash -lc 'bundle exec rails runner "account = EpistulariumAccount.find_by!(email: \"user@example.com\"); Epistularium::SyncConnectionJob.perform_now(account.id, mode: \"incremental\")"'
```

Replace the email before running it.

## 6. Known failure patterns

### Timer runs, but nothing new appears

Check whether:

- `notae-epistularium-sync.service` is enqueueing jobs
- `notae-sidekiq` is actually consuming them
- the UI is showing fresh mail based on new messages, but settings are still reading stale sync timestamps

### WorkMail or IMAP fails with `This message cannot be decoded as _entire_ message`

That indicates a message-level parsing failure during IMAP fetch. Inspect the failing mailbox in Sidekiq logs and confirm the latest adapter code is deployed before retrying.

### Backfill appears slow

This can be normal. Fresh mail runs on `default` every 10 minutes, while older history moves through `epistularium_backfill` on a lower-priority queue.
