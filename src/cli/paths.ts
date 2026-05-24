import { accessSync, constants } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { CliError } from "./errors.js";

export const SKILL_ROOT = fileURLToPath(new URL("../..", import.meta.url));
export const DEFAULT_CONFIG_FILE = "dayu.config.yaml";

export function resolveSkillRoot(): string {
  return process.env.NODE_ENV === "test" && process.env.DAYU_HARNESS_SKILL_ROOT
    ? resolve(process.env.DAYU_HARNESS_SKILL_ROOT)
    : SKILL_ROOT;
}

export function resolveTargetRoot(input?: string): string {
  return resolve(input ?? process.cwd());
}

export function resolveConfigPath(targetRoot: string, input?: string): string {
  return resolve(input ?? join(targetRoot, DEFAULT_CONFIG_FILE));
}

export function resolveProjectRootFromConfig(configPath: string, projectRoot?: string): string | undefined {
  if (!projectRoot) {
    return undefined;
  }

  return isAbsolute(projectRoot) ? resolve(projectRoot) : resolve(dirname(configPath), projectRoot);
}

export function resolveInsideRoot(root: string, relativePath: string): string {
  const absolute = resolve(root, relativePath);
  const rel = relative(root, absolute);

  if (rel === "" || (!rel.startsWith("..") && !isAbsolute(rel))) {
    return absolute;
  }

  throw new CliError("unsafe-path", `path '${relativePath}' escapes root '${root}'`, [
    { code: "unsafe-path", message: `path '${relativePath}' escapes root '${root}'`, path: relativePath }
  ]);
}

export function toRelativePath(root: string, absolutePath: string): string {
  const rel = relative(root, absolutePath);
  return rel === "" ? "." : rel.split("\\").join("/");
}

export function fileExists(path: string): boolean {
  try {
    accessSync(path, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}
