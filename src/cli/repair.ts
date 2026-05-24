import { applyDayuConfig } from "./apply.js";
import type { ApplyReport, RepairOptions } from "./types.js";

export function repairDayuCapability(options: RepairOptions = {}): ApplyReport {
  const report = applyDayuConfig({
    ...options,
    onlyCapabilityId: options.capabilityId ?? options.onlyCapabilityId,
    dryRun: false,
    force: true
  });

  return {
    ...report,
    status: report.status === "no-op" ? "no-op" : "repaired"
  };
}
