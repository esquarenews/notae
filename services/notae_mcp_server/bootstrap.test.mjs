import test from "node:test";
import assert from "node:assert/strict";

import { ensureSidecarDependencies, hasInstalledDependencies } from "./bootstrap.mjs";

test("hasInstalledDependencies returns true when all required packages are present", () => {
  const serviceDir = "/tmp/notae-mcp";
  const seenPaths = [];
  const exists = (path) => {
    seenPaths.push(path);
    return path.endsWith("@modelcontextprotocol/sdk/package.json") || path.endsWith("zod/package.json");
  };

  assert.equal(hasInstalledDependencies({ serviceDir, exists }), true);
  assert.deepEqual(seenPaths, [
    "/tmp/notae-mcp/node_modules/@modelcontextprotocol/sdk/package.json",
    "/tmp/notae-mcp/node_modules/zod/package.json"
  ]);
});

test("ensureSidecarDependencies installs packages when node_modules is missing", () => {
  const serviceDir = "/tmp/notae-mcp";
  let installed = false;
  const exists = (path) => {
    if (path.endsWith("package-lock.json")) return true;
    if (path.endsWith("@modelcontextprotocol/sdk/package.json")) return installed;
    if (path.endsWith("zod/package.json")) return installed;
    return false;
  };
  const calls = [];
  const run = (command, args, options) => {
    calls.push({ command, args, options });
    installed = true;
    return { status: 0 };
  };

  ensureSidecarDependencies({ serviceDir, exists, run });

  assert.deepEqual(calls, [
    {
      command: "npm",
      args: [ "ci", "--omit=dev", "--no-audit", "--no-fund" ],
      options: {
        cwd: serviceDir,
        stdio: [ "ignore", "ignore", "inherit" ]
      }
    }
  ]);
});

test("ensureSidecarDependencies raises when installation does not materialize packages", () => {
  const serviceDir = "/tmp/notae-mcp";
  const exists = (path) => path.endsWith("package-lock.json");
  const run = () => ({ status: 0 });

  assert.throws(
    () => ensureSidecarDependencies({ serviceDir, exists, run }),
    /still missing after installation/
  );
});
