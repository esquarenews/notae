import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { ensureSidecarDependencies } from "./bootstrap.mjs";

const serviceDir = dirname(fileURLToPath(import.meta.url));

ensureSidecarDependencies({ serviceDir });
await import(pathToFileURL(resolve(serviceDir, "server.mjs")).href);
