# Deploy And Restart

Use this on the production host to deploy `main` cleanly.

## Recommended path

```bash
cd /home/esquarenews/apps/notae
bin/deploy-production --check
bin/deploy-production
```

Run these as `esquarenews`. The deploy script requests sudo authentication before
fetching or changing the release, then uses sudo for systemd operations.

`--check` validates the deploy lock, clean checkout, installed bundle, service
runtime configuration, health endpoint, sign-in page and referenced assets. It
does not fetch code, install gems, migrate databases, build assets or restart
services, and does not require sudo authentication.

### Production Ruby environment

The native services use Ruby 3.4.12 with YJIT from `/opt/notae/ruby-3.4.12` and
the bundle at `/var/www/notae/shared/bundle-ruby-3.4.12`. The login shell can select
a different Ruby or an unconfigured mise Bundler shim.

The script loads the root-managed, shell-compatible runtime settings in
`/etc/notae/ruby-3.4.12.env` before resolving Bundler. It uses that exact executable
for installs and tests. Migration and asset jobs load both `/etc/notae/notae.env`
and the runtime file through systemd and invoke Bundler directly. A login shell
cannot reset their runtime PATH. The application secrets file stays unreadable
to the ordinary deployment shell.

For a future runtime change, update the service drop-ins and pass the matching
`RUNTIME_ENV_FILE`. `BUNDLE_BIN` and `PRODUCTION_PATH` can also be overridden.
The preflight rejects a required service whose runtime file or Bundler executable
differs from the deployment configuration.

The shared lock must remain owned and writable by `esquarenews`. The script
rejects direct execution as another user and refuses symlink locks. If an older
root-run helper left a root-owned lock, have an administrator repair its existing
ownership. Keep the lock inode in place; deleting an active lock can allow two
deployments to run concurrently.

On hosts that previously ran Epistularium, retire its installed units before the
first deploy after email removal (the deploy defaults no longer start them):

```bash
sudo systemctl disable --now notae-epistularium-sync.timer
sudo systemctl stop notae-epistularium-sync.service
sudo systemctl reset-failed notae-epistularium-sync.service
```

The script performs the full deploy sequence:

- takes an exclusive deploy lock
- refuses to run with a dirty production checkout
- fetches and fast-forwards `main`
- installs production gems
- stops background workers before migrations
- runs production migrations through `systemd-run` with both application and runtime environment files
- rebuilds production assets
- restarts the web service, Sidekiq, meeting bot, calendar sync timer, and one-shot calendar sync service when present
- verifies systemd health, `/up`, sign-in HTML, and linked CSS/JS assets

Useful overrides:

```bash
APP_URL=https://notae.esquarenews.tech bin/deploy-production
RUN_TESTS=1 bin/deploy-production
RUN_ASSET_CLOBBER=0 bin/deploy-production
RUN_OPTIONAL_SYNC=0 RESTART_TIMERS=0 bin/deploy-production
```

The script prints the previous git revision and rollback starting point if a step fails.

### If deploy stops on a dirty production checkout

The script intentionally refuses to deploy over local production edits. Inspect first:

```bash
cd /home/esquarenews/apps/notae
git status --short
```

If the only dirty files are meeting-bot runtime files like:

```text
?? services/meeting_bot_worker/.env.production
?? services/meeting_bot_worker/node_modules/
?? services/meeting_bot_worker/output/
?? services/meeting_bot_worker/package-lock.json
```

keep the files in place and ignore them locally on the production host:

```bash
cat >> .git/info/exclude <<'EOF'
services/meeting_bot_worker/.env.production
services/meeting_bot_worker/node_modules/
services/meeting_bot_worker/output/
services/meeting_bot_worker/package-lock.json
EOF

git status --short
bin/deploy-production
```

Then choose one path:

```bash
# Keep intentional changes
git add <files>
git commit -m "Describe production change"
git push origin main

# Preserve temporary production-only changes without deploying them
git stash push --include-untracked -m "production dirty state before deploy $(date -Iseconds)"

# Discard generated/unwanted files only after reviewing them
git clean -nd
git restore <tracked-file>
git clean -fd <untracked-path>
```

After the production checkout is clean, rerun:

```bash
bin/deploy-production
```

## Manual fallback

Use this only if the script cannot run and you need to perform the steps manually.

## 1. Update the code

```bash
cd /home/esquarenews/apps/notae
git fetch origin
git checkout main
git pull --ff-only origin main
```

## 2. Install gems and run migrations

```bash
set -a
source /etc/notae/ruby-3.4.12.env
set +a
/opt/notae/ruby-3.4.12/bin/bundle _4.0.3_ install
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p EnvironmentFile=/etc/notae/ruby-3.4.12.env \
  -p Environment=RAILS_ENV=production \
  /opt/notae/ruby-3.4.12/bin/bundle _4.0.3_ exec rails db:migrate
```

If a migration is not intended, stop here and review before continuing.

## 3. Rebuild assets

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p EnvironmentFile=/etc/notae/ruby-3.4.12.env \
  -p Environment=RAILS_ENV=production \
  /opt/notae/ruby-3.4.12/bin/bundle _4.0.3_ exec rails assets:clobber assets:precompile
```

## 4. Restart application services

On the first deployment after removing Epistularium, disable its retired timer and service:

```bash
sudo systemctl disable --now notae-epistularium-sync.timer
sudo systemctl stop notae-epistularium-sync.service
sudo systemctl reset-failed notae-epistularium-sync.service
```

```bash
sudo systemctl restart notae
sudo systemctl restart notae-sidekiq
sudo systemctl restart notae-meeting-bot-worker
sudo systemctl start notae-kalendarium-sync.service
```

If the timer should also be verified:

```bash
sudo systemctl restart notae-kalendarium-sync.timer
sudo systemctl status notae-kalendarium-sync.timer --no-pager
```

## 5. Verify the deployment

```bash
sudo systemctl status notae notae-sidekiq notae-meeting-bot-worker --no-pager
sudo systemctl status notae-kalendarium-sync.service notae-kalendarium-sync.timer --no-pager
journalctl -u notae -n 100 --no-pager -o cat
journalctl -u notae-sidekiq -n 100 --no-pager -o cat
```

Check that sign-in HTML is pointing at compiled assets:

```bash
curl -s https://notae.esquarenews.tech/users/sign_in | rg '/assets/application.*\.(css|js)'
```

Then check that each linked asset returns `200`:

```bash
curl -s https://notae.esquarenews.tech/users/sign_in \
  | rg -o '/assets/[^"]+\.(css|js)' \
  | while read -r asset; do
      curl -s -o /dev/null -w "%{http_code} ${asset}\n" "https://notae.esquarenews.tech${asset}"
    done
```

If the CSS or JS link is missing or returns `404`, the asset build or production asset serving is still broken.

## 6. Quick rollback checklist

If the deploy is bad:

- confirm whether the failure is code, migration, or asset related
- if migrations already ran, do not blindly roll back without checking data impact
- restore the prior git revision, rebuild assets, and restart the same services
- keep Sidekiq stopped if the release introduced a destructive job failure pattern

## Common failures

### `bundle: command not found`

The service PATH is wrong. Compare the unit file with the working production PATH:

```bash
sudo systemctl cat notae
sudo systemctl cat notae-sidekiq
```

### JS and CSS missing after deploy

Usually one of:

- assets were not precompiled on the deployed revision
- the compiled files were removed after precompile
- the app is still serving an older manifest

Re-run:

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p EnvironmentFile=/etc/notae/ruby-3.4.12.env \
  -p Environment=RAILS_ENV=production \
  /opt/notae/ruby-3.4.12/bin/bundle _4.0.3_ exec rails assets:clobber assets:precompile
sudo systemctl restart notae
```
