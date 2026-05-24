import { diagnoseDayuProject } from "./diagnose.js";
import type { ApplyOptions, StatusCapabilityGroup, StatusReport } from "./types.js";

const KIND_ORDER = ["hard", "soft", "infra"] as const;

export function statusDayuProject(options: ApplyOptions = {}): StatusReport {
  const diagnose = diagnoseDayuProject(options);
  const groups: StatusCapabilityGroup[] = KIND_ORDER.map((kind) => ({
    kind,
    capabilities: diagnose.capabilities.filter((capability) => capability.kind === kind)
  })).filter((group) => group.capabilities.length > 0);

  return {
    command: "status",
    status: diagnose.healthy ? "healthy" : "unhealthy",
    targetRoot: diagnose.targetRoot,
    configPath: diagnose.configPath,
    groups,
    summary: {
      healthy: diagnose.capabilities.filter((capability) => capability.status === "healthy").length,
      unhealthy: diagnose.capabilities.filter((capability) => capability.status === "unhealthy").length,
      hard: diagnose.capabilities.filter((capability) => capability.kind === "hard").length,
      soft: diagnose.capabilities.filter((capability) => capability.kind === "soft").length,
      infra: diagnose.capabilities.filter((capability) => capability.kind === "infra").length
    }
  };
}
