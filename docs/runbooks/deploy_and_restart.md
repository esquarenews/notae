# Deploy And Restart

Use this on the production host to deploy `main` cleanly.

## Recommended path

```bash
cd /home/esquarenews/apps/notae
bin/deploy-production
```

The script performs the full deploy sequence:

- takes an exclusive deploy lock
- refuses to run with a dirty production checkout
- fetches and fast-forwards `main`
- installs production gems
- stops background workers before migrations
- runs production migrations through `systemd-run` with `/etc/notae/notae.env`
- rebuilds production assets
- restarts the web service, Sidekiq, meeting bot, sync timers, and one-shot sync services when present
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
bundle install
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  -p Environment=PATH=/home/esquarenews/.local/share/gem/ruby/3.4.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/bash -lc 'bundle exec rails db:migrate'
```

If a migration is not intended, stop here and review before continuing.

## 3. Rebuild assets

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  -p Environment=PATH=/home/esquarenews/.local/share/gem/ruby/3.4.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/bash -lc 'bundle exec rails assets:clobber assets:precompile'
```

## 4. Restart application services

```bash
sudo systemctl restart notae
sudo systemctl restart notae-sidekiq
sudo systemctl restart notae-meeting-bot-worker
sudo systemctl start notae-epistularium-sync.service
sudo systemctl start notae-kalendarium-sync.service
```

If the timer should also be verified:

```bash
sudo systemctl restart notae-epistularium-sync.timer
sudo systemctl restart notae-kalendarium-sync.timer
sudo systemctl status notae-epistularium-sync.timer notae-kalendarium-sync.timer --no-pager
```

## 5. Verify the deployment

```bash
sudo systemctl status notae notae-sidekiq notae-meeting-bot-worker --no-pager
sudo systemctl status notae-epistularium-sync.service notae-epistularium-sync.timer --no-pager
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
  -p Environment=RAILS_ENV=production \
  -p Environment=PATH=/home/esquarenews/.local/share/gem/ruby/3.4.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/bash -lc 'bundle exec rails assets:clobber assets:precompile'
sudo systemctl restart notae
```
