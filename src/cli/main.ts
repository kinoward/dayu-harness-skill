#!/usr/bin/env node
import { Command } from "commander";
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { applyDayuConfig, initDayuConfig } from "./apply.js";
import { diagnoseDayuProject } from "./diagnose.js";
import { checkEnvironment } from "./environment.js";
import { CliError } from "./errors.js";
import { finalizeDayuProject } from "./finalize.js";
import { generateDayuContent } from "./generate.js";
import { checkI18nDrift } from "./i18n-drift.js";
import { applyDayuMerge, planDayuMerge } from "./merge.js";
import { writeError, writeReport, type CliReport } from "./output.js";
import { repairDayuCapability } from "./repair.js";
import { runAuditSensor, runConsistencySensor, runDiffHelper, runValidateSensor } from "./sensors.js";
import { statusDayuProject } from "./status.js";
import { validateDayuProject } from "./validate.js";

interface CommonOptions {
  config?: string;
  target?: string;
  dryRun?: boolean;
  json?: boolean;
  locale?: "zh" | "en";
  apply?: boolean;
  only?: string;
  force?: boolean;
  pruneOrphans?: boolean;
  capability?: string;
  strategy?: "keep" | "replace" | "skip";
  skillRoot?: string;
  githubRemote?: "apply" | "skip";
  releaseValidation?: "real" | "readiness";
  capabilities?: string;
  check?: boolean;
}

export function buildProgram(): Command {
  const program = new Command();

  program.name("dayu-harness").description("Dayu Harness TypeScript CLI").option("--json", "emit JSON");

  program
    .command("init")
    .description("create dayu.config.yaml when missing, then apply it")
    .option("--config <path>", "config path")
    .option("--target <path>", "target project root")
    .option("--locale <locale>", "default config locale: zh or en", "zh")
    .option("--dry-run", "preview without writing")
    .option("--apply", "write dayu.config.yaml and deploy the default plan")
    .option("--force", "overwrite drifted managed files while applying")
    .option("--prune-orphans", "delete previously managed files that are no longer selected")
    .option("--json", "emit JSON")
    .action((options: CommonOptions, command: Command) =>
      execute(command, () =>
        initDayuConfig({
          configPath: options.config,
          targetRoot: options.target,
          dryRun: resolveInitDryRun(options),
          locale: options.locale,
          force: options.force,
          pruneOrphans: options.pruneOrphans
        })
      )
    );

  program
    .command("apply")
    .description("read config, resolve the deployment DAG, and deploy files")
    .option("--config <path>", "config path")
    .option("--target <path>", "target project root")
    .option("--dry-run", "preview without writing")
    .option("--only <capability>", "deploy one enabled capability and its deployment dependencies")
    .option("--force", "overwrite drifted managed files")
    .option("--prune-orphans", "delete previously managed files that are no longer selected")
    .option("--json", "emit JSON")
    .action((options: CommonOptions, command: Command) =>
      execute(command, () =>
        applyDayuConfig({
          configPath: options.config,
          targetRoot: options.target,
          dryRun: options.dryRun,
          onlyCapabilityId: options.only,
          force: options.force,
          pruneOrphans: options.pruneOrphans
        })
      )
    );

  program
    .command("merge")
    .description("plan or apply capability-level keep/replace/skip merging for existing projects")
    .option("--config <path>", "config path")
    .option("--target <path>", "target project root")
    .option("--dry-run", "preview without writing")
    .option("--apply", "apply the selected strategy")
    .option("--strategy <strategy>", "merge strategy: keep, replace, or skip", "keep")
    .option("--only <capability>", "plan or apply one enabled capability and its deployment dependencies")
    .option("--json", "emit JSON")
    .action((options: CommonOptions, command: Command) =>
      execute(command, () => {
        const strategy = parseMergeStrategy(options.strategy);
        const mergeOptions = {
          configPath: options.config,
          targetRoot: options.target,
          dryRun: options.apply ? false : true,
          strategy,
          onlyCapabilityId: options.only
        };
        return mergeOptions.dryRun ? planDayuMerge(mergeOptions) : applyDayuMerge(mergeOptions);
      })
    );

  program
    .command("generate")
    .description("render managed content previews without writing")
    .option("--config <path>", "config path")
    .option("--target <path>", "target project root")
    .option("--capability <capability>", "preview one enabled capability")
    .option("--json", "emit JSON")
    .action((options: CommonOptions, command: Command) =>
      execute(command, () =>
        generateDayuContent({
          configPath: options.config,
          targetRoot: options.target,
          capabilityId: options.capability
        })
      )
    );

  program
    .command("repair [capability]")
    .description("repair drift for one capability or the active deployment plan")
    .option("--config <path>", "config path")
    .option("--target <path>", "target project root")
    .option("--json", "emit JSON")
    .action((capability: string | undefined, options: CommonOptions, command: Command) =>
      execute(command, () =>
        repairDayuCapability({
          configPath: options.config,
          targetRoot: options.target,
          capabilityId: capability
        })
      )
    );

  program
    .command("status")
    .description("show grouped governance capability status")
    .option("--config <path>", "config path")
    .option("--target <path>", "target project root")
    .option("--json", "emit JSON")
    .action((options: CommonOptions, command: Command) =>
      execute(command, () =>
        statusDayuProject({
          configPath: options.config,
          targetRoot: options.target
        })
      )
    );

  program
    .command("diagnose")
    .description("check deployed governance health")
    .option("--config <path>", "config path")
    .option("--target <path>", "target project root")
    .option("--json", "emit JSON")
    .action((options: CommonOptions, command: Command) =>
      execute(command, () =>
        diagnoseDayuProject({
          configPath: options.config,
          targetRoot: options.target
        })
      )
    );

  program
    .command("validate")
    .description("validate manifest, config, dependency, and product consistency")
    .option("--config <path>", "config path")
    .option("--target <path>", "target project root")
    .option("--json", "emit JSON")
    .action((options: CommonOptions, command: Command) =>
      execute(command, () =>
        validateDayuProject({
          configPath: options.config,
          targetRoot: options.target
        })
      )
    );

  program
    .command("finalize")
    .description("verify, commit, sync remote governance, and run end-to-end checks")
    .option("--config <path>", "config path")
    .option("--target <path>", "target project root")
    .option("--skill-root <path>", "Dayu Harness skill root")
    .option("--github-remote <mode>", "remote synchronization mode: apply or skip", "skip")
    .option("--release-validation <mode>", "release validation depth: real or readiness", "readiness")
    .option("--json", "emit JSON")
    .action((options: CommonOptions, command: Command) =>
      execute(command, () =>
        finalizeDayuProject({
          configPath: options.config,
          targetRoot: options.target,
          skillRoot: options.skillRoot,
          githubRemote: parseGithubRemote(options.githubRemote),
          releaseValidation: parseReleaseValidation(options.releaseValidation)
        })
      )
    );

  program
    .command("sensor <name> [args...]")
    .description("run deployed governance sensor logic from the TypeScript CLI")
    .option("--target <path>", "target project root")
    .option("--json", "emit JSON")
    .action((name: string, args: string[] | undefined, options: CommonOptions, command: Command) =>
      executeSensor(command, name, args ?? [], options)
    );

  program
    .command("environment [target]")
    .description("check or prepare the target project environment using the TypeScript CLI")
    .option("--check", "check only")
    .option("--apply", "apply safe initialization")
    .option("--capabilities <ids>", "comma-separated capability ids")
    .option("--json", "emit JSON")
    .action((target: string | undefined, options: CommonOptions, command: Command) => {
      const json = Boolean(command.optsWithGlobals().json);
      const mode = options.apply ? "apply" : "check";
      const report = checkEnvironment({ targetRoot: target, mode, capabilities: options.capabilities });
      if (json) {
        process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
      } else {
        process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
      }
      process.exitCode = report.status === "error" || report.status === "needs_install" ? 1 : 0;
    });

  program
    .command("i18n-drift [target]")
    .description("check README and template i18n drift")
    .option("--json", "emit JSON")
    .action((target: string | undefined, options: CommonOptions, command: Command) => {
      const json = Boolean(command.optsWithGlobals().json);
      const report = checkI18nDrift(target);
      if (json) {
        process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
      } else {
        process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
      }
      process.exitCode = report.status === "pass" ? 0 : 1;
    });

  return program;
}

export async function runCli(argv: readonly string[] = process.argv): Promise<void> {
  const program = buildProgram();
  await program.parseAsync(argv);
}

function resolveInitDryRun(options: CommonOptions): boolean {
  if (options.apply && options.dryRun) {
    throw new CliError("conflicting-options", "init accepts either --dry-run or --apply, not both", [
      {
        code: "conflicting-options",
        message: "remove --dry-run to apply changes, or remove --apply to preview only"
      }
    ]);
  }

  return options.apply ? false : true;
}

async function execute(command: Command, action: () => CliReport): Promise<void> {
  const json = Boolean(command.optsWithGlobals().json);

  try {
    const report = action();
    writeReport(report, json);
    process.exitCode = exitCodeForReport(report);
  } catch (error) {
    writeError(error, json);
    process.exitCode = 1;
  }
}

function executeSensor(command: Command, name: string, args: readonly string[], options: CommonOptions): void {
  const json = Boolean(command.optsWithGlobals().json);
  try {
    if (name === "diff-helper" || name === "diff") {
      process.stdout.write(runDiffHelper(args));
      return;
    }

    const report =
      name === "audit"
        ? runAuditSensor({ targetRoot: options.target ?? inferSensorTarget(args), json })
        : name === "validate"
          ? runValidateSensor({ targetRoot: options.target ?? inferSensorTarget(args), json })
          : name === "check-consistency" || name === "consistency"
            ? runConsistencySensor({ targetRoot: options.target ?? inferSensorTarget(args), json })
            : undefined;

    if (!report) {
      throw new CliError("unknown-sensor", `unknown sensor '${name}'`, [
        { code: "unknown-sensor", message: "supported sensors: audit, validate, check-consistency, diff-helper" }
      ]);
    }

    if (json) {
      process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    } else {
      process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
    }
    const summary = "summary" in report ? report.summary : undefined;
    process.exitCode =
      typeof summary === "object" &&
      summary !== null &&
      "failed" in summary &&
      typeof summary.failed === "number" &&
      summary.failed > 0
        ? 1
        : 0;
  } catch (error) {
    writeError(error, json);
    process.exitCode = 1;
  }
}

function inferSensorTarget(args: readonly string[]): string | undefined {
  for (let index = args.length - 1; index >= 0; index -= 1) {
    const arg = args[index];
    if (arg && !arg.startsWith("-")) {
      return arg;
    }
  }
  return undefined;
}

function exitCodeForReport(report: CliReport): number {
  switch (report.command) {
    case "apply":
      return report.status === "error" || report.status === "conflict" ? 1 : 0;
    case "init":
      return report.status === "error" || report.status === "conflict" ? 1 : 0;
    case "diagnose":
      return report.healthy ? 0 : 1;
    case "merge":
      return report.status === "error" ? 1 : 0;
    case "validate":
      return report.status === "valid" ? 0 : 1;
    case "generate":
      return report.status === "generated" ? 0 : 1;
    case "status":
      return report.status === "healthy" ? 0 : 1;
    case "finalize":
      return report.status === "failed" ? 1 : 0;
  }
}

function parseMergeStrategy(value: string | undefined): "keep" | "replace" | "skip" {
  if (value === "keep" || value === "replace" || value === "skip") {
    return value;
  }

  throw new CliError("invalid-merge-strategy", "merge strategy must be keep, replace, or skip", [
    {
      code: "invalid-merge-strategy",
      message: `unsupported merge strategy '${value ?? ""}'`
    }
  ]);
}

function parseGithubRemote(value: string | undefined): "apply" | "skip" {
  if (value === "apply" || value === "skip" || value === undefined) {
    return value ?? "skip";
  }

  throw new CliError("invalid-github-remote", "github remote mode must be apply or skip", [
    { code: "invalid-github-remote", message: `unsupported github remote mode '${value}'` }
  ]);
}

function parseReleaseValidation(value: string | undefined): "real" | "readiness" {
  if (value === "real" || value === "readiness" || value === undefined) {
    return value ?? "readiness";
  }

  throw new CliError("invalid-release-validation", "release validation mode must be real or readiness", [
    { code: "invalid-release-validation", message: `unsupported release validation mode '${value}'` }
  ]);
}

if (process.argv[1] && realpathSync(fileURLToPath(import.meta.url)) === realpathSync(process.argv[1])) {
  await runCli();
}
