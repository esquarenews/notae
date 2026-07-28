import test from "node:test";
import assert from "node:assert/strict";
import { createServer } from "node:http";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";

const serviceDir = dirname(fileURLToPath(import.meta.url));
const launcherPath = resolve(serviceDir, "../../bin/notae-mcp-server");

test("official MCP client starts from a macOS GUI PATH and accepts forward-compatible API records", async (context) => {
  const apiServer = createServer((request, response) => {
    assert.equal(request.url, "/api/v1/workspaces?limit=1");
    assert.equal(request.headers.authorization, "Bearer test-token");
    response.writeHead(200, { "Content-Type": "application/json" });
    response.end(JSON.stringify({
      data: [
        {
          id: "workspace-id",
          name: "Development",
          slug: "development",
          role: "owner",
          created_at: "2026-07-29T00:00:00Z",
          future_api_field: "accepted"
        }
      ]
    }));
  });
  await new Promise((resolveListen) => apiServer.listen(0, "127.0.0.1", resolveListen));
  context.after(() => new Promise((resolveClose) => apiServer.close(resolveClose)));

  const address = apiServer.address();
  const transport = new StdioClientTransport({
    command: launcherPath,
    env: {
      HOME: process.env.HOME,
      PATH: "/usr/bin:/bin:/usr/sbin:/sbin",
      NOTAE_BASE_URL: `http://127.0.0.1:${address.port}`,
      NOTAE_API_TOKEN: "test-token"
    },
    stderr: "pipe"
  });
  const client = new Client({ name: "notae-regression-test", version: "1.0.0" });
  context.after(() => client.close());

  await client.connect(transport);
  const tools = await client.listTools();
  const result = await client.callTool({
    name: "list_workspaces",
    arguments: { limit: 1 }
  });

  assert.equal(tools.tools.some((tool) => tool.name === "list_workspaces"), true);
  assert.equal(result.isError, undefined);
  assert.deepEqual(result.structuredContent.workspaces, [
    {
      id: "workspace-id",
      name: "Development",
      slug: "development",
      role: "owner",
      created_at: "2026-07-29T00:00:00Z",
      future_api_field: "accepted"
    }
  ]);
});
