import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const serviceDir = dirname(fileURLToPath(import.meta.url));
const launcherPath = resolve(serviceDir, "../../bin/notae-mcp-server");

test("launcher finds Homebrew Node when a macOS GUI PATH does not contain node", () => {
  const result = spawnSync(launcherPath, [], {
    env: {
      HOME: process.env.HOME,
      PATH: "/usr/bin:/bin:/usr/sbin:/sbin"
    },
    encoding: "utf8",
    timeout: 5_000
  });

  assert.equal(result.status, 1);
  assert.match(result.stderr, /NOTAE_BASE_URL is required/);
  assert.doesNotMatch(result.stderr, /env: node: No such file or directory/);
});
