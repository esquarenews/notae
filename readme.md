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

* Deployment instructions

* ...

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
