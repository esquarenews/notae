import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";

const REQUIRED_PACKAGES = [
  "@modelcontextprotocol/sdk/package.json",
  "zod/package.json"
];

const DEPENDENCY_PROBE = [
  "await import('@modelcontextprotocol/sdk/server/mcp.js');",
  "await import('zod');"
].join("\n");

export function hasInstalledDependencies({ serviceDir, exists = existsSync, probe = spawnSync }) {
  const packagesExist = REQUIRED_PACKAGES.every((packagePath) => exists(resolve(serviceDir, "node_modules", packagePath)));
  if (!packagesExist) return false;

  const result = probe(process.execPath, [ "--input-type=module", "--eval", DEPENDENCY_PROBE ], {
    cwd: serviceDir,
    stdio: [ "ignore", "ignore", "ignore" ],
    timeout: 5_000
  });

  return result.status === 0;
}

export function installDependencies({ serviceDir, run = spawnSync, exists = existsSync }) {
  const packageManagerArgs = exists(resolve(serviceDir, "package-lock.json"))
    ? [ "ci", "--omit=dev", "--no-audit", "--no-fund" ]
    : [ "install", "--omit=dev", "--no-audit", "--no-fund" ];

  const siblingNpm = resolve(dirname(process.execPath), "npm");
  const packageManager = exists(siblingNpm) ? siblingNpm : "npm";
  const result = run(packageManager, packageManagerArgs, {
    cwd: serviceDir,
    stdio: [ "ignore", "ignore", "inherit" ]
  });

  if (result.status !== 0) {
    throw new Error(`Failed to install Notae MCP server dependencies (exit ${result.status ?? "unknown"}).`);
  }
}

export function ensureSidecarDependencies({ serviceDir, exists = existsSync, run = spawnSync, probe = spawnSync }) {
  if (hasInstalledDependencies({ serviceDir, exists, probe })) return;

  installDependencies({ serviceDir, run, exists });

  if (!hasInstalledDependencies({ serviceDir, exists, probe })) {
    throw new Error("Notae MCP server dependencies are still missing or invalid after installation.");
  }
}
