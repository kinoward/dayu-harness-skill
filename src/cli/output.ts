import chalk from "chalk";

import { isCliError } from "./errors.js";
import type {
  ApplyReport,
  DiagnoseReport,
  GenerateReport,
  InitReport,
  MergeReport,
  StatusReport,
  ValidationReport
} from "./types.js";

export type CliReport = ApplyReport | InitReport | DiagnoseReport | MergeReport | ValidationReport | GenerateReport | StatusReport;

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
        `${colorStatus("apply", report.status)}`,
        `target: ${report.targetRoot}`,
        `order: ${report.deploymentOrder.join(" -> ")}`,
        `create=${report.summary.create} overwrite=${report.summary.overwrite} delete=${report.summary.delete} chmod=${report.summary.chmod} merge=${report.summary.merge} skip=${report.summary.skip} conflict=${report.summary.conflict} missing=${report.summary.missingSource}`,
        report.orphanPaths.length > 0 ? `orphans=${report.orphanPaths.join(", ")}` : "orphans=0"
      ].join("\n");
    case "init":
      return [
        `${colorStatus("init", report.status)}`,
        `config: ${report.configOperation} ${report.configPath}`,
        humanizeReport(report.apply)
      ].join("\n");
    case "diagnose":
      return [
        `${colorStatus("diagnose", report.status)}`,
        `target: ${report.targetRoot}`,
        `present=${report.summary.present} missing=${report.summary.missing} wrong-mode=${report.summary.wrongMode} drift=${report.summary.drift} needs-merge=${report.summary.needsMerge}`,
        ...report.capabilities.map(
          (capability) =>
            `${capability.capabilityId}: ${capability.status} rule=${capability.rse.rule.present ? "yes" : "no"} sensor=${capability.rse.sensor.present ? "yes" : "no"} enforcer=${capability.rse.enforcer.present ? "yes" : "no"}`
        )
      ].join("\n");
    case "merge":
      return [
        `${colorStatus("merge", report.status)}`,
        `granularity: ${report.decisionGranularity}`,
        `target: ${report.targetRoot}`,
        ...report.capabilities.map(
          (capability) =>
            `${capability.capabilityId}: ${capability.status} default=${capability.defaultStrategy} choices=${capability.availableStrategies.join("/")}`
        )
      ].join("\n");
    case "validate":
      return [
        `${colorStatus("validate", report.status)}`,
        `registry=${report.registry.status} config=${report.config.status} deployment=${report.deployment.status}`,
        ...report.issues.map((issue) => `- ${issue}`)
      ].join("\n");
    case "generate":
      return [
        `${colorStatus("generate", report.status)}`,
        `order: ${report.deploymentOrder.join(" -> ")}`,
        ...report.files.map((file) => `${file.capabilityId}: ${file.dst}`)
      ].join("\n");
    case "status":
      return [
        `${colorStatus("status", report.status)}`,
        `target: ${report.targetRoot}`,
        `healthy=${report.summary.healthy} unhealthy=${report.summary.unhealthy} hard=${report.summary.hard} soft=${report.summary.soft} infra=${report.summary.infra}`,
        ...report.groups.flatMap((group) => [
          `${group.kind}:`,
          ...group.capabilities.map((capability) => `  ${capability.capabilityId}: ${capability.status}`)
        ])
      ].join("\n");
  }
}

function colorStatus(command: string, status: string): string {
  const label = `${command}: ${status}`;
  if (["healthy", "valid", "applied", "merged", "generated", "no-op", "repaired"].includes(status)) {
    return chalk.green(label);
  }
  if (["planned"].includes(status)) {
    return chalk.cyan(label);
  }
  if (["conflict", "unhealthy", "invalid", "error"].includes(status)) {
    return chalk.red(label);
  }
  return label;
}
