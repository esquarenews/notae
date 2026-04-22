# Backup And Restore

Use this runbook to create consistent production backups and to rehearse recovery for Notae.

The current production shape matters:

- PostgreSQL primary database: `notae_production`
- PostgreSQL cache database: `notae_production_cache`
- PostgreSQL queue database: `notae_production_queue`
- PostgreSQL cable database: `notae_production_cable`
- Active Storage service: local disk
- Active Storage path: `/home/esquarenews/apps/notae/storage`

## Recommended operating cadence

Until a managed backup platform replaces this, use this baseline:

- nightly full backup of all four PostgreSQL databases plus the `storage/` directory
- one pre-deploy backup before any production migration with destructive risk
- one weekly restore rehearsal into a non-production environment
- retention target: keep at least 7 daily backups, 4 weekly backups, and 3 monthly backups

This is a baseline, not a substitute for infrastructure-level snapshots if those are available.

## Create a backup

The repo now includes an executable helper:

```bash
cd /home/esquarenews/apps/notae
script/ops/backup_notae_production.sh
```

By default it:

- loads `/etc/notae/notae.env`
- dumps all Notae PostgreSQL databases in custom `pg_dump` format
- archives the Rails `storage/` directory
- writes a `metadata.env` file with the git revision and backup time
- writes `SHA256SUMS` for the backup artifacts

Important overrides:

```bash
BACKUP_ROOT=/var/backups/notae \
APP_ROOT=/home/esquarenews/apps/notae \
ENV_FILE=/etc/notae/notae.env \
script/ops/backup_notae_production.sh
```

## Restore from a backup

The repo also includes a guarded restore helper:

```bash
cd /home/esquarenews/apps/notae
NOTAE_RESTORE_CONFIRM=restore script/ops/restore_notae_production.sh /var/backups/notae/20260419_190000
```

By default it:

- stops the app services
- recreates the four PostgreSQL databases from the backup dumps
- replaces `storage/` with the archived copy
- restarts the app services

If you need to manage service stop/start manually:

```bash
NOTAE_RESTORE_CONFIRM=restore \
SKIP_SERVICE_CONTROL=1 \
script/ops/restore_notae_production.sh /var/backups/notae/20260419_190000
```

## Post-restore verification

After a restore:

```bash
sudo systemctl status notae notae-sidekiq notae-meeting-bot-worker --no-pager
sudo systemctl status notae-epistularium-sync.timer notae-kalendarium-sync.timer --no-pager
curl -I https://notae.esquarenews.tech/service-worker.js
curl -s https://notae.esquarenews.tech/users/sign_in | rg '/assets/application.*\\.(css|js)'
redis-cli ping
```

Then verify in the app:

- sign in works
- a representative Nota opens
- a representative Grid opens
- one recent uploaded asset or cover image is visible
- one recent email and one recent calendar connection render normally

## Attachment and file recovery drill

Run the local rehearsal first after changing the backup tooling:

```bash
cd /home/esquarenews/apps/notae
script/ops/rehearse_storage_recovery_locally.sh
```

This creates a temporary storage archive, restores it into a temporary storage tree, and runs the same verifier used for staging or production rehearsal.

To verify storage recovery without a full rollback:

1. restore a backup into a non-production environment
2. identify one known uploaded file or cover image
3. run the verifier against the restored `storage/` tree
4. confirm the file renders in-app

Use the helper:

```bash
cd /home/esquarenews/apps/notae
script/ops/verify_notae_storage_recovery.sh \
  /var/backups/notae/20260419_190000 \
  /home/esquarenews/apps/notae-staging/storage \
  uploads/2026/04/sample-file.png
```

The verifier:

- compares the archived file manifest against the restored `storage/` tree
- fails if any archived files are missing from the restored copy
- optionally verifies one specific expected file path
- reports extra restored files separately so generated derivatives are visible during the drill

The storage archive contents can still be listed directly when needed:

```bash
tar -tzf /var/backups/notae/20260419_190000/storage.tar.gz | head
```

## Migration rollback readiness

Use the rollback readiness checker before any deploy that includes migrations:

```bash
cd /home/esquarenews/apps/notae
script/ops/check_migration_rollback_readiness.rb --strict db/migrate/20260422000000_example.rb
```

For all pending migrations in a local checkout, pass the specific files from the deploy diff rather than the entire historical migration directory. The checker reports:

- `OK` when the migration has no risky operations
- `REVIEW` when risky operations have a code-supported rollback path
- `BACKUP_REQUIRED` when the migration is restore-only and needs a rehearsed backup before production

Before a migration with destructive risk:

- create a fresh backup with `script/ops/backup_notae_production.sh`
- run `shasum -a 256 -c SHA256SUMS` inside the backup directory
- inspect the migration for irreversible operations
- run `script/ops/check_migration_rollback_readiness.rb --strict` against the migration file or deploy diff
- confirm whether rollback is code-supported or restore-only
- rehearse restore-only rollback in a non-production environment before deploying
- if rollback is restore-only, treat the backup as mandatory and verify its artifact checksums before deploy

## Notes

- Restoring backups over a live production system is destructive. Use a maintenance window.
- The restore helper requires `NOTAE_RESTORE_CONFIRM=restore` on purpose.
- The backup and restore helpers assume the current production layout. Override environment variables if the host layout differs.
