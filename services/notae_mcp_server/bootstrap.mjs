import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve } from "node:path";

const REQUIRED_PACKAGES = [
  "@modelcontextprotocol/sdk/package.json",
  "zod/package.json"
];

export function hasInstalledDependencies({ serviceDir, exists = existsSync }) {
  return REQUIRED_PACKAGES.every((packagePath) => exists(resolve(serviceDir, "node_modules", packagePath)));
}

export function installDependencies({ serviceDir, run = spawnSync, exists = existsSync }) {
  const packageManagerArgs = exists(resolve(serviceDir, "package-lock.json"))
    ? [ "ci", "--omit=dev", "--no-audit", "--no-fund" ]
    : [ "install", "--omit=dev", "--no-audit", "--no-fund" ];

  const result = run("npm", packageManagerArgs, {
    cwd: serviceDir,
    stdio: [ "ignore", "ignore", "inherit" ]
  });

  if (result.status !== 0) {
    throw new Error(`Failed to install Notae MCP server dependencies (exit ${result.status ?? "unknown"}).`);
  }
}

export function ensureSidecarDependencies({ serviceDir, exists = existsSync, run = spawnSync }) {
  if (hasInstalledDependencies({ serviceDir, exists })) return;

  installDependencies({ serviceDir, run, exists });

  if (!hasInstalledDependencies({ serviceDir, exists })) {
    throw new Error("Notae MCP server dependencies are still missing after installation.");
  }
}
