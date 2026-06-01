#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join, resolve } from "node:path";

const result = spawnSync("dayu-harness", ["sensor", "validate", ...process.argv.slice(2)], { stdio: "inherit" });
if (!result.error) {
  process.exit(result.status ?? 0);
}
if (result.error.code !== "ENOENT") {
  console.error(`ERROR: unable to run dayu-harness sensor validate: ${result.error.message}`);
  process.exit(1);
}

const options = parseArgs(process.argv.slice(2));
const fallbackReport = runValidate(options.targetRoot);
emit(fallbackReport, options.json);
process.exit(fallbackReport.summary.failed > 0 ? 1 : 0);

function runValidate(targetRoot) {
  const projectRoot = resolve(targetRoot ?? process.cwd());
  const checks = [];

  const version = projectVersion(projectRoot);
  checks.push({ item: "VERSION", status: version ? "pass" : "warn", detail: version ? `project version ${version}` : "VERSION and package.json version are missing" });

  for (const hook of ["commit-msg", "pre-commit", "pre-push"]) {
    const path = join(projectRoot, ".husky", hook);
    if (!existsSync(path)) {
      checks.push({ item: `husky/${hook}`, status: "skip", detail: `.husky/${hook} is not installed` });
      continue;
    }
    checks.push({ item: `husky/${hook}`, status: isExecutable(path) ? "pass" : "fail", detail: isExecutable(path) ? "executable" : "not executable" });
  }

  checkAny(projectRoot, checks, "commitlint", ["commitlint.config.cjs", "commitlint.config.js"]);
  checkGitHubIssueAssets(projectRoot, checks);
  checkGitHubPrAssets(projectRoot, checks);
  checkJson(projectRoot, checks, "repo-config/pull-request-settings", ".github/repository/pull-request-settings.json");
  checkPullRequestSettings(projectRoot, checks, ".github/repository/pull-request-settings.json");
  checkReleaseAssets(projectRoot, checks);
  checkTddAssets(projectRoot, checks);
  checkAny(projectRoot, checks, "ESLint", ["eslint.config.cjs", "eslint.config.js", ".eslintrc.cjs", ".eslintrc.js", ".eslintrc.json", ".eslintrc"]);
  checkAny(projectRoot, checks, "Prettier", [".prettierrc", ".prettierrc.json", ".prettierrc.js", "prettier.config.js"]);
  checkAny(projectRoot, checks, ".gitignore", [".gitignore"]);

  const workflowDir = join(projectRoot, ".github", "workflows");
  if (existsSync(workflowDir)) {
    for (const entry of safeReadDir(workflowDir).filter((file) => file.endsWith(".yml") || file.endsWith(".yaml"))) {
      if (["issue-lint.yml", "pr-lint.yml", "release-please.yml"].includes(entry)) continue;
      checkWorkflow(projectRoot, checks, `workflow/${entry}`, join(".github", "workflows", entry));
    }
  } else {
    checks.push({ item: "workflow", status: "skip", detail: ".github/workflows/ is not installed" });
  }

  const failed = checks.filter((check) => check.status === "fail").length;
  const skipped = checks.filter((check) => check.status === "skip").length;
  return {
    checks,
    summary: { passed: checks.filter((check) => check.status === "pass").length, failed },
    description_nl: failed === 0 && skipped === 0 ? "All validation checks passed." : failed === 0 ? `Validation passed with ${skipped} skipped checks.` : `${failed} validation checks failed.`
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

function checkAny(root, checks, item, candidates) {
  const found = candidates.find((rel) => existsSync(join(root, rel)));
  checks.push({ item, status: found ? "pass" : "skip", detail: found ? `${found} exists` : `${item} is not installed` });
}

function checkJson(root, checks, item, rel, required = false) {
  const path = join(root, rel);
  if (!existsSync(path)) {
    checks.push({ item, status: required ? "fail" : "skip", detail: required ? `${rel} is missing` : `${rel} is not installed` });
    return;
  }
  try {
    JSON.parse(readFileSync(path, "utf8"));
    checks.push({ item, status: "pass", detail: "valid JSON" });
  } catch (error) {
    checks.push({ item, status: "fail", detail: `invalid JSON: ${error.message}` });
  }
}

function checkWorkflow(root, checks, item, rel, required = false) {
  const path = join(root, rel);
  if (!existsSync(path)) {
    checks.push({ item, status: required ? "fail" : "skip", detail: required ? `${rel} is missing` : `${rel} is not installed` });
    return;
  }
  const yaml = spawnSync("python3", ["-c", "import yaml"], { stdio: ["ignore", "pipe", "pipe"] });
  if (yaml.status !== 0) {
    checks.push({ item, status: "skip", detail: "python3 yaml is unavailable, skipped YAML syntax check" });
    return;
  }
  const result = spawnSync("python3", ["-c", "import sys,yaml; yaml.safe_load(open(sys.argv[1]))", path], { encoding: "utf8" });
  checks.push({ item, status: result.status === 0 ? "pass" : "fail", detail: result.status === 0 ? `${rel} has valid YAML` : `${rel} YAML error: ${firstError(result.stderr)}` });
}

function checkPython(root, checks, item, rel, required = false) {
  const path = join(root, rel);
  if (!existsSync(path)) {
    checks.push({ item, status: required ? "fail" : "skip", detail: required ? `${rel} is missing` : `${rel} is not installed` });
    return;
  }
  const result = spawnSync("python3", ["-c", "import sys; compile(open(sys.argv[1], 'r', encoding='utf-8').read(), sys.argv[1], 'exec')", path], { encoding: "utf8" });
  checks.push({ item, status: result.status === 0 ? "pass" : "fail", detail: result.status === 0 ? `${rel} has valid Python syntax` : `${rel} Python error: ${firstError(result.stderr)}` });
}

function checkGitHubIssueAssets(root, checks) {
  const enabled = [".github/workflows/issue-lint.yml", ".github/scripts/issue_depends_on.py", ".github/ISSUE_TEMPLATE/dayu-harness-issue.md"].some((rel) => existsSync(join(root, rel)));
  if (!enabled) {
    checks.push({ item: "repo-workflow/issue-lint", status: "skip", detail: "issue-lint is not installed" });
    checks.push({ item: "repo-template/issue", status: "skip", detail: "issue template is not installed" });
    checks.push({ item: "repo-script/issue_depends_on.py", status: "skip", detail: "issue dependency script is not installed" });
    return;
  }
  checkWorkflow(root, checks, "repo-workflow/issue-lint", ".github/workflows/issue-lint.yml", true);
  checkRequired(root, checks, "repo-template/issue", ".github/ISSUE_TEMPLATE/dayu-harness-issue.md");
  checkPython(root, checks, "repo-script/issue_depends_on.py", ".github/scripts/issue_depends_on.py", true);
}

function checkGitHubPrAssets(root, checks) {
  const enabled = [".github/workflows/pr-lint.yml", ".github/scripts/pr_body_structure.py", ".github/pull_request_template.md"].some((rel) => existsSync(join(root, rel)));
  if (!enabled) {
    checks.push({ item: "repo-workflow/pr-lint", status: "skip", detail: "pr-lint is not installed" });
    checks.push({ item: "repo-template/pull-request", status: "skip", detail: "pull request template is not installed" });
    checks.push({ item: "repo-script/pr-body-structure.py", status: "skip", detail: "PR body script is not installed" });
    return;
  }
  checkWorkflow(root, checks, "repo-workflow/pr-lint", ".github/workflows/pr-lint.yml", true);
  checkRequired(root, checks, "repo-template/pull-request", ".github/pull_request_template.md");
  checkPython(root, checks, "repo-script/pr-body-structure.py", ".github/scripts/pr_body_structure.py", true);
}

function checkPullRequestSettings(root, checks, rel) {
  const path = join(root, rel);
  if (!existsSync(path)) {
    checks.push({ item: "repo-config/pull-request-settings-auto", status: "skip", detail: `${rel} is not installed` });
    return;
  }
  try {
    const parsed = JSON.parse(readFileSync(path, "utf8"));
    const failures = [
      ["allow_merge_commit", true],
      ["allow_squash_merge", false],
      ["allow_rebase_merge", false],
      ["allow_auto_merge", true],
      ["delete_branch_on_merge", true]
    ].filter(([key, expected]) => parsed[key] !== expected);
    checks.push({ item: "repo-config/pull-request-settings-auto", status: failures.length === 0 ? "pass" : "fail", detail: failures.length === 0 ? `${rel} merge policy is valid` : `${rel} invalid merge policy: ${failures.map(([key, expected]) => `${key}=${expected}`).join(", ")}` });
  } catch (error) {
    checks.push({ item: "repo-config/pull-request-settings-auto", status: "fail", detail: `${rel} parse error: ${error.message}` });
  }
}

function checkReleaseAssets(root, checks) {
  const enabled = [".github/workflows/release-please.yml", ".github/scripts/release_please_policy.py", ".github/release-please-policy.json", "release-please-config.json", ".release-please-manifest.json"].some((rel) => existsSync(join(root, rel)));
  if (!enabled) {
    checks.push({ item: "release/repository-settings-policy", status: "skip", detail: "release-please policy is not installed" });
    checks.push({ item: "release/release-please-config", status: "skip", detail: "release-please config is not installed" });
    checks.push({ item: "release/release-please-manifest", status: "skip", detail: "release-please manifest is not installed" });
    checks.push({ item: "release/workflow", status: "skip", detail: "release-please workflow is not installed" });
    checks.push({ item: "release/release-please-policy-script", status: "skip", detail: "release-please policy script is not installed" });
    checks.push({ item: "release/release-please-policy", status: "skip", detail: "release-please policy execution is not installed" });
    return;
  }
  checkJson(root, checks, "release/repository-settings-policy", ".github/release-please-policy.json", true);
  checkJson(root, checks, "release/release-please-config", "release-please-config.json", true);
  checkJson(root, checks, "release/release-please-manifest", ".release-please-manifest.json", true);
  checkWorkflow(root, checks, "release/workflow", ".github/workflows/release-please.yml", true);
  checkPython(root, checks, "release/release-please-policy-script", ".github/scripts/release_please_policy.py", true);
}

function checkTddAssets(root, checks) {
  const enabled = [".github/dayu-harness/pr-tdd-policy.json", ".github/scripts/pr_tdd_check.py"].some((rel) => existsSync(join(root, rel)));
  if (!enabled) {
    checks.push({ item: "quality/pr-tdd-policy", status: "skip", detail: "TDD policy is not installed" });
    checks.push({ item: "quality/pr-tdd-check-script", status: "skip", detail: "TDD script is not installed" });
    return;
  }
  checkJson(root, checks, "quality/pr-tdd-policy", ".github/dayu-harness/pr-tdd-policy.json", true);
  checkPython(root, checks, "quality/pr-tdd-check-script", ".github/scripts/pr_tdd_check.py", true);
}

function checkRequired(root, checks, item, rel) {
  checks.push({ item, status: existsSync(join(root, rel)) ? "pass" : "fail", detail: existsSync(join(root, rel)) ? `${rel} exists` : `${rel} is missing` });
}

function safeReadDir(path) {
  try {
    return readdirSync(path);
  } catch {
    return [];
  }
}

function firstError(text) {
  return String(text ?? "").split(/\r?\n/).find((line) => line.trim())?.trim() ?? "unknown";
}

function projectVersion(root) {
  const versionPath = join(root, "VERSION");
  if (existsSync(versionPath)) return readFileSync(versionPath, "utf8").trim();
  const packagePath = join(root, "package.json");
  if (!existsSync(packagePath)) return "";
  try {
    return JSON.parse(readFileSync(packagePath, "utf8")).version ?? "";
  } catch {
    return "";
  }
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
  for (const item of report.checks.filter((entry) => entry.status === "fail")) {
    console.log(`- [${item.status}] ${item.item}: ${item.detail}`);
  }
}
