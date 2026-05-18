# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

## Production deployment

Production deploys should be run from the production host with the checked-in deploy script:

```bash
cd /home/esquarenews/apps/notae
bin/deploy-production
```

The script is designed to account for the full Notae production deploy path:

- takes an exclusive deploy lock so two deploys cannot run at once
- refuses to run with a dirty production checkout
- fetches and fast-forwards `main` from `origin`
- installs production gems
- optionally runs the test suite with `RUN_TESTS=1`
- stops optional background workers before migrations
- runs production migrations through `systemd-run` using `/etc/notae/notae.env`
- rebuilds production assets
- restarts the web service, Sidekiq, meeting bot worker, sync timers, and one-shot sync services when present
- verifies required systemd service health
- checks `/up`
- checks the sign-in page and verifies linked compiled CSS/JS assets return successfully
- prints the previous git revision and rollback starting point if a step fails

Useful overrides:

```bash
APP_URL=https://notae.esquarenews.tech bin/deploy-production
RUN_TESTS=1 bin/deploy-production
RUN_ASSET_CLOBBER=0 bin/deploy-production
RUN_OPTIONAL_SYNC=0 RESTART_TIMERS=0 bin/deploy-production
```

For the detailed runbook, manual fallback commands, common failures, and rollback notes, see:

- [`bin/deploy-production`](bin/deploy-production)
- [`docs/runbooks/deploy_and_restart.md`](docs/runbooks/deploy_and_restart.md)

## Email notifications setup (Dev + Production)

Email notifications are sent via `ActionMailer` and queued with Sidekiq (`deliver_later`).

### Development (local inbox with Mailpit)

1. Start Mailpit:

```bash
docker run -d --name mailpit -p 1025:1025 -p 8025:8025 axllent/mailpit
```

2. Set development environment variables:

```bash
SMTP_ADDRESS=127.0.0.1
SMTP_PORT=1025
SMTP_DOMAIN=localhost
SMTP_ENABLE_STARTTLS_AUTO=false
MAIL_FROM="Notae <noreply@notae.local>"
APP_HOST=localhost
APP_PORT=3000
```

3. Open the mailbox UI:

- [http://localhost:8025](http://localhost:8025)

### Production (real SMTP provider)

Use a provider such as Postmark, Resend, or Amazon SES and set:

```bash
SMTP_ADDRESS=<provider-host>
SMTP_PORT=587
SMTP_USERNAME=<provider-username>
SMTP_PASSWORD=<provider-password>
SMTP_AUTHENTICATION=plain
SMTP_ENABLE_STARTTLS_AUTO=true
MAIL_FROM="Notae <noreply@yourdomain.com>"
APP_HOST=<your-production-host>
APP_PORT=443
```

### Background jobs

Because mail delivery uses `deliver_later`, production requires:

- Redis running
- Sidekiq running

### DNS deliverability (production)

Configure and verify:

- SPF
- DKIM
- DMARC

### Smoke test checklist

1. Create a comment with an `@email` mention in a workspace.
2. Confirm a `Notification` record is created.
3. Confirm Sidekiq processes the mail job.
4. Confirm email is received by recipient.
5. Confirm links in the email use the correct host.
