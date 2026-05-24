import { dirname, join, resolve } from "node:path";

import { buildApplyPlan } from "./apply.js";
import { isCliError } from "./errors.js";
import { loadManifestRegistry } from "./manifest-registry.js";
import { DEFAULT_CONFIG_FILE, resolveTargetRoot } from "./paths.js";
import type { ApplyOptions, ValidationReport } from "./types.js";

export function validateDayuProject(options: ApplyOptions = {}): ValidationReport {
  const explicitConfigPath = options.configPath ? resolve(options.configPath) : undefined;
  const targetRoot = options.targetRoot
    ? resolveTargetRoot(options.targetRoot)
    : explicitConfigPath
      ? dirname(explicitConfigPath)
      : resolveTargetRoot();
  const configPath = explicitConfigPath ?? join(targetRoot, DEFAULT_CONFIG_FILE);
  const issues: string[] = [];
  let registryCapabilityCount = 0;

  try {
    registryCapabilityCount = loadManifestRegistry().manifests.length;
  } catch (error) {
    issues.push(...messagesFromError(error));
  }

  try {
    const plan = buildApplyPlan({ ...options, dryRun: true });
    for (const operation of plan.fileOperations) {
      if (operation.status !== "skip") {
        issues.push(`${operation.dst}: ${operation.status}${operation.reason ? ` (${operation.reason})` : ""}`);
      }
    }
    for (const operation of plan.installerOperations) {
      if (operation.status !== "skip") {
        issues.push(`${operation.dst}: ${operation.status}${operation.reason ? ` (${operation.reason})` : ""}`);
      }
    }

    return {
      command: "validate",
      status: issues.length === 0 ? "valid" : "invalid",
      targetRoot: plan.targetRoot,
      configPath: plan.configPath,
      registry: {
        status: registryCapabilityCount > 0 ? "valid" : "invalid",
        capabilityCount: registryCapabilityCount
      },
      config: {
        status: "valid",
        capabilityCount: plan.requestedCapabilities.length
      },
      deployment: {
        status: issues.length === 0 ? "valid" : "invalid",
        order: plan.deploymentOrder
      },
      issues
    };
  } catch (error) {
    issues.push(...messagesFromError(error));

    return {
      command: "validate",
      status: "invalid",
      targetRoot,
      configPath,
      registry: {
        status: registryCapabilityCount > 0 ? "valid" : "invalid",
        capabilityCount: registryCapabilityCount
      },
      config: {
        status: "invalid"
      },
      deployment: {
        status: "invalid"
      },
      issues
    };
  }
}

function messagesFromError(error: unknown): string[] {
  if (isCliError(error)) {
    return error.issues.map((issue) => issue.message);
  }

  return [error instanceof Error ? error.message : String(error)];
}
