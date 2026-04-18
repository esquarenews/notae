import test from "node:test";
import assert from "node:assert/strict";

import { NotaeApiClient, NotaeApiError, buildUrl } from "./client.mjs";

test("buildUrl appends query parameters and preserves the path", () => {
  const url = buildUrl("https://notae.example.com", "/api/v1/workspaces", { q: "alpha", limit: 10 });

  assert.equal(url.toString(), "https://notae.example.com/api/v1/workspaces?q=alpha&limit=10");
});

test("client trims trailing slashes from the base url", () => {
  const client = new NotaeApiClient({
    baseUrl: "https://notae.example.com///",
    token: "secret-token",
    fetchImpl: async () => new Response(JSON.stringify({ data: [] }), {
      status: 200,
      headers: { "content-type": "application/json" }
    })
  });

  assert.equal(client.baseUrl, "https://notae.example.com");
});

test("request sends bearer auth and parses json", async () => {
  let receivedRequest = null;
  const fetchImpl = async (url, options) => {
    receivedRequest = { url: url.toString(), options };
    return new Response(JSON.stringify({ data: [ { slug: "alpha-space" } ] }), {
      status: 200,
      headers: { "content-type": "application/json" }
    });
  };

  const client = new NotaeApiClient({
    baseUrl: "https://notae.example.com",
    token: "secret-token",
    fetchImpl
  });

  const workspaces = await client.listWorkspaces({ q: "alpha" });

  assert.deepEqual(workspaces, [ { slug: "alpha-space" } ]);
  assert.equal(receivedRequest.url, "https://notae.example.com/api/v1/workspaces?q=alpha");
  assert.equal(receivedRequest.options.headers.Authorization, "Bearer secret-token");
  assert.equal(receivedRequest.options.headers.Accept, "application/json");
});

test("request raises a NotaeApiError with API error text", async () => {
  const client = new NotaeApiClient({
    baseUrl: "https://notae.example.com",
    token: "secret-token",
    fetchImpl: async () => new Response(JSON.stringify({
      error: { message: "Select a task list before approving." }
    }), {
      status: 422,
      headers: { "content-type": "application/json" }
    })
  });

  await assert.rejects(
    () => client.approveAgentAction({
      workspaceSlug: "alpha-space",
      agentActionId: "draft-1"
    }),
    (error) => {
      assert.ok(error instanceof NotaeApiError);
      assert.equal(error.status, 422);
      assert.equal(error.message, "Select a task list before approving.");
      return true;
    }
  );
});

test("listTaskLists filters client-side when q is provided", async () => {
  const client = new NotaeApiClient({
    baseUrl: "https://notae.example.com",
    token: "secret-token",
    fetchImpl: async () => new Response(JSON.stringify({
      data: [
        { id: "1", name: "Task Inbox" },
        { id: "2", name: "Calendar Backlog" }
      ]
    }), {
      status: 200,
      headers: { "content-type": "application/json" }
    })
  });

  const taskLists = await client.listTaskLists({ workspaceSlug: "alpha-space", q: "task" });

  assert.deepEqual(taskLists, [ { id: "1", name: "Task Inbox" } ]);
});

test("createCalendarEvent posts structured event data", async () => {
  let receivedRequest = null;
  const client = new NotaeApiClient({
    baseUrl: "https://notae.example.com",
    token: "secret-token",
    fetchImpl: async (url, options) => {
      receivedRequest = { url: url.toString(), options };
      return new Response(JSON.stringify({
        data: {
          event: {
            id: "event-1",
            calendar_id: "calendar-1",
            title: "Board review",
            starts_at_utc: "2026-04-20T00:30:00Z",
            ends_at_utc: "2026-04-20T01:30:00Z",
            all_day: false,
            status: "confirmed",
            visibility: "default"
          },
          url: "/w/test-space/kalendarium?view=day"
        }
      }), {
        status: 201,
        headers: { "content-type": "application/json" }
      });
    }
  });

  const result = await client.createCalendarEvent({
    workspaceSlug: "test-space",
    calendarId: "calendar-1",
    title: "Board review",
    startsAt: "2026-04-20T10:30:00+10:00",
    endsAt: "2026-04-20T11:30:00+10:00",
    description: "Review the Q2 board pack",
    location: "Melbourne",
    reminderOffsetsMinutes: [ 10, 30 ]
  });

  assert.equal(receivedRequest.url, "https://notae.example.com/api/v1/workspaces/test-space/kalendarium/events");
  assert.equal(receivedRequest.options.method, "POST");
  assert.deepEqual(JSON.parse(receivedRequest.options.body), {
    kalendarium_event: {
      kalendarium_calendar_id: "calendar-1",
      title: "Board review",
      starts_at: "2026-04-20T10:30:00+10:00",
      ends_at: "2026-04-20T11:30:00+10:00",
      description: "Review the Q2 board pack",
      location: "Melbourne",
      reminder_offsets_minutes: [ 10, 30 ]
    }
  });
  assert.equal(result.event.id, "event-1");
  assert.equal(result.url, "/w/test-space/kalendarium?view=day");
});

test("sendCodexCompletionPush posts notification payload", async () => {
  let receivedRequest = null;
  const client = new NotaeApiClient({
    baseUrl: "https://notae.example.com",
    token: "secret-token",
    fetchImpl: async (url, options) => {
      receivedRequest = { url: url.toString(), options };
      return new Response(JSON.stringify({
        data: {
          notification: {
            id: "notification-1",
            workspace_id: "workspace-1",
            recipient_id: "user-1",
            notification_type: "codex_request_completed",
            title: "Codex finished",
            body: "The task is complete.",
            path: "/w/test-space",
            created_at: "2026-04-18T05:00:00Z"
          },
          url: "/app/notifications/notification-1"
        }
      }), {
        status: 201,
        headers: { "content-type": "application/json" }
      });
    }
  });

  const result = await client.sendCodexCompletionPush({
    workspaceSlug: "test-space",
    title: "Codex finished",
    body: "The task is complete.",
    path: "/w/test-space"
  });

  assert.equal(receivedRequest.url, "https://notae.example.com/api/v1/workspaces/test-space/notifications/codex_completion");
  assert.equal(receivedRequest.options.method, "POST");
  assert.deepEqual(JSON.parse(receivedRequest.options.body), {
    notification: {
      title: "Codex finished",
      body: "The task is complete.",
      path: "/w/test-space"
    }
  });
  assert.equal(result.notification.id, "notification-1");
  assert.equal(result.url, "/app/notifications/notification-1");
});
