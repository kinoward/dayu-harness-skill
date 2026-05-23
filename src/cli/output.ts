import { isCliError } from "./errors.js";
import type {
  ApplyReport,
  DiagnoseReport,
  GenerateReport,
  InitReport,
  MergeReport,
  ValidationReport
} from "./types.js";

export type CliReport = ApplyReport | InitReport | DiagnoseReport | MergeReport | ValidationReport | GenerateReport;

export function writeReport(report: CliReport, json: boolean): void {
  if (json) {
    process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    return;
  }

  process.stdout.write(`${humanizeReport(report)}\n`);
}

export function writeError(error: unknown, json: boolean): void {
  if (json) {
    const body = isCliError(error)
      ? { status: "error", code: error.code, message: error.message, issues: error.issues }
      : { status: "error", code: "error", message: error instanceof Error ? error.message : String(error) };
    process.stderr.write(`${JSON.stringify(body, null, 2)}\n`);
    return;
  }

  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
}

function humanizeReport(report: CliReport): string {
  switch (report.command) {
    case "apply":
      return [
        `apply: ${report.status}`,
        `target: ${report.targetRoot}`,
        `order: ${report.deploymentOrder.join(" -> ")}`,
        `create=${report.summary.create} chmod=${report.summary.chmod} merge=${report.summary.merge} skip=${report.summary.skip} conflict=${report.summary.conflict} missing=${report.summary.missingSource}`
      ].join("\n");
    case "init":
      return [
        `init: ${report.status}`,
        `config: ${report.configOperation} ${report.configPath}`,
        humanizeReport(report.apply)
      ].join("\n");
    case "diagnose":
      return [
        `diagnose: ${report.status}`,
        `target: ${report.targetRoot}`,
        `present=${report.summary.present} missing=${report.summary.missing} wrong-mode=${report.summary.wrongMode} drift=${report.summary.drift} needs-merge=${report.summary.needsMerge}`
      ].join("\n");
    case "merge":
      return [
        `merge: ${report.status}`,
        `target: ${report.targetRoot}`,
        ...report.capabilities.map(
          (capability) => `${capability.capabilityId}: ${capability.status} (${capability.recommendation})`
        )
      ].join("\n");
    case "validate":
      return [
        `validate: ${report.status}`,
        `registry=${report.registry.status} config=${report.config.status} deployment=${report.deployment.status}`,
        ...report.issues.map((issue) => `- ${issue}`)
      ].join("\n");
    case "generate":
      return [
        `generate: ${report.status}`,
        `order: ${report.deploymentOrder.join(" -> ")}`,
        ...report.files.map((file) => `${file.capabilityId}: ${file.dst}`)
      ].join("\n");
  }
}
