import { readFileSync, writeFileSync } from "node:fs";
import { basename } from "node:path";
import { stringify as stringifyYaml } from "yaml";

import {
  DAYU_CONFIG_SCHEMA_VERSION,
  DayuConfigSchema,
  formatZodError,
  parseDayuConfigYaml,
  type CapabilityId,
  type DayuConfig,
  type LocaleCode
} from "../schemas/index.js";
import { CliError } from "./errors.js";

export const DEFAULT_PHASE1D_CAPABILITIES: readonly CapabilityId[] = [
  "core",
  "git.commit-format",
  "ai.execution"
] as const;

export function readDayuConfig(configPath: string): DayuConfig {
  try {
    return parseDayuConfigYaml(readFileSync(configPath, "utf8"));
  } catch (error) {
    if (error instanceof Error) {
      throw new CliError("config-invalid", `failed to parse ${configPath}: ${error.message}`, [
        { code: "config-invalid", message: error.message, path: configPath }
      ]);
    }
    throw error;
  }
}

export function createDefaultDayuConfig(targetRoot: string, locale: LocaleCode = "zh"): DayuConfig {
  return DayuConfigSchema.parse({
    schemaVersion: DAYU_CONFIG_SCHEMA_VERSION,
    locale,
    project: {
      name: basename(targetRoot)
    },
    capabilities: DEFAULT_PHASE1D_CAPABILITIES.map((id) => ({ id }))
  });
}

export function writeDayuConfig(configPath: string, config: DayuConfig): void {
  writeFileSync(configPath, stringifyDayuConfig(config), "utf8");
}

export function stringifyDayuConfig(config: DayuConfig): string {
  return stringifyYaml(
    {
      schemaVersion: config.schemaVersion,
      locale: config.locale,
      project: config.project,
      capabilities: config.capabilities.map((capability) => ({
        id: capability.id,
        ...(capability.enabled === false ? { enabled: false } : {}),
        ...(capability.options ? { options: capability.options } : {})
      }))
    },
    { lineWidth: 0 }
  );
}

export function enabledCapabilityIds(config: DayuConfig): CapabilityId[] {
  const ids = config.capabilities.filter((capability) => capability.enabled).map((capability) => capability.id);
  if (ids.length === 0) {
    throw new CliError("config-empty", "dayu.config.yaml must enable at least one capability");
  }
  return ids;
}

export function formatConfigSchemaError(error: unknown): string {
  if (error && typeof error === "object" && "issues" in error) {
    return formatZodError(error as Parameters<typeof formatZodError>[0]);
  }

  return error instanceof Error ? error.message : String(error);
}
