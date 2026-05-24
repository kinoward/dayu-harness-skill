import { applyDayuConfig, buildApplyPlan } from "./apply.js";
import { loadManifestRegistry } from "./manifest-registry.js";
import { summarizeRse } from "./rse.js";
import type {
  FileOperation,
  InstallerOperation,
  MergeCapabilityPlan,
  MergeOptions,
  MergeReport,
  MergeStrategy,
  ManifestRegistry
} from "./types.js";

export function planDayuMerge(options: MergeOptions = {}): MergeReport {
  const plan = buildApplyPlan({ ...options, dryRun: true });
  const registry = loadRegistryFromPlan();
  const displayByCapability = new Map(plan.capabilitySummaries.map((capability) => [capability.capabilityId, capability]));
  const capabilities = plan.deploymentOrder.map((capabilityId): MergeCapabilityPlan => {
    const manifest = registry.manifestById.get(capabilityId);
    if (!manifest) {
      throw new Error(`capability '${capabilityId}' is not loaded`);
    }
    const fileOperations = plan.fileOperations.filter((operation) => operation.capabilityId === capabilityId);
    const installerOperations = plan.installerOperations.filter((operation) => operation.capabilityId === capabilityId);
    const paths = [...fileOperations.map((operation) => operation.dst), ...installerOperations.map((operation) => operation.dst)];
    const hasError =
      fileOperations.some((operation) => operation.status === "missing-source") ||
      installerOperations.some((operation) => operation.status === "missing-source" || operation.status === "unsupported");
    const hasConflict = fileOperations.some((operation) => operation.status === "conflict");
    const hasWork =
      fileOperations.some((operation) => ["create", "overwrite", "delete", "chmod"].includes(operation.status)) ||
      installerOperations.some((operation) => operation.status === "create" || operation.status === "merge");

    if (hasError) {
      return {
        capabilityId,
        displayName: displayByCapability.get(capabilityId)?.displayName ?? capabilityId,
        displaySummary: displayByCapability.get(capabilityId)?.summary ?? capabilityId,
        kind: manifest.kind,
        status: "error",
        decisionGranularity: "capability",
        availableStrategies: STRATEGY_OPTIONS,
        defaultStrategy: "skip",
        recommendation: "review",
        rse: summarizeRse(manifest),
        summary: summarizeCapabilityOperations(fileOperations, installerOperations),
        paths
      };
    }

    if (hasConflict) {
      return {
        capabilityId,
        displayName: displayByCapability.get(capabilityId)?.displayName ?? capabilityId,
        displaySummary: displayByCapability.get(capabilityId)?.summary ?? capabilityId,
        kind: manifest.kind,
        status: "conflict",
        decisionGranularity: "capability",
        availableStrategies: STRATEGY_OPTIONS,
        defaultStrategy: "keep",
        recommendation: "review",
        rse: summarizeRse(manifest),
        summary: summarizeCapabilityOperations(fileOperations, installerOperations),
        paths
      };
    }

    if (!hasWork) {
      return {
        capabilityId,
        displayName: displayByCapability.get(capabilityId)?.displayName ?? capabilityId,
        displaySummary: displayByCapability.get(capabilityId)?.summary ?? capabilityId,
        kind: manifest.kind,
        status: "no-op",
        decisionGranularity: "capability",
        availableStrategies: STRATEGY_OPTIONS,
        defaultStrategy: "skip",
        recommendation: "skip",
        rse: summarizeRse(manifest),
        summary: summarizeCapabilityOperations(fileOperations, installerOperations),
        paths
      };
    }

    return {
      capabilityId,
      displayName: displayByCapability.get(capabilityId)?.displayName ?? capabilityId,
      displaySummary: displayByCapability.get(capabilityId)?.summary ?? capabilityId,
      kind: manifest.kind,
      status: "clean",
      decisionGranularity: "capability",
      availableStrategies: STRATEGY_OPTIONS,
      defaultStrategy: "replace",
      recommendation: "apply",
      rse: summarizeRse(manifest),
      summary: summarizeCapabilityOperations(fileOperations, installerOperations),
      paths
    };
  });

  const hasErrors = capabilities.some((capability) => capability.status === "error");
  const hasConflicts = capabilities.some((capability) => capability.status === "conflict");

  return {
    command: "merge",
    status: hasErrors ? "error" : hasConflicts ? "conflict" : "planned",
    dryRun: true,
    decisionGranularity: "capability",
    strategyOptions: STRATEGY_OPTIONS,
    targetRoot: plan.targetRoot,
    configPath: plan.configPath,
    capabilities
  };
}

const STRATEGY_OPTIONS: readonly MergeStrategy[] = ["keep", "replace", "skip"];

export function applyDayuMerge(options: MergeOptions = {}): MergeReport {
  const dryRun = options.dryRun ?? true;
  const plan = planDayuMerge({ ...options, dryRun: true });
  if (dryRun || options.strategy === "keep" || options.strategy === "skip") {
    return plan;
  }

  const applied = applyDayuConfig({
    ...options,
    dryRun: false,
    force: options.strategy === "replace" || options.force
  });

  return {
    ...plan,
    status: applied.status === "conflict" || applied.status === "error" ? applied.status : "merged"
  };
}

function summarizeCapabilityOperations(
  fileOperations: readonly FileOperation[],
  installerOperations: readonly InstallerOperation[]
) {
  return {
    create:
      fileOperations.filter((operation) => operation.status === "create").length +
      installerOperations.filter((operation) => operation.status === "create").length,
    overwrite: fileOperations.filter((operation) => operation.status === "overwrite").length,
    delete: fileOperations.filter((operation) => operation.status === "delete").length,
    chmod: fileOperations.filter((operation) => operation.status === "chmod").length,
    merge: installerOperations.filter((operation) => operation.status === "merge").length,
    skip:
      fileOperations.filter((operation) => operation.status === "skip").length +
      installerOperations.filter((operation) => operation.status === "skip").length,
    conflict: fileOperations.filter((operation) => operation.status === "conflict").length,
    missingSource:
      fileOperations.filter((operation) => operation.status === "missing-source").length +
      installerOperations.filter((operation) => operation.status === "missing-source").length,
    unsupported: installerOperations.filter((operation) => operation.status === "unsupported").length
  };
}

function loadRegistryFromPlan(): ManifestRegistry {
  return loadManifestRegistry();
}
