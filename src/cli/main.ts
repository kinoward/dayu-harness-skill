#!/usr/bin/env -S node --import tsx
import { Command } from "commander";
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

import { applyDayuConfig, initDayuConfig } from "./apply.js";
import { diagnoseDayuProject } from "./diagnose.js";
import { generateDayuContent } from "./generate.js";
import { planDayuMerge } from "./merge.js";
import { writeError, writeReport, type CliReport } from "./output.js";
import { validateDayuProject } from "./validate.js";

interface CommonOptions {
  config?: string;
  target?: string;
  dryRun?: boolean;
  json?: boolean;
  locale?: "zh" | "en";
  capability?: string;
}

export function buildProgram(): Command {
  const program = new Command();

  program.name("dayu-harness").description("Dayu Harness Phase 1d TypeScript CLI").option("--json", "emit JSON");

  program
    .command("init")
    .description("create dayu.config.yaml when missing, then apply it")
    .option("--config <path>", "config path")
    .option("--target <path>", "target project root")
    .option("--locale <locale>", "default config locale: zh or en", "zh")
    .option("--dry-run", "preview without writing")
    .option("--json", "emit JSON")
    .action((options: CommonOptions, command: Command) =>
      execute(command, () =>
        initDayuConfig({
          configPath: options.config,
          targetRoot: options.target,
          dryRun: options.dryRun,
          locale: options.locale
        })
      )
    );

  program
    .command("apply")
    .description("read config, resolve the deployment DAG, and deploy files")
    .option("--config <path>", "config path")
    .option("--target <path>", "target project root")
    .option("--dry-run", "preview without writing")
    .option("--json", "emit JSON")
    .action((options: CommonOptions, command: Command) =>
      execute(command, () =>
        applyDayuConfig({
          configPath: options.config,
          targetRoot: options.target,
          dryRun: options.dryRun
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
    .command("merge")
    .description("build a capability-granular merge plan")
    .option("--config <path>", "config path")
    .option("--target <path>", "target project root")
    .option("--dry-run", "preview without writing", true)
    .option("--json", "emit JSON")
    .action((options: CommonOptions, command: Command) =>
      execute(command, () =>
        planDayuMerge({
          configPath: options.config,
          targetRoot: options.target,
          dryRun: true
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
    .command("generate")
    .description("render content previews without applying the full scaffold flow")
    .option("--config <path>", "config path")
    .option("--target <path>", "target project root")
    .option("--capability <id>", "limit previews to one requested capability")
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

  return program;
}

export async function runCli(argv: readonly string[] = process.argv): Promise<void> {
  const program = buildProgram();
  await program.parseAsync(argv);
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
  }
}

if (process.argv[1] && realpathSync(fileURLToPath(import.meta.url)) === realpathSync(process.argv[1])) {
  await runCli();
}
