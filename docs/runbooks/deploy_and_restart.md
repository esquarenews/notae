# Deploy And Restart

Use this after pulling new code to production.

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
bundle exec rails db:migrate
```

If a migration is not intended, stop here and review before continuing.

## 3. Rebuild assets

```bash
bundle exec rails assets:clobber
bundle exec rails assets:precompile
```

## 4. Restart application services

```bash
sudo systemctl restart notae
sudo systemctl restart notae-sidekiq
sudo systemctl restart notae-meeting-bot-worker
sudo systemctl start notae-epistularium-sync.service
```

If the timer should also be verified:

```bash
sudo systemctl restart notae-epistularium-sync.timer
sudo systemctl status notae-epistularium-sync.timer --no-pager
```

## 5. Verify the deployment

```bash
sudo systemctl status notae notae-sidekiq notae-meeting-bot-worker --no-pager
sudo systemctl status notae-epistularium-sync.service notae-epistularium-sync.timer --no-pager
journalctl -u notae -n 100 --no-pager -o cat
journalctl -u notae-sidekiq -n 100 --no-pager -o cat
```

Check that sign-in HTML is pointing at compiled assets:

```bash
curl -s https://notae.esquarenews.tech/users/sign_in | rg '/assets/application.*\.(css|js)'
```

If the CSS or JS link is missing, the asset build or production asset serving is still broken.

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
bundle exec rails assets:clobber
bundle exec rails assets:precompile
sudo systemctl restart notae
```
