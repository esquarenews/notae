# Sidekiq Failure

Use this when jobs are not running, scheduled work is backing up, or the UI shows queued work that never completes.

## 1. Check the service

```bash
sudo systemctl status notae-sidekiq --no-pager
journalctl -u notae-sidekiq -n 200 --no-pager -o cat
redis-cli ping
```

Expected:

- service is `active (running)`
- Redis returns `PONG`

## 2. Check queue depth

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  -p Environment=PATH=/home/esquarenews/.local/share/gem/ruby/3.4.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/bash -lc 'bundle exec rails runner - <<'"'"'RUBY'"'"'
require "sidekiq/api"
Sidekiq::Queue.all.each { |queue| puts "#{queue.name}=#{queue.size}" }
puts "retry=#{Sidekiq::RetrySet.new.size}"
puts "dead=#{Sidekiq::DeadSet.new.size}"
RUBY'
```

Current queues that matter operationally:

- `default`
- `epistularium_backfill`

## 3. Restart cleanly

```bash
sudo systemctl restart notae-sidekiq
sudo systemctl status notae-sidekiq --no-pager
journalctl -u notae-sidekiq --since "2 minutes ago" --no-pager -o cat
```

## 4. Common failure patterns

### `bundle: command not found`

The Sidekiq unit does not have the correct PATH. Confirm:

```bash
sudo systemctl cat notae-sidekiq
```

The unit should run through `/usr/bin/bash -lc` and include the Ruby gem bin directory in PATH.

### Redis connection failures

Check:

```bash
sudo grep -E 'REDIS_URL|ACTIVE_JOB_QUEUE_ADAPTER' /etc/notae/notae.env
redis-cli -u redis://127.0.0.1:6379/0 ping
```

### Jobs are running, but a specific feature is still stuck

Filter logs by job name:

```bash
journalctl -u notae-sidekiq -n 300 --no-pager -o cat | rg 'Epistularium|Kalendarium|WebPush|Search::|Agent'
```

Useful job classes:

- `Epistularium::SyncConnectionJob`
- `Kalendarium::SyncConnectionJob`
- `Kalendarium::SyncCalendarJob`
- `WebPush::DeliverNotificationJob`

## 5. When to stop and escalate

Stop here and investigate code if:

- the dead set is growing
- the same job is retrying with the same exception
- job failures started immediately after a deploy
- Sidekiq is consuming the queue, but the wrong jobs are being enqueued
