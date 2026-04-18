import test from "node:test";
import assert from "node:assert/strict";

import { autoPushConfigFor, buildAutoPushPayload } from "./auto_push.mjs";

test("autoPushConfigFor returns null for read-only tools", () => {
  assert.equal(autoPushConfigFor("list_workspaces"), null);
  assert.equal(autoPushConfigFor("read_page_markdown"), null);
});

test("buildAutoPushPayload creates a page-completion payload", () => {
  const payload = buildAutoPushPayload("create_page_from_markdown", {
    workspaceSlug: "personal",
    result: {
      page: {
        id: "page-123",
        title: "Board notes"
      }
    }
  });

  assert.deepEqual(payload, {
    workspaceSlug: "personal",
    title: "Notae page created",
    body: "Created page: Board notes",
    path: "/w/personal/pages/page-123"
  });
});

test("buildAutoPushPayload uses result url when available", () => {
  const payload = buildAutoPushPayload("create_calendar_event", {
    workspaceSlug: "personal",
    result: {
      event: { title: "Adwen to movies" },
      url: "/w/personal/kalendarium?view=day"
    }
  });

  assert.deepEqual(payload, {
    workspaceSlug: "personal",
    title: "Calendar event created",
    body: "Created event: Adwen to movies",
    path: "/w/personal/kalendarium?view=day"
  });
});

test("buildAutoPushPayload falls back to workspace agent actions path", () => {
  const payload = buildAutoPushPayload("create_agent_action", {
    workspaceSlug: "marketing",
    result: {
      id: "agent-1",
      title: "Reply to client"
    }
  });

  assert.deepEqual(payload, {
    workspaceSlug: "marketing",
    title: "Agent action created",
    body: "Created draft: Reply to client",
    path: "/w/marketing/agent_actions"
  });
});
