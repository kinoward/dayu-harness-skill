import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, join, resolve } from "node:path";

export interface EnvironmentOptions {
  targetRoot?: string;
  mode?: "check" | "apply";
  capabilities?: string;
}

type ItemStatus =
  | "ok"
  | "missing"
  | "needs_install"
  | "needs_initialization"
  | "needs_user_action"
  | "initialized"
  | "configured"
  | "created"
  | "installed"
  | "error";

interface EnvironmentItem {
  kind: string;
  name: string;
  status: ItemStatus;
  required: boolean;
  action: string;
  description_nl: string;
  install_hint?: string;
}

const DEFAULT_CAPABILITIES = [
  "core",
  "git.commit-format",
  "project.gitignore",
  "ai.execution",
  "ai.memory",
  "knowledge.adr",
  "knowledge.troubleshooting",
  "knowledge.research",
  "project.context",
  "knowledge.archive"
];

const NPM_DEPS_BY_CAPABILITY = new Map<string, string[]>([
  ["git.commit-format", ["@commitlint/cli", "@commitlint/config-conventional"]],
  ["quality.node-tooling", ["eslint", "@eslint/js", "prettier", "lint-staged"]]
]);

const HOOK_BACKED_CAPABILITIES = new Set(["git.commit-format", "quality.node-tooling", "github.branch-protection", "release.versioning"]);

export function checkEnvironment(options: EnvironmentOptions = {}) {
  const mode = options.mode ?? "check";
  const targetRoot = resolve(options.targetRoot ?? process.cwd());
  const capabilities = parseCapabilities(options.capabilities);
  const items: EnvironmentItem[] = [];
  let missingTools = 0;
  let initializations = 0;
  let installs = 0;
  let userActions = 0;
  let errors = 0;

  const requiresNode = requiredNpmDependencies(capabilities).length > 0;
  const requiresPython = capabilities.some((capability) => ["github.pr", "github.issue", "github.release-please", "quality.tdd"].includes(capability));
  const requiresPyYaml = capabilities.some((capability) => ["github.pr", "github.issue", "github.release-please"].includes(capability));
  const requiresGh = capabilities.some((capability) => capability.startsWith("github.") || capability === "release.versioning");
  const requiresHookPath = capabilities.some((capability) => HOOK_BACKED_CAPABILITIES.has(capability));

  for (const [tool, required] of [
    ["git", true],
    ["node", requiresNode],
    ["npm", requiresNode],
    ["npx", requiresNode],
    ["python3", requiresPython],
    ["gh", requiresGh]
  ] as const) {
    if (!required) continue;
    if (commandOk(tool, ["--version"])) {
      items.push({ kind: "tool", name: tool, status: "ok", required: true, action: "none", description_nl: `${tool} 已可用。` });
    } else {
      missingTools += 1;
      items.push({
        kind: "tool",
        name: tool,
        status: "missing",
        required: true,
        action: "install",
        description_nl: `${tool} 缺失，不能继续部署。`,
        install_hint: installHint(tool)
      });
    }
  }

  if (requiresPyYaml && commandOk("python3", ["--version"])) {
    if (commandOk("python3", ["-c", "import yaml"])) {
      items.push({ kind: "python_module", name: "yaml", status: "ok", required: true, action: "none", description_nl: "PyYAML 已可用。" });
    } else {
      missingTools += 1;
      items.push({
        kind: "python_module",
        name: "yaml",
        status: "missing",
        required: true,
        action: "python3 -m pip install PyYAML",
        description_nl: "GitHub workflow YAML 校验需要 PyYAML。",
        install_hint: "安装 Python 包：python3 -m pip install PyYAML。"
      });
    }
  }

  if (missingTools === 0) {
    const gitResult = ensureGitProject(targetRoot, mode, items);
    initializations += gitResult.initializations;
    errors += gitResult.errors;

    if (requiresHookPath && existsSync(join(targetRoot, ".git"))) {
      const hookResult = ensureHooksPath(targetRoot, mode, items);
      initializations += hookResult.initializations;
      userActions += hookResult.userActions;
      errors += hookResult.errors;
    }

    if (requiresNode) {
      const nodeResult = ensureNodeProject(targetRoot, mode, requiredNpmDependencies(capabilities), items);
      initializations += nodeResult.initializations;
      installs += nodeResult.installs;
      errors += nodeResult.errors;
    }

    if (requiresGh) {
      if (commandOk("gh", ["auth", "status"])) {
        items.push({ kind: "auth", name: "gh", status: "ok", required: true, action: "none", description_nl: "GitHub CLI 已登录。" });
      } else {
        userActions += 1;
        items.push({ kind: "auth", name: "gh", status: "needs_user_action", required: true, action: "gh auth login", description_nl: "GitHub CLI 尚未登录，启用 GitHub 能力前必须执行 gh auth login。" });
      }
    }

    ensureBaselineFile(targetRoot, "README.md", `# ${basename(targetRoot)}\n\nProject initialized with Dayu Harness governance.\n`, mode, items);
    ensureBaselineFile(targetRoot, "VERSION", `${projectVersion(targetRoot)}\n`, mode, items);
    ensureBaselineFile(targetRoot, "CHANGELOG.md", `# Changelog\n\n## ${projectVersion(targetRoot)}\n\n- Initial project baseline.\n`, mode, items);
    initializations += items.filter((item) => item.status === "created" && item.kind === "project_file").length;
  }

  const status =
    errors > 0
      ? "error"
      : userActions > 0
        ? "needs_user_action"
        : missingTools > 0
          ? "needs_install"
          : mode === "check" && initializations > 0
            ? "needs_initialization"
            : mode === "check" && installs > 0
              ? "needs_install"
              : "ok";
  const description =
    status === "ok"
      ? "环境依赖完整。"
      : status === "needs_install"
        ? "环境工具已具备，但目标项目缺少必需依赖；apply 阶段会执行列出的安装命令。"
        : status === "needs_initialization"
          ? "环境工具已具备，但目标项目需要初始化；apply 阶段会执行列出的命令。"
          : status === "needs_user_action"
            ? "存在必须由用户确认或登录的环境事项。"
            : "环境准备执行失败，必须修复后才能部署。";

  return {
    mode,
    target: targetRoot,
    targetRoot,
    status,
    default_branch: currentBranch(targetRoot) || "main",
    project_baseline: { version: projectVersion(targetRoot) },
    summary: description,
    items,
    missing_tools: missingTools,
    initializations,
    installs,
    user_actions: userActions,
    errors,
    description_nl: description
  };
}

function parseCapabilities(raw?: string): string[] {
  if (!raw) return DEFAULT_CAPABILITIES;
  return raw
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function requiredNpmDependencies(capabilities: readonly string[]): string[] {
  return [...new Set(capabilities.flatMap((capability) => NPM_DEPS_BY_CAPABILITY.get(capability) ?? []))];
}

function commandOk(command: string, args: readonly string[]): boolean {
  try {
    execFileSync(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    return true;
  } catch {
    return false;
  }
}

function ensureGitProject(
  targetRoot: string,
  mode: "check" | "apply",
  items: EnvironmentItem[]
): { initializations: number; errors: number } {
  if (existsSync(join(targetRoot, ".git"))) {
    items.push({ kind: "project", name: "git", status: "ok", required: true, action: "none", description_nl: `目标目录已是 Git 项目，将保留当前默认分支 ${currentBranch(targetRoot) || "main"}。` });
    return { initializations: 0, errors: 0 };
  }
  if (mode === "apply") {
    try {
      execFileSync("git", ["-C", targetRoot, "init", "-b", "main"], { stdio: ["ignore", "pipe", "pipe"] });
      items.push({ kind: "project", name: "git", status: "initialized", required: true, action: "git init -b main", description_nl: "目标目录不是 Git 项目，已初始化 Git，并使用 main 作为默认分支。" });
      return { initializations: 1, errors: 0 };
    } catch (error) {
      items.push({ kind: "project", name: "git", status: "error", required: true, action: "git init -b main", description_nl: `Git 初始化失败：${message(error)}` });
      return { initializations: 0, errors: 1 };
    }
  }
  items.push({ kind: "project", name: "git", status: "needs_initialization", required: true, action: "git init -b main", description_nl: "目标目录不是 Git 项目，apply 阶段会使用 main 初始化默认分支。" });
  return { initializations: 1, errors: 0 };
}

function ensureHooksPath(
  targetRoot: string,
  mode: "check" | "apply",
  items: EnvironmentItem[]
): { initializations: number; userActions: number; errors: number } {
  const hooksPath = gitConfigValue(targetRoot, "core.hooksPath");
  if (normalizeHooksPath(hooksPath) === ".husky") {
    items.push({ kind: "git_config", name: "core.hooksPath", status: "ok", required: true, action: "none", description_nl: "Git hooksPath 已指向 .husky。" });
    return { initializations: 0, userActions: 0, errors: 0 };
  }
  if (hooksPath) {
    items.push({ kind: "git_config", name: "core.hooksPath", status: "needs_user_action", required: true, action: "manual_confirm", description_nl: `Git hooksPath 当前为 ${hooksPath}。不能自动覆盖已有 hooksPath，必须由用户确认迁移到 .husky 或手动合并。` });
    return { initializations: 0, userActions: 1, errors: 0 };
  }
  if (mode === "apply") {
    try {
      execFileSync("git", ["-C", targetRoot, "config", "core.hooksPath", ".husky"], { stdio: ["ignore", "pipe", "pipe"] });
      items.push({ kind: "git_config", name: "core.hooksPath", status: "configured", required: true, action: "git config core.hooksPath .husky", description_nl: "已配置 Git 使用 .husky 目录执行 hooks。" });
      return { initializations: 1, userActions: 0, errors: 0 };
    } catch (error) {
      items.push({ kind: "git_config", name: "core.hooksPath", status: "error", required: true, action: "git config core.hooksPath .husky", description_nl: `配置 Git hooksPath 失败：${message(error)}` });
      return { initializations: 0, userActions: 0, errors: 1 };
    }
  }
  items.push({ kind: "git_config", name: "core.hooksPath", status: "needs_initialization", required: true, action: "git config core.hooksPath .husky", description_nl: "Git hooksPath 未配置，部署前必须指向 .husky。" });
  return { initializations: 1, userActions: 0, errors: 0 };
}

function ensureNodeProject(
  targetRoot: string,
  mode: "check" | "apply",
  dependencies: readonly string[],
  items: EnvironmentItem[]
): { initializations: number; installs: number; errors: number } {
  let initializations = 0;
  let installs = 0;
  let errors = 0;

  if (!existsSync(join(targetRoot, "package.json"))) {
    if (mode === "apply") {
      try {
        execFileSync("npm", ["init", "-y"], { cwd: targetRoot, stdio: ["ignore", "pipe", "pipe"] });
        syncPackageVersion(targetRoot, projectVersion(targetRoot));
        initializations += 1;
        items.push({ kind: "project", name: "node", status: "initialized", required: true, action: "npm init -y", description_nl: "治理工具链需要 package.json，已执行 npm init -y；这不表示目标项目必须是 Node.js 应用。" });
      } catch (error) {
        errors += 1;
        items.push({ kind: "project", name: "node", status: "error", required: true, action: "npm init -y", description_nl: `npm init 失败：${message(error)}` });
      }
    } else {
      initializations += 1;
      items.push({ kind: "project", name: "node", status: "needs_initialization", required: true, action: "npm init -y", description_nl: "治理工具链需要 package.json，部署前需执行 npm init -y；这不要求目标项目本身是 Node.js 应用。" });
    }
  } else {
    items.push({ kind: "project", name: "node", status: "ok", required: true, action: "none", description_nl: "package.json 已存在。" });
  }

  if (!existsSync(join(targetRoot, "package.json"))) return { initializations, installs, errors };

  const missing = missingPackageDependencies(targetRoot, dependencies);
  if (missing.length === 0) {
    items.push({ kind: "npm_dependencies", name: "devDependencies", status: "ok", required: true, action: "none", description_nl: "必需 package.json devDependencies 已存在。" });
  } else if (mode === "apply") {
    try {
      execFileSync("npm", ["install", "--save-dev", ...missing], { cwd: targetRoot, stdio: ["ignore", "pipe", "pipe"] });
      syncPackageVersion(targetRoot, projectVersion(targetRoot));
      syncPackageLockVersion(targetRoot, projectVersion(targetRoot));
      installs += 1;
      items.push({ kind: "npm_dependencies", name: "devDependencies", status: "installed", required: true, action: `npm install --save-dev ${missing.join(" ")}`, description_nl: `已安装必需 package.json devDependencies：${missing.join(", ")}。` });
    } catch (error) {
      errors += 1;
      items.push({ kind: "npm_dependencies", name: "devDependencies", status: "error", required: true, action: `npm install --save-dev ${missing.join(" ")}`, description_nl: `安装必需 package.json 依赖失败：${message(error)}` });
    }
  } else {
    installs += 1;
    items.push({ kind: "npm_dependencies", name: "devDependencies", status: "needs_install", required: true, action: `npm install --save-dev ${missing.join(" ")}`, description_nl: `缺少必需 package.json devDependencies：${missing.join(", ")}。` });
  }

  if (!existsSync(join(targetRoot, "package-lock.json"))) {
    if (mode === "apply" && missing.length === 0) {
      try {
        execFileSync("npm", ["install"], { cwd: targetRoot, stdio: ["ignore", "pipe", "pipe"] });
        syncPackageVersion(targetRoot, projectVersion(targetRoot));
        syncPackageLockVersion(targetRoot, projectVersion(targetRoot));
        installs += 1;
        items.push({ kind: "project", name: "package-lock.json", status: "created", required: false, action: "npm install", description_nl: `已通过 npm install 生成 package-lock.json、安装已声明依赖，并同步版本 ${projectVersion(targetRoot)}。` });
      } catch (error) {
        errors += 1;
        items.push({ kind: "project", name: "package-lock.json", status: "error", required: false, action: "npm install", description_nl: `生成 package-lock.json 或安装已声明依赖失败：${message(error)}` });
      }
    } else if (mode === "check") {
      items.push({ kind: "project", name: "package-lock.json", status: "needs_initialization", required: false, action: "npm install", description_nl: "package-lock.json 缺失；apply 阶段安装依赖时会生成或补齐。" });
      initializations += 1;
    }
  } else if (mode === "apply") {
    syncPackageLockVersion(targetRoot, projectVersion(targetRoot));
    items.push({ kind: "project", name: "package-lock.version", status: "configured", required: false, action: "sync package-lock.json version", description_nl: `package-lock.json version 已同步为 ${projectVersion(targetRoot)}。` });
  } else {
    items.push({ kind: "project", name: "package-lock.version", status: "ok", required: false, action: "none", description_nl: `package-lock.json version 使用 ${readPackageLockVersion(targetRoot) || "未设置"}。` });
  }

  return { initializations, installs, errors };
}

function missingPackageDependencies(targetRoot: string, dependencies: readonly string[]): string[] {
  const packageJson = readJsonObject(join(targetRoot, "package.json"));
  const declared = { ...(packageJson.dependencies as Record<string, unknown> | undefined), ...(packageJson.devDependencies as Record<string, unknown> | undefined) };
  return dependencies.filter((dependency) => !(dependency in declared));
}

function ensureBaselineFile(targetRoot: string, rel: string, content: string, mode: "check" | "apply", items: EnvironmentItem[]): void {
  const path = join(targetRoot, rel);
  if (existsSync(path)) {
    items.push({ kind: "project_file", name: rel, status: "ok", required: false, action: "none", description_nl: `${rel} 已存在。` });
    return;
  }
  if (mode === "apply") {
    mkdirSync(targetRoot, { recursive: true });
    writeFileSync(path, content);
    items.push({ kind: "project_file", name: rel, status: "created", required: false, action: `create ${rel}`, description_nl: `已创建 ${rel}。` });
  } else {
    items.push({ kind: "project_file", name: rel, status: "needs_initialization", required: false, action: `create ${rel}`, description_nl: `项目缺少 ${rel}，apply 阶段会创建。` });
  }
}

function projectVersion(targetRoot: string): string {
  const packageJson = readJsonObject(join(targetRoot, "package.json"));
  const packageVersion = typeof packageJson.version === "string" && packageJson.version !== "1.0.0" ? packageJson.version : "";
  return packageVersion || readFirstLine(join(targetRoot, "VERSION")) || readChangelogVersion(targetRoot) || "0.1.0";
}

function syncPackageVersion(targetRoot: string, version: string): void {
  const path = join(targetRoot, "package.json");
  const parsed = readJsonObject(path);
  if (!Object.keys(parsed).length) return;
  parsed.version = version;
  writeJson(path, parsed);
}

function syncPackageLockVersion(targetRoot: string, version: string): void {
  const path = join(targetRoot, "package-lock.json");
  const parsed = readJsonObject(path);
  if (!Object.keys(parsed).length) return;
  parsed.version = version;
  const packages = parsed.packages as Record<string, Record<string, unknown>> | undefined;
  if (packages?.[""]) packages[""].version = version;
  writeJson(path, parsed);
}

function readPackageLockVersion(targetRoot: string): string {
  const parsed = readJsonObject(join(targetRoot, "package-lock.json"));
  const packages = parsed.packages as Record<string, { version?: unknown }> | undefined;
  return typeof packages?.[""]?.version === "string" ? packages[""].version : typeof parsed.version === "string" ? parsed.version : "";
}

function readChangelogVersion(targetRoot: string): string {
  const changelog = readText(join(targetRoot, "CHANGELOG.md"));
  for (const line of changelog.split(/\r?\n/)) {
    const match = line.match(/^##\s+(?:\[?v?)?([0-9]+\.[0-9]+\.[0-9][0-9A-Za-z.+-]*)/);
    if (match?.[1]) return match[1];
  }
  return "";
}

function currentBranch(targetRoot: string): string {
  try {
    const branch = execFileSync("git", ["-C", targetRoot, "symbolic-ref", "--quiet", "--short", "HEAD"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
    return branch === "HEAD" ? "" : branch;
  } catch {
    return "";
  }
}

function gitConfigValue(targetRoot: string, key: string): string {
  try {
    return execFileSync("git", ["-C", targetRoot, "config", "--local", "--get", key], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
  } catch {
    return "";
  }
}

function normalizeHooksPath(value: string): string {
  return value.trim().replace(/\\/g, "/").replace(/\/+$/, "").replace(/^\.\//, "");
}

function readJsonObject(path: string): Record<string, unknown> {
  if (!existsSync(path)) return {};
  try {
    return JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
  } catch {
    return {};
  }
}

function writeJson(path: string, value: unknown): void {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function readText(path: string): string {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return "";
  }
}

function readFirstLine(path: string): string {
  return readText(path).split(/\r?\n/)[0]?.trim() ?? "";
}

function installHint(tool: string): string {
  switch (tool) {
    case "git":
      return "macOS: xcode-select --install 或 brew install git；Ubuntu/Debian: sudo apt-get install git。";
    case "node":
    case "npm":
    case "npx":
      return "安装 Node.js LTS（npm/npx 随 Node.js 提供），例如使用 mise/nvm/brew 或系统包管理器。";
    case "python3":
      return "安装 Python 3。macOS: brew install python；Ubuntu/Debian: sudo apt-get install python3。";
    case "gh":
      return "安装 GitHub CLI 并登录：gh auth login。";
    default:
      return `请使用系统包管理器安装 ${tool}。`;
  }
}

function message(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
