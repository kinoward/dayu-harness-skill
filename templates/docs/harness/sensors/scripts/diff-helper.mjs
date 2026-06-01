#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { basename } from "node:path";

const result = spawnSync("dayu-harness", ["sensor", "diff-helper", ...process.argv.slice(2)], { stdio: "inherit" });
if (!result.error) {
  process.exit(result.status ?? 0);
}
if (result.error.code !== "ENOENT") {
  console.error(`ERROR: unable to run dayu-harness sensor diff-helper: ${result.error.message}`);
  process.exit(1);
}

const fallbackResult = runDiffHelper(process.argv.slice(2));
process.stdout.write(fallbackResult.output);
process.exit(fallbackResult.code);

function runDiffHelper(argv) {
  const [mode = "diff", file1 = "", file2 = ""] = argv;
  if (mode === "check") {
    if (!file1) return { output: usage(), code: 2 };
    return existsSync(file1) ? { output: `exists: ${file1}\n`, code: 0 } : { output: `missing: ${file1}\n`, code: 1 };
  }
  if (!file1 || !file2) return { output: usage(), code: 2 };
  if (mode === "diff") {
    const output = diffFiles(file1, file2);
    return { output, code: output.startsWith("ERROR:") ? 1 : 0 };
  }
  if (mode === "describe") {
    const counts = countDiff(file1, file2);
    const output = `=== Change description ===\nFile: ${basename(file1)} -> ${basename(file2)}\n\nAdded ${counts.added} lines, removed ${counts.removed} lines.\n\n--- diff ---\n${diffFiles(file1, file2)}`;
    return { output, code: output.includes("ERROR: file not found:") ? 1 : 0 };
  }
  if (mode === "merge-plan") {
    const plan = mergePlan(file1, file2);
    return { output: `${JSON.stringify(plan, null, 2)}\n`, code: plan.status === "error" ? 1 : 0 };
  }
  return { output: usage(), code: 2 };
}

function usage() {
  return "Usage: diff-helper.mjs [diff|describe|merge-plan] <existing> <incoming>\n       diff-helper.mjs check <file>\n";
}

function diffFiles(file1, file2) {
  if (!existsSync(file1)) return `ERROR: file not found: ${file1}\n`;
  if (!existsSync(file2)) return `ERROR: file not found: ${file2}\n`;
  const left = readFileSync(file1, "utf8").split(/\r?\n/);
  const right = readFileSync(file2, "utf8").split(/\r?\n/);
  const lines = [`--- ${file1}`, `+++ ${file2}`];
  const max = Math.max(left.length, right.length);
  for (let index = 0; index < max; index += 1) {
    if (left[index] === right[index]) continue;
    if (left[index] !== undefined) lines.push(`-${left[index]}`);
    if (right[index] !== undefined) lines.push(`+${right[index]}`);
  }
  return `${lines.join("\n")}\n`;
}

function countDiff(file1, file2) {
  const diff = diffFiles(file1, file2).split(/\r?\n/);
  return {
    added: diff.filter((line) => line.startsWith("+") && !line.startsWith("+++")).length,
    removed: diff.filter((line) => line.startsWith("-") && !line.startsWith("---")).length
  };
}

function mergePlan(file1, file2) {
  const existingExists = existsSync(file1);
  const incomingExists = existsSync(file2);
  if (!existingExists || !incomingExists) {
    return {
      status: incomingExists ? "clean" : "error",
      existing: { path: file1, exists: existingExists, lines: existingExists ? readFileSync(file1, "utf8").split(/\r?\n/).length : 0 },
      incoming: { path: file2, exists: incomingExists, lines: incomingExists ? readFileSync(file2, "utf8").split(/\r?\n/).length : 0 },
      diff: incomingExists ? countDiff("/dev/null", file2) : { added: 0, removed: 0 },
      recommendation: incomingExists ? "merge" : "manual_required",
      strategies: incomingExists ? ["merge", "replace", "skip"] : ["replace", "skip"],
      description_nl: incomingExists ? `目标项目中暂无 ${file2}。可安全写入。` : `Incoming file not found: ${file2}.`
    };
  }
  const same = readFileSync(file1, "utf8") === readFileSync(file2, "utf8");
  const counts = countDiff(file1, file2);
  const manual = isManualMergeRequired(file2);
  return {
    status: manual && existingExists ? "manual_required" : "conflict",
    existing: { path: file1, exists: true, lines: readFileSync(file1, "utf8").split(/\r?\n/).length },
    incoming: { path: file2, exists: true, lines: readFileSync(file2, "utf8").split(/\r?\n/).length },
    diff: counts,
    recommendation: same ? "skip" : manual ? "manual_required" : "merge",
    strategies: manual ? ["replace", "skip"] : ["merge", "replace", "skip"],
    description_nl: same ? "Files are identical." : `检测到已有 ${file1}。建议在应用前人工确认。`
  };
}

function isManualMergeRequired(target) {
  return /\.(ya?ml|js|cjs|mjs|json|json5)$/.test(target) || /(^|\/)(package\.json|commitlint\.config\.cjs|eslint\.config\.)/.test(target);
}
