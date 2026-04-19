# Notae Production Runbooks

These runbooks are written for the current production layout used in Notae:

- app root: `/home/esquarenews/apps/notae`
- app user: `esquarenews`
- env file: `/etc/notae/notae.env`
- Rails service: `notae`
- Sidekiq service: `notae-sidekiq`
- meeting bot worker: `notae-meeting-bot-worker`
- Epistularium timer: `notae-epistularium-sync.timer`
- Epistularium oneshot service: `notae-epistularium-sync.service`

If production differs, adjust the paths and service names before running commands.

## Runbooks

- [Deploy and restart](./deploy_and_restart.md)
- [Sidekiq failure](./sidekiq_failure.md)
- [Email sync failure](./email_sync_failure.md)
- [Push notification failure](./push_notification_failure.md)
- [MCP token setup](./mcp_token_setup.md)
- [Calendar provider sync failure](./calendar_provider_sync_failure.md)

## Common checks

```bash
sudo systemctl status notae notae-sidekiq notae-meeting-bot-worker --no-pager
sudo systemctl status notae-epistularium-sync.timer --no-pager
systemctl list-timers --all | rg epistularium
redis-cli ping
```

## Safe Rails runner pattern

Use `systemd-run` for production console tasks so the command inherits the same environment files as the services:

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  -p Environment=PATH=/home/esquarenews/.local/share/gem/ruby/3.4.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/bash -lc 'bundle exec rails runner - <<'"'"'RUBY'"'"'
puts Rails.env
RUBY'
```

If token creation or encrypted attributes fail with `Missing Active Record encryption credential`, export the bootstrap secret inside the same shell:

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  /usr/bin/bash -lc 'export ACTIVE_RECORD_ENCRYPTION_BOOTSTRAP_SECRET="$SECRET_KEY_BASE"; bundle exec rails runner "puts :ok"'
```
