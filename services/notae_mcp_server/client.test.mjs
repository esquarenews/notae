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
