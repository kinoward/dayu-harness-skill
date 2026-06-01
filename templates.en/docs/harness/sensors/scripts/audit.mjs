#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, statSync } from "node:fs";
import { join, resolve } from "node:path";

const result = spawnSync("dayu-harness", ["sensor", "audit", ...process.argv.slice(2)], { stdio: "inherit" });
if (!result.error) {
  process.exit(result.status ?? 0);
}
if (result.error.code !== "ENOENT") {
  console.error(`ERROR: unable to run dayu-harness sensor audit: ${result.error.message}`);
  process.exit(1);
}

const options = parseArgs(process.argv.slice(2));
const fallbackReport = runAudit(options.targetRoot);
emit(fallbackReport, options.json);
process.exit(fallbackReport.summary.failed > 0 ? 1 : 0);

function runAudit(targetRoot) {
  const projectRoot = resolve(targetRoot ?? process.cwd());
  const checks = [];
  record(checks, "CLAUDE.md", existsSync(join(projectRoot, "CLAUDE.md")), "CLAUDE.md exists", "CLAUDE.md is missing");
  record(checks, "AGENTS.md", existsSync(join(projectRoot, "AGENTS.md")), "root AGENTS.md exists", "root AGENTS.md is missing");
  record(checks, "docs/AGENTS.md", existsSync(join(projectRoot, "docs", "AGENTS.md")), "docs/AGENTS.md exists", "docs/AGENTS.md is missing");

  for (const dir of [
    "docs/harness",
    "docs/harness/guides",
    "docs/harness/sensors",
    "docs/harness/sensors/scripts",
    "docs/exec-plans",
    "docs/generated",
    "docs/design-docs",
    "docs/troubleshooting",
    "docs/references",
    "docs/product-specs",
    "docs/archive"
  ]) {
    const path = join(projectRoot, dir);
    if (!existsSync(path)) {
      checks.push({ check: dir, status: "warn", detail: `${dir} is missing or not enabled` });
      continue;
    }
    record(checks, `${dir}/AGENTS.md`, existsSync(join(path, "AGENTS.md")), `${dir}/AGENTS.md exists`, `${dir}/AGENTS.md is missing`, "warn");
  }

  for (const hook of ["commit-msg", "pre-commit", "pre-push"]) {
    const path = join(projectRoot, ".husky", hook);
    if (!existsSync(path)) {
      checks.push({ check: `hook/${hook}`, status: "warn", detail: `.husky/${hook} is not installed` });
      continue;
    }
    checks.push({ check: `hook/${hook}`, status: isExecutable(path) ? "pass" : "warn", detail: `.husky/${hook} ${isExecutable(path) ? "is executable" : "is not executable"}` });
  }

  for (const script of ["audit.mjs", "validate.mjs", "diff-helper.mjs", "check-consistency.mjs", "dayu-format.mjs"]) {
    const path = join(projectRoot, "docs/harness/sensors/scripts", script);
    if (!existsSync(path)) {
      checks.push({ check: `sensor/${script}`, status: "warn", detail: `${script} is not installed` });
      continue;
    }
    checks.push({ check: `sensor/${script}`, status: isExecutable(path) ? "pass" : "warn", detail: `${script} ${isExecutable(path) ? "is executable" : "is not executable"}` });
  }

  const failed = checks.filter((check) => check.status === "fail").length;
  const warnings = checks.filter((check) => check.status === "warn").length;
  return {
    results: checks,
    summary: { total: checks.length, passed: checks.filter((check) => check.status === "pass").length, failed, warnings },
    description_nl: failed === 0 && warnings === 0 ? `Governance audit passed (${checks.length} checks).` : `Governance audit found ${failed} failures and ${warnings} warnings.`
  };
}

function parseArgs(args) {
  let json = false;
  let targetRoot;
  for (const arg of args) {
    if (arg === "--json") {
      json = true;
      continue;
    }
    if (!arg.startsWith("-")) targetRoot = arg;
  }
  return { json, targetRoot };
}

function record(checks, check, condition, pass, fail, failStatus = "fail") {
  checks.push({ check, status: condition ? "pass" : failStatus, detail: condition ? pass : fail });
}

function isExecutable(path) {
  try {
    return (statSync(path).mode & 0o111) !== 0;
  } catch {
    return false;
  }
}

function emit(report, json) {
  if (json) {
    console.log(JSON.stringify(report, null, 2));
    return;
  }
  console.log(report.description_nl);
  for (const item of report.results.filter((entry) => entry.status !== "pass")) {
    console.log(`- [${item.status}] ${item.check}: ${item.detail}`);
  }
}
