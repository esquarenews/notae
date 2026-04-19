# MCP Token Setup

Use this to connect Codex or another MCP client to Notae.

## 1. Create an API token in production

Use the Rails runner through `systemd-run` so the app gets the production environment.

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  /usr/bin/bash -lc 'export ACTIVE_RECORD_ENCRYPTION_BOOTSTRAP_SECRET="$SECRET_KEY_BASE"; bundle exec rails runner "user = User.find_by!(email: \"errol@esquarenews.com.au\"); token = user.api_tokens.create!(name: \"Codex MCP\"); puts token.token"'
```

If this fails, first confirm the env is present:

```bash
sudo systemd-run --wait --collect --pty \
  -p User=esquarenews \
  -p Group=esquarenews \
  -p WorkingDirectory=/home/esquarenews/apps/notae \
  -p EnvironmentFile=/etc/notae/notae.env \
  -p Environment=RAILS_ENV=production \
  /usr/bin/bash -lc 'ruby -e "puts({secret_key_base: ENV[%q[SECRET_KEY_BASE]].to_s.empty? ? %q[missing] : %q[present], bootstrap: ENV[%q[ACTIVE_RECORD_ENCRYPTION_BOOTSTRAP_SECRET]].to_s.empty? ? %q[missing] : %q[present]}.inspect)"'
```

## 2. Add the token to Codex config

Set:

- `NOTAE_BASE_URL`
- `NOTAE_API_TOKEN`

Example:

```toml
[env]
NOTAE_BASE_URL = "https://notae.esquarenews.tech"
NOTAE_API_TOKEN = "paste-token-here"
```

The local Notae MCP client in this repo is documented in:

- `docs/notae_mcp_server.md`

## 3. Verify the API directly

```bash
curl -s https://notae.esquarenews.tech/api/v1/workspaces \
  -H "Authorization: Bearer YOUR_TOKEN"
```

If the token works, the API should return a workspace list instead of an auth error.

## 4. Cloudflare rule

If Cloudflare is in front of production, create or verify a rule that skips WAF challenges for authenticated API traffic. The working pattern is:

- hostname equals `notae.esquarenews.tech`
- URI path starts with `/api/v1/`
- header `Authorization` exists
- action: `Skip`

Without this, Codex MCP calls can be blocked even when the token is valid.

## 5. Common failures

### `Missing Active Record encryption credential: active_record_encryption.deterministic_key`

The token creation shell did not export `ACTIVE_RECORD_ENCRYPTION_BOOTSTRAP_SECRET` from `SECRET_KEY_BASE`. Re-run the exact command above.

### API returns 401

Check:

- the token was copied correctly
- the token belongs to the expected user
- the Authorization header is `Bearer <token>`

### API returns challenge or HTML instead of JSON

Cloudflare is still intercepting `/api/v1/` traffic.
