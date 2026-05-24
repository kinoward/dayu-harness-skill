#!/usr/bin/env node
import { Command } from "commander";
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { applyDayuConfig, initDayuConfig } from "./apply.js";
import { diagnoseDayuProject } from "./diagnose.js";
import { CliError } from "./errors.js";
import { generateDayuContent } from "./generate.js";
import { applyDayuMerge, planDayuMerge } from "./merge.js";
import { writeError, writeReport, type CliReport } from "./output.js";
import { repairDayuCapability } from "./repair.js";
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

if (process.argv[1] && realpathSync(fileURLToPath(import.meta.url)) === realpathSync(process.argv[1])) {
  await runCli();
}
