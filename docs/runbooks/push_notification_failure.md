# Push Notification Failure

Use this when the Notae notification center updates but device push does not arrive.

## 1. Confirm server-side prerequisites

```bash
sudo grep -E 'VAPID_PUBLIC_KEY|VAPID_PRIVATE_KEY|VAPID_SUBJECT' /etc/notae/notae.env
curl -I https://notae.esquarenews.tech/service-worker.js
curl -I https://notae.esquarenews.tech/manifest.webmanifest
curl -s https://notae.esquarenews.tech/users/sign_in | rg 'data-pwa-web-push-public-key-value'
```

Expected:

- manifest and service worker return `200`
- the sign-in HTML includes the public VAPID key

## 2. Check subscription readiness

In the app, use Settings > Notifications and verify:

- browser permission is granted
- device subscription exists
- test push delivery is verified
- banner confirmation is marked after a successful push

## 3. Inspect the latest subscription from Rails

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  -p Environment=PATH=/home/esquarenews/.local/share/gem/ruby/3.4.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/bash -lc 'bundle exec rails runner - <<'"'"'RUBY'"'"'
u = User.find_by!(email: "errol@esquarenews.com.au")
puts "subscriptions=#{u.web_push_subscriptions.count}"
u.web_push_subscriptions.order(created_at: :desc).limit(5).each do |s|
  puts [
    "id=#{s.id}",
    "host=#{URI.parse(s.endpoint).host rescue "invalid"}",
    "created_at=#{s.created_at}",
    "last_delivered_at=#{s.last_delivered_at || "-"}",
    "last_error_at=#{s.last_error_at || "-"}",
    "last_error_message=#{s.last_error_message || "-"}"
  ].join(" | ")
end
RUBY'
```

## 4. Trigger a real notification

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  -p Environment=PATH=/home/esquarenews/.local/share/gem/ruby/3.4.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/bash -lc 'bundle exec rails runner - <<'"'"'RUBY'"'"'
u = User.find_by!(email: "errol@esquarenews.com.au")
w = u.workspaces.first or raise("No workspace for user")
notification = Notification.create!(
  workspace: w,
  recipient: u,
  actor: u,
  notification_type: Notification::TYPE_MENTION,
  metadata: {}
)
puts "notification_id=#{notification.id}"
RUBY'
```

Then inspect Sidekiq:

```bash
journalctl -u notae-sidekiq --since "10 minutes ago" --no-pager -o cat | rg 'WebPush|web push|push' -C 4
```

## 5. Known failure patterns

### `OpenSSL::PKey::PKeyError: pkeys are immutable on OpenSSL 3.0`

That means the OpenSSL 3 compatibility shim is missing or not loaded. The repo carries the fix in:

- `config/initializers/webpush_openssl_compat.rb`

Deploy the current code and restart Sidekiq:

```bash
sudo systemctl restart notae-sidekiq
```

### Test push says success, but there is no banner on device

The server path may be working while the browser or OS is still suppressing banners. Check:

- site notification permission in the browser
- macOS or iOS system notification permissions for the browser or installed PWA
- the app readiness center, which now records whether the user confirmed seeing the device banner

### Notification center updates, but device push never enqueues

Confirm the notification type is enabled for push, the user has at least one `web_push_subscription`, and Sidekiq is running.
