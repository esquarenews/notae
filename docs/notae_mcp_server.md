# Notae MCP Server For Codex

This repo now includes a local MCP stdio server that lets Codex connect to Notae over the existing bearer-token API.

## What it does

- lists accessible Notae workspaces
- searches pages by title
- reads a page as Markdown
- creates a new page from Markdown
- appends Markdown to an existing page
- lists task lists and calendars for approval destinations
- creates calendar events directly in Kalendārium
- creates agent-action drafts in Notae
- approves agent-action drafts when the API token belongs to an approver

The MCP server is intentionally thin. Notae business logic stays in Rails; the MCP layer just translates Codex tool calls into Notae API requests.

## Environment

The MCP sidecar reads these environment variables:

- `NOTAE_BASE_URL`
- `NOTAE_API_TOKEN`

Example:

```bash
export NOTAE_BASE_URL="https://notae.example.com"
export NOTAE_API_TOKEN="paste-a-valid-notae-api-token"
```

## Install sidecar dependencies

```bash
cd /Users/errolschmidt/Documents/notae_app/notae/services/notae_mcp_server
npm install
```

The launcher now bootstraps these dependencies automatically on first run if `node_modules` is missing, so a clean checkout can still start the MCP server. A manual install is still useful when you want to prewarm the sidecar or verify dependencies explicitly.

## Connect from Codex

Add this to [`/Users/errolschmidt/.codex/config.toml`](/Users/errolschmidt/.codex/config.toml):

```toml
[mcp_servers.notae]
command = "/Users/errolschmidt/Documents/notae_app/notae/bin/notae-mcp-server"
env = { NOTAE_BASE_URL = "https://notae.example.com", NOTAE_API_TOKEN = "replace-with-a-real-token" }
```

Then restart Codex so it reloads the MCP server list. If Codex started while the sidecar was broken or missing dependencies, the current session will not discover Notae tools until a restart or a fresh session.

## Notae API token

The MCP server uses the existing `ApiToken` bearer-token model in Notae.

The token must belong to a Notae user who already has workspace access:

- for document read/write: any editor-level user is sufficient
- for agent-action approval: the token user must be an `owner` or `admin` in that workspace

If you do not yet have an API token management UI in your deployment, create one with Rails console or `rails runner`, for example:

```bash
cd /Users/errolschmidt/Documents/notae_app/notae
bundle exec rails runner 'user = User.find_by!(email: "you@example.com"); token = user.api_tokens.create!(name: "Codex MCP"); puts token.token'
```

## Tools exposed to Codex

- `list_workspaces`
- `search_pages`
- `read_page_markdown`
- `create_page_from_markdown`
- `append_markdown_to_page`
- `list_task_lists`
- `list_calendars`
- `create_calendar_event`
- `send_codex_completion_push`
- `list_agent_actions`
- `create_agent_action`
- `approve_agent_action`

Successful Notae write tools also auto-send a completion push for the authenticated user:

- `create_page_from_markdown`
- `append_markdown_to_page`
- `create_calendar_event`
- `create_agent_action`
- `approve_agent_action`

## Notes

- page resources are also exposed through the MCP resource template:
  - `notae://workspace/{workspaceSlug}/pages/{pageId}.md`
- direct calendar event creation requires a writable calendar in the target workspace
- `list_calendars` returns effective `writable` state alongside the raw `read_only` flag so legacy writable provider calendars can still be selected correctly
- `send_codex_completion_push` creates a Notae notification of type `codex_request_completed` and triggers normal web-push delivery for the authenticated user
- the MCP server auto-sends that same push after each successful write action so Codex completions surface on mobile without a second manual tool call
- task drafts still need a destination task list at approval time
- calendar drafts still need a destination calendar at approval time
- the MCP server does not bypass Notae permissions or workspace policy
