import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";

export interface SensorRunOptions {
  targetRoot?: string;
  json?: boolean;
}

interface RecordedCheck {
  check?: string;
  item?: string;
  id?: string;
  name?: string;
  status: "pass" | "fail" | "warn" | "skip";
  detail: string;
  issues?: string[];
}

const OPTIONAL_CAPABILITIES = new Set([
  "ai.execution",
  "ai.memory",
  "git.commit-format",
  "github.branch-protection",
  "github.pr",
  "github.repository-settings",
  "github.issue",
  "github.release-please",
  "quality.tdd",
  "knowledge.archive",
  "knowledge.adr",
  "knowledge.research",
  "knowledge.troubleshooting",
  "project.context",
  "project.gitignore",
  "quality.node-tooling",
  "quality.practices",
  "release.versioning"
]);

const SENSOR_FILES = ["audit.mjs", "validate.mjs", "diff-helper.mjs", "check-consistency.mjs", "dayu-format.mjs"];

export function runAuditSensor(options: SensorRunOptions = {}) {
  const projectRoot = resolve(options.targetRoot ?? process.cwd());
  const checks: RecordedCheck[] = [];

  record(checks, "CLAUDE.md", existsSync(join(projectRoot, "CLAUDE.md")), "CLAUDE.md 存在", "CLAUDE.md 不存在");
  if (existsSync(join(projectRoot, "CLAUDE.md"))) {
    const claude = readText(join(projectRoot, "CLAUDE.md"));
    if (!claude.includes("@AGENTS.md")) {
      checks.push({ check: "CLAUDE.md", status: "warn", detail: "CLAUDE.md 存在但未引用 @AGENTS.md" });
    }
  }
  record(checks, "AGENTS.md", existsSync(join(projectRoot, "AGENTS.md")), "根 AGENTS.md 存在", "根 AGENTS.md 不存在");
  record(checks, "docs/AGENTS.md", existsSync(join(projectRoot, "docs", "AGENTS.md")), "docs/AGENTS.md 存在", "docs/AGENTS.md 不存在");

  for (const dir of [
    "docs/harness",
    "docs/harness/guides",
    "docs/harness/sensors",
    "docs/harness/sensors/scripts",
    "docs/harness/sensors/reviews",
    "docs/exec-plans",
    "docs/exec-plans/active",
    "docs/exec-plans/completed",
    "docs/generated",
    "docs/design-docs",
    "docs/troubleshooting",
    "docs/references",
    "docs/references/research",
    "docs/product-specs",
    "docs/archive",
    "docs/archive/product-specs"
  ]) {
    if (!existsSync(join(projectRoot, dir))) {
      checks.push({ check: `${dir}/AGENTS.md`, status: "warn", detail: `${dir}/ 目录不存在（可能已跳过）` });
      continue;
    }
    record(checks, `${dir}/AGENTS.md`, existsSync(join(projectRoot, dir, "AGENTS.md")), `${dir}/AGENTS.md 存在`, `${dir}/ 目录存在但缺少 AGENTS.md`, "warn");
  }

  for (const hook of ["commit-msg", "pre-commit", "pre-push"]) {
    const path = join(projectRoot, ".husky", hook);
    if (!existsSync(path)) {
      checks.push({ check: `hook/${hook}`, status: "warn", detail: `.husky/${hook} 未安装` });
      continue;
    }
    checks.push({
      check: `hook/${hook}`,
      status: isExecutable(path) ? "pass" : "warn",
      detail: isExecutable(path) ? `.husky/${hook} 已安装且可执行` : `.husky/${hook} 已安装但不可执行`
    });
  }

  for (const script of SENSOR_FILES) {
    const path = join(projectRoot, "docs/harness/sensors/scripts", script);
    if (!existsSync(path)) {
      checks.push({ check: `sensor/${script}`, status: "warn", detail: `docs/harness/sensors/scripts/${script} 未安装` });
      continue;
    }
    checks.push({
      check: `sensor/${script}`,
      status: isExecutable(path) ? "pass" : "warn",
      detail: isExecutable(path) ? `${script} 已安装且可执行` : `${script} 已安装但不可执行`
    });
  }

  const failed = checks.filter((check) => check.status === "fail").length;
  const warnings = checks.filter((check) => check.status === "warn").length;
  return {
    results: checks.map((check) => ({
      check: check.check ?? check.name ?? "",
      status: check.status,
      detail: check.detail
    })),
    summary: {
      total: checks.length,
      passed: checks.filter((check) => check.status === "pass").length,
      failed,
      warnings
    },
    description_nl:
      failed === 0 && warnings === 0
        ? `项目治理体系完整性检查全部通过。共检查 ${checks.length} 项。`
        : `项目治理体系存在 ${failed} 个失败项和 ${warnings} 个警告项。`
  };
}

export function runValidateSensor(options: SensorRunOptions = {}) {
  const projectRoot = resolve(options.targetRoot ?? process.cwd());
  const checks: RecordedCheck[] = [];

  checkProjectVersion(projectRoot, checks);
  for (const hook of ["commit-msg", "pre-commit", "pre-push"]) {
    const path = join(projectRoot, ".husky", hook);
    if (!existsSync(path)) {
      checks.push({ item: `husky/${hook}`, status: "skip", detail: `.husky/${hook} 未安装` });
      continue;
    }
    checks.push({
      item: `husky/${hook}`,
      status: isExecutable(path) ? "pass" : "fail",
      detail: isExecutable(path) ? "可执行" : "文件存在但不可执行"
    });
  }

  const commitlint = firstExisting(projectRoot, ["commitlint.config.cjs", "commitlint.config.js"]);
  checks.push({ item: "commitlint", status: commitlint ? "pass" : "skip", detail: commitlint ? `${commitlint} 存在` : "commitlint 配置文件不存在（可能未启用）" });

  checkGitHubIssueAssets(projectRoot, checks);
  checkGitHubPrAssets(projectRoot, checks);
  checkJson(projectRoot, checks, "repo-config/pull-request-settings", ".github/repository/pull-request-settings.json");
  checkPullRequestSettings(projectRoot, checks, ".github/repository/pull-request-settings.json");
  checkReleaseAssets(projectRoot, checks);
  checkTddAssets(projectRoot, checks);

  checkPlain(projectRoot, checks, "ESLint", ["eslint.config.cjs", "eslint.config.js", ".eslintrc.cjs", ".eslintrc.js", ".eslintrc.json", ".eslintrc"]);
  checkPlain(projectRoot, checks, "Prettier", [".prettierrc", ".prettierrc.json", ".prettierrc.js", "prettier.config.js"]);
  checkPlain(projectRoot, checks, ".gitignore", [".gitignore"]);

  const workflowDir = join(projectRoot, ".github", "workflows");
  if (existsSync(workflowDir)) {
    for (const entry of safeReadDir(workflowDir).filter((file) => file.endsWith(".yml") || file.endsWith(".yaml"))) {
      const item = `workflow/${entry}`;
      if (["issue-lint.yml", "pr-lint.yml", "release-please.yml"].includes(entry)) continue;
      checkWorkflowFile(projectRoot, checks, item, join(".github", "workflows", entry));
    }
  } else {
    checks.push({ item: "workflow", status: "skip", detail: ".github/workflows/ 目录不存在（可能未启用 CI）" });
  }

  const failed = checks.filter((check) => check.status === "fail").length;
  const skipped = checks.filter((check) => check.status === "skip").length;
  return {
    checks: checks.map((check) => ({
      item: check.item ?? check.check ?? "",
      status: check.status,
      detail: check.detail
    })),
    summary: {
      passed: checks.filter((check) => check.status === "pass").length,
      failed
    },
    description_nl:
      failed === 0 && skipped === 0
        ? "所有校验项均通过。"
        : failed === 0
          ? `校验通过，但存在 ${skipped} 个跳过项。`
          : `存在 ${failed} 个校验失败项。`
  };
}

export function runConsistencySensor(options: SensorRunOptions = {}) {
  const projectRoot = resolve(options.targetRoot ?? process.cwd());
  const agentsFiles = findAgentsFiles(projectRoot);
  const referenced = new Set<string>();
  const c1Issues: string[] = [];

  for (const agentsFile of agentsFiles) {
    const baseDir = dirname(agentsFile);
    for (const link of extractMarkdownLinks(join(projectRoot, agentsFile))) {
      if (isExternalLink(link.target)) continue;
      const resolved = resolveLink(projectRoot, baseDir, link.target);
      if (!resolved) continue;
      if (existsSync(join(projectRoot, resolved))) {
        referenced.add(resolved.replace(/\/$/, ""));
        continue;
      }
      const optional = extractOptionalCapability(link.raw);
      if (!optional || !OPTIONAL_CAPABILITIES.has(optional)) {
        c1Issues.push(`${agentsFile}:${link.line}\t${resolved}\t目标不存在`);
      }
    }
  }

  const c2Issues = indexCountIssues(projectRoot, agentsFiles);
  const c3Issues = orphanDocIssues(projectRoot, referenced);
  const c4Issues = referencedScriptIssues(projectRoot, referenced);
  const checks = [
    { id: "C1", name: "链接有效性", issues: c1Issues },
    { id: "C2", name: "索引计数", issues: c2Issues },
    { id: "C3", name: "孤儿检测", issues: c3Issues },
    { id: "C4", name: "脚本完整性", issues: c4Issues }
  ];
  const failed = checks.filter((check) => check.issues.length > 0).length;

  return {
    checks: checks.map((check) => ({
      id: check.id,
      name: check.name,
      status: check.issues.length === 0 ? "pass" : "fail",
      issues: check.issues,
      detail: check.issues.length === 0 ? `${check.name}通过。` : `发现 ${check.issues.length} 个问题。`
    })),
    summary: {
      total: checks.length,
      passed: checks.length - failed,
      failed
    },
    description_nl: failed === 0 ? "全部 4 项检查通过，文档体系一致性良好。" : `发现 ${failed} 项问题需要处理。`
  };
}

export function runDiffHelper(argv: readonly string[]): string {
  const [mode = "diff", file1 = "", file2 = ""] = argv;
  if (mode === "check") {
    if (!file1) return usage();
    return existsSync(file1) ? `✓ 已存在: ${file1}\n` : `✗ 不存在: ${file1}\n`;
  }
  if (!file1 || !file2) {
    return usage();
  }
  if (mode === "diff") {
    return diffFiles(file1, file2);
  }
  if (mode === "describe") {
    const counts = countDiff(file1, file2);
    return `=== 变更描述 ===\n文件: ${basename(file1)} -> ${basename(file2)}\n\n新增 ${counts.added} 行，移除 ${counts.removed} 行。\n\n--- diff ---\n${diffFiles(file1, file2)}`;
  }
  if (mode === "merge-plan") {
    return `${JSON.stringify(mergePlan(file1, file2), null, 2)}\n`;
  }
  return usage();
}

function checkProjectVersion(projectRoot: string, checks: RecordedCheck[]): void {
  const values = [
    ["package.json", readPackageVersion(projectRoot)],
    ["package-lock.json", readPackageLockVersion(projectRoot)],
    ["VERSION", readFirstLine(join(projectRoot, "VERSION"))],
    ["CHANGELOG.md", readChangelogVersion(projectRoot)],
    [".release-please-manifest.json", readJsonValue(join(projectRoot, ".release-please-manifest.json"), ".")]
  ].filter(([, value]) => value);

  if (values.length === 0) {
    checks.push({ item: "project/version-sync", status: "skip", detail: "未发现初始化版本源，跳过版本一致性校验" });
    return;
  }
  const expected = values[0][1];
  const mismatches = values.filter(([, value]) => value !== expected).map(([name, value]) => `${name}=${value}`);
  checks.push({
    item: "project/version-sync",
    status: mismatches.length === 0 ? "pass" : "fail",
    detail: mismatches.length === 0 ? `初始化版本源一致：${expected}` : `初始化版本源未对齐：${mismatches.join(", ")}`
  });
}

function checkPlain(projectRoot: string, checks: RecordedCheck[], item: string, paths: readonly string[]): void {
  const found = firstExisting(projectRoot, paths);
  checks.push({ item, status: found ? "pass" : "skip", detail: found ? `${found} 存在` : `${item} 配置文件不存在（可能未启用）` });
}

function firstExisting(projectRoot: string, paths: readonly string[]): string {
  return paths.find((path) => existsSync(join(projectRoot, path))) ?? "";
}

function checkJson(projectRoot: string, checks: RecordedCheck[], item: string, rel: string, required = false): void {
  const path = join(projectRoot, rel);
  if (!existsSync(path)) {
    checks.push({ item, status: required ? "fail" : "skip", detail: required ? `${rel} 缺失（功能可能未正确部署）` : `${rel} 未部署（按可选能力处理）` });
    return;
  }
  try {
    JSON.parse(readFileSync(path, "utf8"));
    checks.push({ item, status: "pass", detail: `${rel} JSON 语法有效` });
  } catch (error) {
    checks.push({ item, status: "fail", detail: `${rel} JSON 语法错误: ${error instanceof Error ? error.message : String(error)}` });
  }
}

function checkWorkflowFile(projectRoot: string, checks: RecordedCheck[], item: string, rel: string, required = false): void {
  const path = join(projectRoot, rel);
  if (!existsSync(path)) {
    checks.push({ item, status: required ? "fail" : "skip", detail: required ? `${rel} 缺失（功能可能未正确部署）` : `${rel} 未部署（按可选能力处理）` });
    return;
  }
  if (!commandOk("python3", ["-c", "import yaml"])) {
    checks.push({ item, status: "skip", detail: "缺少 python3 yaml 库，跳过 YAML 语法校验" });
    return;
  }
  const result = spawnSync("python3", ["-c", "import sys,yaml; yaml.safe_load(open(sys.argv[1]))", path], { encoding: "utf8" });
  checks.push({
    item,
    status: result.status === 0 ? "pass" : "fail",
    detail: result.status === 0 ? `${rel} YAML 语法有效` : `${rel} YAML 语法错误: ${firstErrorLine(result.stderr)}`
  });
}

function checkPythonScript(projectRoot: string, checks: RecordedCheck[], item: string, rel: string, required = false): void {
  const path = join(projectRoot, rel);
  if (!existsSync(path)) {
    checks.push({ item, status: required ? "fail" : "skip", detail: required ? `${rel} 缺失（功能可能未正确部署）` : `${rel} 未部署（按可选能力处理）` });
    return;
  }
  if (!commandOk("python3", ["--version"])) {
    checks.push({ item, status: "skip", detail: "缺少 python3，跳过 Python 语法校验" });
    return;
  }
  const result = spawnSync("python3", ["-c", "import sys; compile(open(sys.argv[1], 'r', encoding='utf-8').read(), sys.argv[1], 'exec')", path], { encoding: "utf8" });
  checks.push({
    item,
    status: result.status === 0 ? "pass" : "fail",
    detail: result.status === 0 ? `${rel} Python 语法有效` : `${rel} Python 语法错误: ${firstErrorLine(result.stderr)}`
  });
}

function checkGitHubIssueAssets(projectRoot: string, checks: RecordedCheck[]): void {
  const enabled = [".github/workflows/issue-lint.yml", ".github/scripts/issue_depends_on.py", ".github/ISSUE_TEMPLATE/dayu-harness-issue.md"].some((rel) => existsSync(join(projectRoot, rel)));
  if (!enabled) {
    checks.push({ item: "repo-workflow/issue-lint", status: "skip", detail: "issue-lint 工作流未部署（按可选能力处理）" });
    checks.push({ item: "repo-template/issue", status: "skip", detail: "Issue 模板未部署（按可选能力处理）" });
    checks.push({ item: "repo-script/issue_depends_on.py", status: "skip", detail: "issue 依赖检查脚本未部署（按可选能力处理）" });
    return;
  }
  checkWorkflowFile(projectRoot, checks, "repo-workflow/issue-lint", ".github/workflows/issue-lint.yml", true);
  checkRequiredFile(projectRoot, checks, "repo-template/issue", ".github/ISSUE_TEMPLATE/dayu-harness-issue.md");
  checkPythonScript(projectRoot, checks, "repo-script/issue_depends_on.py", ".github/scripts/issue_depends_on.py", true);
}

function checkGitHubPrAssets(projectRoot: string, checks: RecordedCheck[]): void {
  const enabled = [".github/workflows/pr-lint.yml", ".github/scripts/pr_body_structure.py", ".github/pull_request_template.md"].some((rel) => existsSync(join(projectRoot, rel)));
  if (!enabled) {
    checks.push({ item: "repo-workflow/pr-lint", status: "skip", detail: "pr-lint 工作流未部署（按可选能力处理）" });
    checks.push({ item: "repo-template/pull-request", status: "skip", detail: "PR 模板未部署（按可选能力处理）" });
    checks.push({ item: "repo-script/pr-body-structure.py", status: "skip", detail: "PR body 结构检查脚本未部署（按可选能力处理）" });
    return;
  }
  checkWorkflowFile(projectRoot, checks, "repo-workflow/pr-lint", ".github/workflows/pr-lint.yml", true);
  checkRequiredFile(projectRoot, checks, "repo-template/pull-request", ".github/pull_request_template.md");
  checkPythonScript(projectRoot, checks, "repo-script/pr-body-structure.py", ".github/scripts/pr_body_structure.py", true);
}

function checkPullRequestSettings(projectRoot: string, checks: RecordedCheck[], rel: string): void {
  const path = join(projectRoot, rel);
  if (!existsSync(path)) {
    checks.push({ item: "repo-config/pull-request-settings-auto", status: "skip", detail: `${rel} 未部署（按可选能力处理）` });
    return;
  }
  try {
    const parsed = JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
    const failures = [
      ["allow_merge_commit", true],
      ["allow_squash_merge", false],
      ["allow_rebase_merge", false],
      ["allow_auto_merge", true],
      ["delete_branch_on_merge", true]
    ].filter(([key, expected]) => parsed[String(key)] !== expected);
    checks.push({
      item: "repo-config/pull-request-settings-auto",
      status: failures.length === 0 ? "pass" : "fail",
      detail:
        failures.length === 0
          ? `${rel} merge-only、自动合并与删除分支设置正确`
          : `${rel} 未满足仓库级自动合并策略：${failures.map(([key, expected]) => `${key}=${expected}`).join(", ")}`
    });
  } catch (error) {
    checks.push({ item: "repo-config/pull-request-settings-auto", status: "fail", detail: `${rel} 配置解析失败：${error instanceof Error ? error.message : String(error)}` });
  }
}

function checkReleaseAssets(projectRoot: string, checks: RecordedCheck[]): void {
  const enabled = [
    ".github/workflows/release-please.yml",
    ".github/scripts/release_please_policy.py",
    ".github/release-please-policy.json",
    "release-please-config.json",
    ".release-please-manifest.json"
  ].some((rel) => existsSync(join(projectRoot, rel)));
  if (!enabled) {
    checks.push({ item: "release/repository-settings-policy", status: "skip", detail: "release-please 策略未部署（按可选能力处理）" });
    checks.push({ item: "release/release-please-config", status: "skip", detail: "release-please 配置未部署（按可选能力处理）" });
    checks.push({ item: "release/release-please-manifest", status: "skip", detail: "release-please manifest 未部署（按可选能力处理）" });
    checks.push({ item: "release/workflow", status: "skip", detail: "release-please 工作流未部署（按可选能力处理）" });
    checks.push({ item: "release/release-please-policy-script", status: "skip", detail: "release-please 策略脚本未部署（按可选能力处理）" });
    checks.push({ item: "release/release-please-policy", status: "skip", detail: "release-please 策略执行校验未部署（按可选能力处理）" });
    return;
  }
  checkJson(projectRoot, checks, "release/repository-settings-policy", ".github/release-please-policy.json", true);
  checkJson(projectRoot, checks, "release/release-please-config", "release-please-config.json", true);
  checkJson(projectRoot, checks, "release/release-please-manifest", ".release-please-manifest.json", true);
  checkReleaseVersionSync(projectRoot, checks);
  checkWorkflowFile(projectRoot, checks, "release/workflow", ".github/workflows/release-please.yml", true);
  checkPythonScript(projectRoot, checks, "release/release-please-policy-script", ".github/scripts/release_please_policy.py", true);
  const script = join(projectRoot, ".github/scripts/release_please_policy.py");
  const policy = join(projectRoot, ".github/release-please-policy.json");
  if (existsSync(script) && existsSync(policy) && commandOk("python3", ["--version"])) {
    const result = spawnSync("python3", [script, policy, projectRoot], { cwd: projectRoot, encoding: "utf8", env: { ...process.env, PYTHONDONTWRITEBYTECODE: "1" } });
    checks.push({
      item: "release/release-please-policy",
      status: result.status === 0 ? "pass" : "fail",
      detail: result.status === 0 ? "release-please 策略校验通过" : `release-please 策略校验失败: ${firstErrorLine(result.stderr || result.stdout)}`
    });
  }
}

function checkTddAssets(projectRoot: string, checks: RecordedCheck[]): void {
  const enabled = [".github/dayu-harness/pr-tdd-policy.json", ".github/scripts/pr_tdd_check.py"].some((rel) => existsSync(join(projectRoot, rel)));
  if (!enabled) {
    checks.push({ item: "quality/pr-tdd-policy", status: "skip", detail: "TDD 策略未部署（按可选能力处理）" });
    checks.push({ item: "quality/pr-tdd-check-script", status: "skip", detail: "TDD 检查脚本未部署（按可选能力处理）" });
    return;
  }
  checkJson(projectRoot, checks, "quality/pr-tdd-policy", ".github/dayu-harness/pr-tdd-policy.json", true);
  checkPythonScript(projectRoot, checks, "quality/pr-tdd-check-script", ".github/scripts/pr_tdd_check.py", true);
}

function checkRequiredFile(projectRoot: string, checks: RecordedCheck[], item: string, rel: string): void {
  checks.push({ item, status: existsSync(join(projectRoot, rel)) ? "pass" : "fail", detail: existsSync(join(projectRoot, rel)) ? `${rel} 已部署` : `${rel} 缺失（功能可能未正确部署）` });
}

function checkReleaseVersionSync(projectRoot: string, checks: RecordedCheck[]): void {
  const values = [
    ["package.json", readPackageVersion(projectRoot)],
    ["package-lock.json", readPackageLockVersion(projectRoot)],
    ["VERSION", readFirstLine(join(projectRoot, "VERSION"))],
    ["CHANGELOG.md", readChangelogVersion(projectRoot)],
    [".release-please-manifest.json", readJsonValue(join(projectRoot, ".release-please-manifest.json"), ".")]
  ];
  const missing = values.filter(([, value]) => !value).map(([name]) => name);
  const present = values.filter(([, value]) => value);
  const expected = present[0]?.[1] ?? "";
  const mismatches = present.filter(([, value]) => value !== expected).map(([name, value]) => `${name}=${value}`);
  checks.push({
    item: "release/version-sync",
    status: missing.length === 0 && mismatches.length === 0 ? "pass" : "fail",
    detail:
      missing.length === 0 && mismatches.length === 0
        ? `package.json、package-lock.json、VERSION、release manifest 与 CHANGELOG 起始版本一致：${expected}`
        : `发布版本源未对齐。缺失：${missing.join(", ") || "无"}；不一致：${mismatches.join(", ") || "无"}。`
  });
}

function commandOk(command: string, args: readonly string[]): boolean {
  try {
    const result = spawnSync(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    return result.status === 0;
  } catch {
    return false;
  }
}

function firstErrorLine(text: string | Buffer | undefined): string {
  return String(text ?? "")
    .split(/\r?\n/)
    .find((line) => line.trim())?.trim() ?? "未知";
}

function record(
  checks: RecordedCheck[],
  check: string,
  passed: boolean,
  passDetail: string,
  failDetail: string,
  failStatus: "fail" | "warn" = "fail"
): void {
  checks.push({ check, status: passed ? "pass" : failStatus, detail: passed ? passDetail : failDetail });
}

function safeReadDir(path: string): string[] {
  try {
    return readdirSync(path);
  } catch {
    return [];
  }
}

function readText(path: string): string {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return "";
  }
}

function isExecutable(path: string): boolean {
  try {
    return (statSync(path).mode & 0o111) !== 0;
  } catch {
    return false;
  }
}

function readPackageVersion(projectRoot: string): string {
  return readJsonValue(join(projectRoot, "package.json"), "version");
}

function readPackageLockVersion(projectRoot: string): string {
  const path = join(projectRoot, "package-lock.json");
  if (!existsSync(path)) return "";
  try {
    const parsed = JSON.parse(readFileSync(path, "utf8")) as { version?: string; packages?: Record<string, { version?: string }> };
    return parsed.packages?.[""]?.version ?? parsed.version ?? "";
  } catch {
    return "";
  }
}

function readJsonValue(path: string, key: string): string {
  if (!existsSync(path)) return "";
  try {
    const parsed = JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
    const value = parsed[key];
    return typeof value === "string" ? value : "";
  } catch {
    return "";
  }
}

function readFirstLine(path: string): string {
  return readText(path).split(/\r?\n/)[0]?.trim() ?? "";
}

function readChangelogVersion(projectRoot: string): string {
  const changelog = readText(join(projectRoot, "CHANGELOG.md"));
  for (const line of changelog.split(/\r?\n/)) {
    const match = line.match(/^##\s+(?:\[?v?)?([0-9]+\.[0-9]+\.[0-9][0-9A-Za-z.+-]*)/);
    if (match?.[1]) return match[1];
  }
  return "";
}

function findAgentsFiles(projectRoot: string): string[] {
  const files: string[] = [];
  if (existsSync(join(projectRoot, "AGENTS.md"))) files.push("AGENTS.md");
  walk(join(projectRoot, "docs"), (path) => {
    if (basename(path) === "AGENTS.md") files.push(toPosix(relative(projectRoot, path)));
  });
  return files;
}

function walk(root: string, visit: (path: string) => void): void {
  if (!existsSync(root)) return;
  for (const entry of safeReadDir(root)) {
    const path = join(root, entry);
    try {
      const stat = statSync(path);
      if (stat.isDirectory()) walk(path, visit);
      else if (stat.isFile()) visit(path);
    } catch {
      continue;
    }
  }
}

function extractMarkdownLinks(file: string): Array<{ line: number; target: string; raw: string }> {
  return readText(file)
    .split(/\r?\n/)
    .flatMap((raw, index) => {
      const links: Array<{ line: number; target: string; raw: string }> = [];
      const regex = /\[[^\]]+\]\(([^)]*)\)/g;
      let match: RegExpExecArray | null;
      while ((match = regex.exec(raw))) {
        links.push({ line: index + 1, target: match[1].trim(), raw });
      }
      return links;
    });
}

function isExternalLink(path: string): boolean {
  return /^(https?:|mailto:|#)/.test(path);
}

function resolveLink(projectRoot: string, baseDir: string, target: string): string {
  const withoutFragment = target.split("#")[0];
  if (!withoutFragment) return "";
  const clean = withoutFragment.replace(/^\//, "");
  if (existsSync(join(projectRoot, clean))) return toPosix(clean);
  const combined = baseDir === "." ? clean : join(baseDir, clean);
  const absolute = resolve(projectRoot, combined);
  if (!inside(projectRoot, absolute)) return "";
  return toPosix(relative(projectRoot, absolute));
}

function inside(root: string, path: string): boolean {
  const rel = relative(root, path);
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
}

function extractOptionalCapability(line: string): string {
  return line.replaceAll("`", "").match(/(?:可选|Optional)[：:]\s*([A-Za-z0-9._-]+)/)?.[1] ?? "";
}

function indexCountIssues(projectRoot: string, agentsFiles: readonly string[]): string[] {
  const issues: string[] = [];
  for (const agentsFile of agentsFiles) {
    const text = readText(join(projectRoot, agentsFile));
    const claims = text.match(/[0-9]+\s*(?:个|篇|项|条|items|documents|docs|files|entries)/g) ?? [];
    if (claims.length === 0) continue;
    const actual = directoryIndexLinkCount(text);
    for (const claim of claims) {
      const claimed = Number(claim.match(/[0-9]+/)?.[0] ?? 0);
      if (claimed !== actual) {
        issues.push(`${agentsFile} 声明了 '${claim}'，但目录索引实际找到 ${actual} 个列表项链接`);
      }
    }
  }
  return issues;
}

function directoryIndexLinkCount(text: string): number {
  const lines = text.split(/\r?\n/);
  const start = lines.findIndex((line) => /^\s*#{1,6}\s*(目录索引|Directory Index)\s*$/.test(line));
  const scoped = start >= 0 ? lines.slice(start + 1) : lines;
  let count = 0;
  for (const line of scoped) {
    if (start >= 0 && /^\s*#{1,6}\s+/.test(line)) break;
    if (/^\s*[-*]\s+\[[^\]]+\]\([^)]+\)/.test(line)) count += 1;
  }
  return count;
}

function orphanDocIssues(projectRoot: string, referenced: ReadonlySet<string>): string[] {
  const issues: string[] = [];
  walk(join(projectRoot, "docs"), (path) => {
    if (!path.endsWith(".md")) return;
    const rel = toPosix(relative(projectRoot, path));
    const dir = toPosix(dirname(rel));
    if (!referenced.has(rel) && !referenced.has(dir)) issues.push(rel);
  });
  return issues;
}

function referencedScriptIssues(projectRoot: string, referenced: ReadonlySet<string>): string[] {
  const issues: string[] = [];
  for (const ref of referenced) {
    if (!/\.(mjs|cjs|js|ts|json|ya?ml)$/.test(ref) && !ref.startsWith(".husky/")) continue;
    const path = join(projectRoot, ref);
    if (!existsSync(path)) {
      issues.push(`${ref} (文件不存在)`);
    } else if ((ref.endsWith(".mjs") || ref.startsWith(".husky/")) && !isExecutable(path)) {
      issues.push(`${ref} (不可执行)`);
    }
  }
  return issues;
}

function usage(): string {
  return [
    "用法:",
    "  diff-helper.mjs diff <file1> <file2>",
    "  diff-helper.mjs describe <file1> <file2>",
    "  diff-helper.mjs check <file>",
    "  diff-helper.mjs merge-plan <existing> <incoming>",
    ""
  ].join("\n");
}

function diffFiles(file1: string, file2: string): string {
  const result = spawnSync("diff", ["-u", file1, file2], { encoding: "utf8" });
  return `${result.stdout ?? ""}${result.stderr ?? ""}`;
}

function countDiff(file1: string, file2: string): { added: number; removed: number } {
  const diff = diffFiles(file1, file2);
  let added = 0;
  let removed = 0;
  for (const line of diff.split(/\r?\n/)) {
    if (line.startsWith("+++") || line.startsWith("---")) continue;
    if (line.startsWith("+")) added += 1;
    if (line.startsWith("-")) removed += 1;
  }
  return { added, removed };
}

function mergePlan(existing: string, incoming: string) {
  const existingExists = existsSync(existing);
  const incomingExists = existsSync(incoming);
  const counts = incomingExists ? countDiff(existingExists ? existing : "/dev/null", incoming) : { added: 0, removed: 0 };
  const manual = incomingExists && isManualMergeRequired(incoming);
  const recommendation = !incomingExists ? "manual_required" : counts.added === 0 && counts.removed === 0 ? "skip" : manual ? "manual_required" : "merge";
  return {
    status: !incomingExists ? "error" : manual && existingExists ? "manual_required" : existingExists ? "conflict" : "clean",
    existing: {
      path: existing,
      exists: existingExists,
      lines: existingExists ? readText(existing).split(/\r?\n/).length : 0
    },
    incoming: {
      path: incoming,
      lines: incomingExists ? readText(incoming).split(/\r?\n/).length : 0
    },
    diff: counts,
    recommendation,
    strategies: recommendation === "manual_required" ? ["replace", "skip"] : ["merge", "replace", "skip"],
    description_nl: !incomingExists
      ? `Incoming file not found: ${incoming}.`
      : existingExists
        ? `检测到已有 ${existing}。建议在应用前人工确认。`
        : `目标项目中暂无 ${incoming}。可安全写入。`
  };
}

function isManualMergeRequired(target: string): boolean {
  return /\.(ya?ml|js|cjs|mjs|json|json5)$/.test(target) || /(^|\/)(package\.json|commitlint\.config\.cjs|eslint\.config\.)/.test(target);
}

function toPosix(path: string): string {
  return path.split("\\").join("/");
}
