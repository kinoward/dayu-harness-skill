import { buildApplyPlan } from "./apply.js";
import type { ApplyOptions, MergeCapabilityPlan, MergeReport } from "./types.js";

export function planDayuMerge(options: ApplyOptions = {}): MergeReport {
  const plan = buildApplyPlan({ ...options, dryRun: true });
  const capabilities = plan.deploymentOrder.map((capabilityId): MergeCapabilityPlan => {
    const fileOperations = plan.fileOperations.filter((operation) => operation.capabilityId === capabilityId);
    const installerOperations = plan.installerOperations.filter((operation) => operation.capabilityId === capabilityId);
    const paths = [...fileOperations.map((operation) => operation.dst), ...installerOperations.map((operation) => operation.dst)];
    const hasError =
      fileOperations.some((operation) => operation.status === "missing-source") ||
      installerOperations.some((operation) => operation.status === "missing-source" || operation.status === "unsupported");
    const hasConflict = fileOperations.some((operation) => operation.status === "conflict");
    const hasWork =
      fileOperations.some((operation) => operation.status === "create" || operation.status === "chmod") ||
      installerOperations.some((operation) => operation.status === "create" || operation.status === "merge");

    if (hasError) {
      return {
        capabilityId,
        status: "error",
        recommendation: "review",
        paths
      };
    }

    if (hasConflict) {
      return {
        capabilityId,
        status: "conflict",
        recommendation: "review",
        paths
      };
    }

    if (!hasWork) {
      return {
        capabilityId,
        status: "no-op",
        recommendation: "skip",
        paths
      };
    }

    return {
      capabilityId,
      status: "clean",
      recommendation: "apply",
      paths
    };
  });

  const hasErrors = capabilities.some((capability) => capability.status === "error");
  const hasConflicts = capabilities.some((capability) => capability.status === "conflict");

  return {
    command: "merge",
    status: hasErrors ? "error" : hasConflicts ? "conflict" : "planned",
    dryRun: true,
    targetRoot: plan.targetRoot,
    configPath: plan.configPath,
    capabilities
  };
}
