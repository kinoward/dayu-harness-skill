import { readFileSync } from "node:fs";
import { join } from "node:path";

import {
  ManifestV2Schema,
  formatZodError,
  validateDayuConfigCapabilities,
  type DayuConfig,
  type ManifestV2
} from "../schemas/index.js";
import { CliError } from "./errors.js";
import { resolveSkillRoot } from "./paths.js";
import type { ManifestRegistry } from "./types.js";

export const PHASE1D_CAPABILITY_IDS = ["core", "git.hooks", "git.commit-format", "ai.execution"] as const;

export function loadPhase1dManifestRegistry(skillRoot: string = resolveSkillRoot()): ManifestRegistry {
  const manifests = PHASE1D_CAPABILITY_IDS.map((id) => readManifest(skillRoot, id));
  const manifestById = new Map<string, ManifestV2>();

  for (const manifest of manifests) {
    manifestById.set(manifest.id, manifest);
  }

  return { skillRoot, manifests, manifestById };
}

export function assertConfigCapabilitiesKnown(config: DayuConfig, registry: ManifestRegistry): void {
  const unknown = validateDayuConfigCapabilities(config, registry.manifestById.keys());
  if (unknown.length > 0) {
    throw new CliError(
      "unknown-capability",
      `unknown capability id(s): ${unknown.join(", ")}`,
      unknown.map((id) => ({ code: "unknown-capability", message: `unknown capability '${id}'`, path: id }))
    );
  }
}

function readManifest(skillRoot: string, id: string): ManifestV2 {
  const manifestPath = join(skillRoot, "capabilities", `${id}.json`);
  let raw: unknown;

  try {
    raw = JSON.parse(readFileSync(manifestPath, "utf8"));
  } catch (error) {
    throw new CliError("manifest-read-failed", `failed to read manifest ${manifestPath}`, [
      {
        code: "manifest-read-failed",
        message: error instanceof Error ? error.message : String(error),
        path: manifestPath
      }
    ]);
  }

  const parsed = ManifestV2Schema.safeParse(raw);
  if (!parsed.success) {
    throw new CliError("manifest-invalid", `manifest ${id} is invalid:\n${formatZodError(parsed.error)}`, [
      {
        code: "manifest-invalid",
        message: formatZodError(parsed.error),
        path: manifestPath
      }
    ]);
  }

  return parsed.data;
}
