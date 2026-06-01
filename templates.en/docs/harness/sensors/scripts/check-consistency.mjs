#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, extname, join, relative, resolve } from "node:path";

const result = spawnSync("dayu-harness", ["sensor", "check-consistency", ...process.argv.slice(2)], { stdio: "inherit" });
if (!result.error) {
  process.exit(result.status ?? 0);
}
if (result.error.code !== "ENOENT") {
  console.error(`ERROR: unable to run dayu-harness sensor check-consistency: ${result.error.message}`);
  process.exit(1);
}

const options = parseArgs(process.argv.slice(2));
const fallbackReport = runConsistency(options.targetRoot);
emit(fallbackReport, options.json);
process.exit(fallbackReport.summary.failed > 0 ? 1 : 0);

function runConsistency(targetRoot) {
  const projectRoot = resolve(targetRoot ?? process.cwd());
  const agentsFiles = findFiles(projectRoot, (rel) => rel.endsWith("AGENTS.md"));
  const referenced = new Set();
  const linkIssues = [];

  for (const agentsFile of agentsFiles) {
    const absolute = join(projectRoot, agentsFile);
    const base = dirname(agentsFile);
    const lines = readFileSync(absolute, "utf8").split(/\r?\n/);
    lines.forEach((line, index) => {
      for (const match of line.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)) {
        const target = match[1].split("#")[0].trim();
        if (!target || /^[a-z]+:\/\//i.test(target) || target.startsWith("mailto:")) continue;
        const rel = normalizeRelative(base, target);
        if (existsSync(join(projectRoot, rel))) {
          referenced.add(rel.replace(/\/$/, ""));
        } else {
          linkIssues.push(`${agentsFile}:${index + 1}\t${rel}\ttarget missing`);
        }
      }
    });
  }

  const docs = findFiles(join(projectRoot, "docs"), (rel) => extname(rel) === ".md").map((rel) => `docs/${rel}`);
  const orphanIssues = docs.filter((rel) => !rel.endsWith("AGENTS.md") && !referenced.has(rel)).map((rel) => `${rel}\tnot referenced by AGENTS index`);
  const checks = [
    { id: "C1", name: "link validity", issues: linkIssues },
    { id: "C2", name: "AGENTS files discovered", issues: agentsFiles.length > 0 ? [] : ["no AGENTS.md files found"] },
    { id: "C3", name: "orphan docs", issues: orphanIssues },
    { id: "C4", name: "sensor scripts", issues: ["audit.mjs", "validate.mjs", "diff-helper.mjs"].filter((file) => !existsSync(join(projectRoot, "docs/harness/sensors/scripts", file))).map((file) => `${file} missing`) }
  ];
  const failed = checks.filter((check) => check.issues.length > 0).length;
  return {
    checks: checks.map((check) => ({
      id: check.id,
      name: check.name,
      status: check.issues.length === 0 ? "pass" : "fail",
      issues: check.issues,
      detail: check.issues.length === 0 ? `${check.name} passed.` : `${check.issues.length} issue(s) found.`
    })),
    summary: { total: checks.length, passed: checks.length - failed, failed },
    description_nl: failed === 0 ? "All consistency checks passed." : `${failed} consistency checks failed.`
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

function findFiles(root, predicate, prefix = "") {
  if (!existsSync(root)) return [];
  const out = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name === ".git") continue;
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name;
    const abs = join(root, entry.name);
    if (entry.isDirectory()) {
      out.push(...findFiles(abs, predicate, rel));
    } else if (predicate(rel)) {
      out.push(rel);
    }
  }
  return out.sort();
}

function normalizeRelative(base, target) {
  return relative(".", resolve(base || ".", target)).split("\\").join("/");
}

function emit(report, json) {
  if (json) {
    console.log(JSON.stringify(report, null, 2));
    return;
  }
  console.log(report.description_nl);
  for (const check of report.checks.filter((entry) => entry.status !== "pass")) {
    console.log(`- [${check.status}] ${check.id} ${check.name}: ${check.detail}`);
  }
}
