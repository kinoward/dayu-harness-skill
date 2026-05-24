import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";

import { resolveDeploymentOrder } from "../architecture/index.js";
import { enabledCapabilityIds, readDayuConfig } from "./config.js";
import { diagnoseDayuProject } from "./diagnose.js";
import { CliError } from "./errors.js";
import { managedPathsFile } from "./journal.js";
import { loadManifestRegistry } from "./manifest-registry.js";
import { DEFAULT_CONFIG_FILE, resolveConfigPath, resolveTargetRoot } from "./paths.js";
import { statusDayuProject } from "./status.js";
import type { FinalizeCheck, FinalizeOptions, FinalizeReport } from "./types.js";
import { validateDayuProject } from "./validate.js";
import type { CapabilityId, ManifestV2 } from "../schemas/index.js";

export function finalizeDayuProject(options: FinalizeOptions = {}): FinalizeReport {
  const targetRoot = options.targetRoot ? resolveTargetRoot(options.targetRoot) : resolveTargetRoot();
  const configPath = options.configPath ? resolve(options.configPath) : resolveConfigPath(targetRoot);
  const skillRoot = options.skillRoot ? resolve(options.skillRoot) : loadManifestRegistry().skillRoot;
  const manifestRegistry = loadManifestRegistry(skillRoot);
  const githubRemote = options.githubRemote ?? "skip";
  const releaseValidation = options.releaseValidation ?? "readiness";
  const config = readDayuConfig(configPath);
  const capabilityIds = new Set(enabledCapabilityIds(config));
  const deploymentOrder = resolveDeploymentOrder(manifestRegistry.manifests, [...capabilityIds] as CapabilityId[]);
  const deployedCapabilityIds = new Set<CapabilityId>(deploymentOrder);
  const remoteActions = collectEnabledRemoteActions(deployedCapabilityIds, manifestRegistry.manifestById);
  const remoteActionsJson = JSON.stringify(remoteActions);
  const hasRemoteActions = remoteActions.length > 0;
  const needsIssuePrE2e = deployedCapabilityIds.has("github.issue") && deployedCapabilityIds.has("github.pr");
  const needsReleaseValidation = deployedCapabilityIds.has("github.release-please");
  const needsRemoteE2e = needsIssuePrE2e || needsReleaseValidation;
  const checks: FinalizeCheck[] = [];

  runLocalChecks(targetRoot, configPath, checks);
  if (checks.some((check) => check.status === "failed")) {
    return finalizeReport({
      targetRoot,
      configPath,
      githubRemote,
      releaseValidation,
      stagedPaths: [],
      checks,
      issuePrE2e: {
        status: "skipped",
        description: "本地验证未通过，已停止提交、远端同步和 E2E。"
      },
      releaseE2e: {
        status: "skipped",
        description: "本地验证未通过，已停止 Release Please 验证。"
      }
    });
  }

  const finalizePaths = collectFinalizePathSet(targetRoot, configPath);
  const unrelatedStagedPaths = stagedFiles(targetRoot).filter((path) => !finalizePaths.has(path));
  if (unrelatedStagedPaths.length > 0) {
    checks.push({
      name: "Git 暂存区边界",
      status: "failed",
      description: `暂存区已有非 Dayu 托管文件，已停止提交：${unrelatedStagedPaths.join(", ")}`
    });
    return finalizeReport({
      targetRoot,
      configPath,
      githubRemote,
      releaseValidation,
      stagedPaths: [],
      checks,
      issuePrE2e: {
        status: "skipped",
        description: "暂存区存在非 Dayu 托管文件，已停止远端同步和 E2E。"
      },
      releaseE2e: {
        status: "skipped",
        description: "暂存区存在非 Dayu 托管文件，已停止 Release Please 验证。"
      }
    });
  }
  checks.push({ name: "Git 暂存区边界", status: "passed", description: "暂存区没有非 Dayu 托管文件。" });

  const stagedPaths = stageFinalizePaths(targetRoot, finalizePaths);
  const commitSha = commitIfNeeded(targetRoot, checks);

  let remote: FinalizeReport["remote"] | undefined;
  let issuePrE2e: FinalizeReport["issuePrE2e"];
  let releaseE2e: FinalizeReport["releaseE2e"];

  if (githubRemote === "apply") {
    remote = applyAndVerifyRemote(targetRoot, skillRoot, remoteActionsJson, remoteActions, checks);
    const remoteReady =
      remote?.applyStatus === "ok" &&
      remote.verifyStatus === "ok" &&
      Boolean(remote.repository) &&
      remote.initializationPullRequestMerged !== false;
    if (needsIssuePrE2e && remoteReady) {
      issuePrE2e = runIssuePrE2e(targetRoot, remote?.repository);
      checks.push({
        name: "GitHub Issue/PR E2E",
        status: issuePrE2e.status === "passed" ? "passed" : "failed",
        description: issuePrE2e.description
      });
    } else if (needsIssuePrE2e) {
      issuePrE2e = {
        status: "skipped",
        description: "GitHub 远端未完成，已暂停 Issue/PR E2E。"
      };
      checks.push({
        name: "GitHub Issue/PR E2E",
        status: "skipped",
        description: issuePrE2e.description
      });
    }
    if (needsReleaseValidation && remoteReady) {
      releaseE2e =
        releaseValidation === "real"
          ? runReleasePleaseRealValidation(targetRoot, remote?.repository)
          : runReleasePleaseReadiness(targetRoot, remote?.repository);
      checks.push({
        name: "Release Please",
        status: releaseE2e.status === "passed" ? "passed" : releaseE2e.status === "skipped" ? "skipped" : "failed",
        description: releaseE2e.description
      });
    } else if (needsReleaseValidation) {
      releaseE2e = {
        status: "skipped",
        description: "GitHub 远端未完成，已暂停 Release Please 验证。"
      };
      checks.push({
        name: "Release Please",
        status: "skipped",
        description: releaseE2e.description
      });
    }
  } else if (hasRemoteActions || needsRemoteE2e) {
    remote = {
      applyStatus: "skipped",
      verifyStatus: "skipped",
      remoteActions,
      applyItems: [],
      verifyItems: []
    };
    checks.push({
      name: "GitHub 远端同步",
      status: "skipped",
      description: hasRemoteActions
        ? `已跳过远端同步，未应用远端动作：${describeRemoteActions(remoteActions)}。`
        : "已跳过远端同步，需远端仓库的 E2E 验证未执行。"
    });
    if (needsIssuePrE2e) {
      issuePrE2e = {
        status: "skipped",
        description: "GitHub 远端未完成，已暂停 Issue/PR E2E。"
      };
    }
    if (needsReleaseValidation) {
      releaseE2e = {
        status: "skipped",
        description: "GitHub 远端未完成，已暂停 Release Please 验证。"
      };
    }
  }

  return finalizeReport({
    targetRoot,
    configPath,
    githubRemote,
    releaseValidation,
    stagedPaths,
    commitSha,
    checks,
    remote,
    issuePrE2e,
    releaseE2e
  });
}

function finalizeReport(input: Omit<FinalizeReport, "command" | "status"> & { status?: FinalizeReport["status"] }): FinalizeReport {
  const failed = input.checks.some((check) => check.status === "failed");
  const remoteCapabilityEnabled = Boolean(input.remote?.remoteActions && input.remote.remoteActions.length > 0);
  const remoteAttempted = Boolean(input.remote);
  const remoteCheckNames = new Set([
    "GitHub 远端同步",
    "GitHub 远端校验",
    "初始化 PR 后远端校验"
  ]);
  const remoteCheckSkipped = input.checks.some((check) => remoteCheckNames.has(check.name) && check.status === "skipped");
  const remoteIncomplete =
    remoteAttempted &&
    ((remoteCapabilityEnabled && input.githubRemote === "skip") ||
      ["needs_user_action", "needs_initialization", "missing", "partial", "skipped"].includes(input.remote?.applyStatus ?? "") ||
      ["needs_user_action", "needs_initialization", "missing", "partial", "skipped"].includes(input.remote?.verifyStatus ?? ""));
  const enabledE2eSkipped = input.issuePrE2e?.status === "skipped" || input.releaseE2e?.status === "skipped";
  const partial = !failed && (remoteCheckSkipped || remoteIncomplete || enabledE2eSkipped);
  return {
    command: "finalize",
    ...input,
    status: input.status ?? (failed ? "failed" : partial ? "partial" : "completed")
  };
}

function collectEnabledRemoteActions(
  enabledCapabilityIds: ReadonlySet<CapabilityId>,
  manifestById: ReadonlyMap<string, ManifestV2>
): ReadonlyArray<Record<string, unknown>> {
  const actions: Record<string, unknown>[] = [];
  const seen = new Set<string>();

  for (const manifest of manifestById.values()) {
    if (!enabledCapabilityIds.has(manifest.id) || !manifest.remote_actions) {
      continue;
    }

    for (const action of manifest.remote_actions) {
      const normalizedAction = action as Record<string, unknown>;
      const key = JSON.stringify(normalizedAction);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      actions.push(normalizedAction);
    }
  }
  return actions;
}

function describeRemoteActions(actions: ReadonlyArray<Record<string, unknown>>): string {
  if (actions.length === 0) {
    return "（无）";
  }
  return actions
    .map((action) => {
      const kind = typeof action.kind === "string" ? action.kind : "unknown";
      const name = typeof action.name === "string" ? action.name : "";
      return name ? `${kind}(${name})` : kind;
    })
    .join("、");
}

function runLocalChecks(targetRoot: string, configPath: string, checks: FinalizeCheck[]): void {
  const validate = validateDayuProject({ targetRoot, configPath });
  checks.push({
    name: "dayu-harness validate",
    status: validate.status === "valid" ? "passed" : "failed",
    description: validate.status === "valid" ? "检查通过。" : validate.issues.join("; ")
  });
  const diagnose = diagnoseDayuProject({ targetRoot, configPath });
  checks.push({
    name: "dayu-harness diagnose",
    status: diagnose.status === "healthy" ? "passed" : "failed",
    description: diagnose.status === "healthy" ? "检查通过。" : "治理文件存在缺失、漂移或冲突。"
  });
  const status = statusDayuProject({ targetRoot, configPath });
  checks.push({
    name: "dayu-harness status",
    status: status.status === "healthy" ? "passed" : "failed",
    description: status.status === "healthy" ? "检查通过。" : "治理能力未全部健康。"
  });

  for (const script of ["validate.sh", "audit.sh", "check-consistency.sh"]) {
    const scriptPath = join(targetRoot, "docs/harness/sensors/scripts", script);
    if (!existsSync(scriptPath)) {
      checks.push({
        name: script,
        status: "skipped",
        description: "目标项目尚未部署对应检查脚本。"
      });
      continue;
    }
    runCommandCheck(script, "bash", [scriptPath, "--json", targetRoot], checks);
  }
}

function runCommandCheck(name: string, command: string, args: string[], checks: FinalizeCheck[]): void {
  try {
    execFileSync(command, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    checks.push({ name, status: "passed", description: "检查通过。" });
  } catch (error) {
    checks.push({
      name,
      status: "failed",
      description: error instanceof Error ? error.message : String(error)
    });
  }
}

function stageFinalizePaths(targetRoot: string, paths: ReadonlySet<string>): string[] {
  ensureGitRepository(targetRoot);
  const staged = [...paths].sort();
  if (staged.length > 0) {
    execFileSync("git", ["-C", targetRoot, "add", "-A", "--", ...staged], { stdio: ["ignore", "pipe", "pipe"] });
  }
  return stagedFiles(targetRoot);
}

function collectFinalizePathSet(targetRoot: string, configPath: string): Set<string> {
  const managedPath = join(targetRoot, managedPathsFile());
  const paths = new Set<string>();
  addIfPresentOrTracked(paths, targetRoot, configPath);
  addIfPresentOrTracked(paths, targetRoot, managedPath);

  if (existsSync(managedPath)) {
    const parsed = JSON.parse(readFileSync(managedPath, "utf8")) as { managedPaths?: unknown; previousManagedPaths?: unknown };
    if (Array.isArray(parsed.managedPaths)) {
      for (const item of parsed.managedPaths) {
        if (typeof item === "string") {
          addIfPresentOrTracked(paths, targetRoot, join(targetRoot, item));
        }
      }
    }
    if (Array.isArray(parsed.previousManagedPaths)) {
      for (const item of parsed.previousManagedPaths) {
        if (typeof item === "string") {
          addIfTrackedDeletion(paths, targetRoot, item);
        }
      }
    }
  }

  for (const extra of [DEFAULT_CONFIG_FILE, "package.json", "package-lock.json", "VERSION", "CHANGELOG.md"]) {
    addIfPresentOrTracked(paths, targetRoot, join(targetRoot, extra));
  }

  for (const legacyPath of deletedLegacyStatePaths(targetRoot)) {
    paths.add(legacyPath);
  }

  return paths;
}

function addIfPresentOrTracked(paths: Set<string>, targetRoot: string, absolutePath: string): void {
  const rel = relative(targetRoot, absolutePath);
  if (rel && !rel.startsWith("..") && (existsSync(absolutePath) || isTracked(targetRoot, rel))) {
    paths.add(rel);
  }
}

function addIfTrackedDeletion(paths: Set<string>, targetRoot: string, relativePath: string): void {
  if (relativePath && !relativePath.startsWith("..") && !existsSync(join(targetRoot, relativePath)) && isTracked(targetRoot, relativePath)) {
    paths.add(relativePath);
  }
}

function isTracked(targetRoot: string, relativePath: string): boolean {
  try {
    execFileSync("git", ["-C", targetRoot, "ls-files", "--error-unmatch", "--", relativePath], { stdio: ["ignore", "pipe", "pipe"] });
    return true;
  } catch {
    return false;
  }
}

function stagedFiles(targetRoot: string): string[] {
  return execFileSync("git", ["-C", targetRoot, "diff", "--cached", "--name-only"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  })
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .sort();
}

function deletedLegacyStatePaths(targetRoot: string): string[] {
  return execFileSync("git", ["-C", targetRoot, "status", "--porcelain", "--", ".dayu"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  })
    .split(/\r?\n/)
    .filter((line) => line.trim().startsWith("D "))
    .map((line) => line.slice(3).trim())
    .filter(Boolean);
}

function commitIfNeeded(targetRoot: string, checks: FinalizeCheck[]): string | undefined {
  const diff = execFileSync("git", ["-C", targetRoot, "diff", "--cached", "--name-only"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  }).trim();
  if (!diff) {
    checks.push({ name: "Git 初始化提交", status: "skipped", description: "没有需要提交的治理变更。" });
    return undefined;
  }

  execFileSync("git", ["-C", targetRoot, "commit", "-m", "chore: initialize Dayu Harness governance"], {
    stdio: ["ignore", "pipe", "pipe"]
  });
  const sha = execFileSync("git", ["-C", targetRoot, "rev-parse", "--short=12", "HEAD"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  }).trim();
  checks.push({ name: "Git 初始化提交", status: "passed", description: `已创建初始化提交 ${sha}。` });
  return sha;
}

function applyAndVerifyRemote(
  targetRoot: string,
  skillRoot: string,
  remoteActionsJson: string,
  remoteActions: ReadonlyArray<Record<string, unknown>>,
  checks: FinalizeCheck[]
): FinalizeReport["remote"] {
  const scriptPath = join(skillRoot, "scripts/github-remote.sh");
  if (!existsSync(scriptPath)) {
    checks.push({ name: "GitHub 远端同步", status: "failed", description: "缺少 scripts/github-remote.sh。" });
    return { applyStatus: "error" };
  }

  const apply = runRemoteScript(scriptPath, targetRoot, "--apply", remoteActionsJson);
  checks.push({
    name: "GitHub 远端同步",
    status: remoteScriptCheckStatus(apply.status),
    description: apply.description
  });
  let verify = runRemoteScript(scriptPath, targetRoot, "--verify", remoteActionsJson);
  checks.push({
    name: "GitHub 远端校验",
    status: remoteScriptCheckStatus(verify.status),
    description: verify.description
  });

  const initPr = apply.items.find((item) => item.kind === "pull_request" && item.action === "create" && item.status === "ok");
  let initializationPullRequestMerged: boolean | undefined;
  if (initPr) {
    const merged = mergeInitializationPullRequest(String(initPr.number ?? ""), apply.repository);
    initializationPullRequestMerged = merged;
    checks.push({
      name: "初始化 PR 合并",
      status: merged ? "passed" : "failed",
      description: merged ? "初始化 PR 已合并。" : "初始化 PR 未能自动合并。"
    });
    if (merged) {
      syncLocalDefaultBranch(targetRoot, verify.defaultBranch || apply.defaultBranch);
      verify = runRemoteScript(scriptPath, targetRoot, "--verify", remoteActionsJson);
      checks.push({
        name: "初始化 PR 后远端校验",
        status: remoteScriptCheckStatus(verify.status),
        description: verify.description
      });
    }
  }

  return {
    applyStatus: apply.status,
    verifyStatus: verify.status,
    repository: verify.repository || apply.repository,
    initializationPullRequestMerged,
    remoteActions,
    applyItems: apply.items,
    verifyItems: verify.items
  };
}

function remoteScriptCheckStatus(status: string): FinalizeCheck["status"] {
  if (status === "ok") {
    return "passed";
  }
  if (["needs_user_action", "needs_initialization", "missing", "partial"].includes(status)) {
    return "skipped";
  }
  return "failed";
}

interface RemoteScriptResult {
  status: string;
  repository?: string;
  defaultBranch?: string;
  description: string;
  items: Array<Record<string, unknown>>;
}

function runRemoteScript(
  scriptPath: string,
  targetRoot: string,
  mode: "--apply" | "--verify",
  remoteActionsJson: string
): RemoteScriptResult {
  const output = execFileSync("bash", [scriptPath, targetRoot, mode], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    env: {
      ...process.env,
      DAYU_HARNESS_REMOTE_ACTIONS_JSON: remoteActionsJson
    }
  });
  const parsed = JSON.parse(output) as { status?: string; repository?: string; default_branch?: string; description_nl?: string; items?: unknown };
  return {
    status: parsed.status ?? "error",
    repository: parsed.repository,
    defaultBranch: parsed.default_branch,
    description: parsed.description_nl ?? "",
    items: Array.isArray(parsed.items) ? (parsed.items as Array<Record<string, unknown>>) : []
  };
}

function syncLocalDefaultBranch(targetRoot: string, defaultBranch?: string): void {
  const branch = defaultBranch || currentBranchBase(targetRoot);
  execFileSync("git", ["-C", targetRoot, "fetch", "origin", branch], { stdio: ["ignore", "pipe", "pipe"] });
  execFileSync("git", ["-C", targetRoot, "switch", branch], { stdio: ["ignore", "pipe", "pipe"] });
  execFileSync("git", ["-C", targetRoot, "pull", "--ff-only", "origin", branch], { stdio: ["ignore", "pipe", "pipe"] });
}

function mergeInitializationPullRequest(prNumber: string, repository?: string): boolean {
  if (!prNumber || !repository) {
    return false;
  }
  try {
    execFileSync("gh", ["pr", "checks", prNumber, "--repo", repository, "--watch", "--fail-fast"], {
      stdio: ["ignore", "pipe", "pipe"]
    });
    execFileSync("gh", ["pr", "merge", prNumber, "--repo", repository, "--merge", "--delete-branch"], {
      stdio: ["ignore", "pipe", "pipe"]
    });
    return true;
  } catch {
    return false;
  }
}

function runIssuePrE2e(targetRoot: string, repository?: string): NonNullable<FinalizeReport["issuePrE2e"]> {
  if (!repository) {
    return { status: "failed", description: "缺少 GitHub 仓库信息，无法执行 Issue/PR E2E。" };
  }
  const formatter = join(targetRoot, "docs/harness/sensors/scripts/dayu-format.mjs");
  if (!existsSync(formatter)) {
    return { status: "failed", description: "缺少固定格式内容生成器，无法创建合规测试 Issue/PR。" };
  }

  const tmp = join(targetRoot, ".dayu-harness", "tmp", `issue-pr-e2e-${Date.now()}`);
  mkdirSync(tmp, { recursive: true });
  const branch = `dayu-harness/e2e-${Date.now()}`;
  const base = currentBranchBase(targetRoot);
  const startedAt = new Date().toISOString();
  let issueNumber = "";
  let prNumber = "";
  let branchCreated = false;
  let validationError: unknown;
  try {
    const issueBody = execFileSync(process.execPath, [
      formatter,
      "issue-body",
      "--summary",
      "Validate Dayu Harness GitHub Issue and PR governance.",
      "--background",
      "Temporary E2E created by dayu-harness finalize."
    ], { encoding: "utf8" });
    const issueUrl = execFileSync("gh", ["issue", "create", "--repo", repository, "--title", "Dayu Harness finalize E2E", "--body", issueBody], {
      encoding: "utf8"
    }).trim();
    issueNumber = issueUrl.split("/").pop() ?? "";
    waitForWorkflowAfter(repository, "issue-lint.yml", startedAt);
    execFileSync("git", ["-C", targetRoot, "switch", "-c", branch], { stdio: ["ignore", "pipe", "pipe"] });
    branchCreated = true;
    const markerPath = join(targetRoot, ".dayu-harness", `e2e-${Date.now()}.txt`);
    writeFileSync(markerPath, "Dayu Harness finalize E2E marker.\n", "utf8");
    execFileSync("git", ["-C", targetRoot, "add", relative(targetRoot, markerPath)], { stdio: ["ignore", "pipe", "pipe"] });
    execFileSync("git", ["-C", targetRoot, "commit", "-m", "test: dayu harness finalize e2e"], { stdio: ["ignore", "pipe", "pipe"] });
    execFileSync("git", ["-C", targetRoot, "push", "-u", "origin", branch], { stdio: ["ignore", "pipe", "pipe"] });
    const prBodyPath = join(tmp, "pr-body.md");
    const prBody = execFileSync(process.execPath, [
      formatter,
      "pr-body",
      "--summary",
      "Validate Dayu Harness GitHub PR checks.",
      "--implementation",
      "Adds a temporary finalize E2E marker.",
      "--test-command",
      `gh pr checks --repo ${repository}`,
      "--issue",
      issueNumber,
      "--final",
      "yes"
    ], { encoding: "utf8" });
    writeFileSync(prBodyPath, prBody, "utf8");
    const prUrl = execFileSync("gh", [
      "pr",
      "create",
      "--repo",
      repository,
      "--base",
      base,
      "--head",
      branch,
      "--title",
      "Dayu Harness finalize E2E",
      "--body-file",
      prBodyPath
    ], { encoding: "utf8" }).trim();
    prNumber = prUrl.split("/").pop() ?? "";
    execFileSync("gh", ["pr", "checks", prNumber, "--repo", repository, "--watch", "--fail-fast"], { stdio: ["ignore", "pipe", "pipe"] });
  } catch (error) {
    validationError = error;
  }

  const cleanupErrors: string[] = [];
  if (prNumber) {
    collectCleanupError(cleanupErrors, "关闭测试 PR 并删除远端分支", "gh", [
      "pr",
      "close",
      prNumber,
      "--repo",
      repository,
      "--comment",
      "Dayu Harness finalize E2E complete.",
      "--delete-branch"
    ]);
  } else if (branchCreated) {
    collectCleanupError(cleanupErrors, "删除测试远端分支", "git", ["-C", targetRoot, "push", "origin", "--delete", branch]);
  }
  if (issueNumber) {
    collectCleanupError(cleanupErrors, "关闭测试 Issue", "gh", [
      "issue",
      "close",
      issueNumber,
      "--repo",
      repository,
      "--comment",
      "Dayu Harness finalize E2E complete."
    ]);
  }
  collectCleanupError(cleanupErrors, "切回原本分支", "git", ["-C", targetRoot, "switch", base]);
  if (branchCreated) {
    collectCleanupError(cleanupErrors, "删除测试本地分支", "git", ["-C", targetRoot, "branch", "-D", branch]);
  }
  try {
    rmSync(tmp, { recursive: true, force: true });
  } catch (error) {
    cleanupErrors.push(`删除临时目录: ${errorMessage(error)}`);
  }

  const validationDescription = validationError ? errorMessage(validationError) : `测试 Issue #${issueNumber} 和 PR #${prNumber} 已验证。`;
  if (validationError) {
    return {
      status: "failed",
      description: cleanupErrors.length > 0 ? `${validationDescription}；清理也失败：${cleanupErrors.join("；")}` : validationDescription
    };
  }
  if (cleanupErrors.length > 0) {
    return {
      status: "failed",
      description: `${validationDescription} 但清理失败：${cleanupErrors.join("；")}`
    };
  }
  return { status: "passed", description: `测试 Issue #${issueNumber} 和 PR #${prNumber} 已验证并清理。` };
}

function mergeCurrentBranchViaPullRequest(
  targetRoot: string,
  repository: string,
  base: string,
  branch: string,
  details: { title: string; summary: string; implementation: string; testCommand: string }
): void {
  const formatter = join(targetRoot, "docs/harness/sensors/scripts/dayu-format.mjs");
  if (!existsSync(formatter)) {
    throw new CliError("missing-dayu-format", "缺少固定格式内容生成器，无法创建合规验证 PR。");
  }

  const tmp = join(targetRoot, ".dayu-harness", "tmp", `merge-pr-${Date.now()}`);
  mkdirSync(tmp, { recursive: true });
  const startedAt = new Date().toISOString();
  let issueNumber = "";
  let prNumber = "";
  try {
    const issueBody = execFileSync(process.execPath, [
      formatter,
      "issue-body",
      "--summary",
      details.summary,
      "--background",
      "Temporary validation issue created by dayu-harness finalize."
    ], { encoding: "utf8" });
    const issueUrl = execFileSync("gh", ["issue", "create", "--repo", repository, "--title", details.title, "--body", issueBody], {
      encoding: "utf8"
    }).trim();
    issueNumber = issueUrl.split("/").pop() ?? "";
    if (existsSync(join(targetRoot, ".github/workflows/issue-lint.yml"))) {
      waitForWorkflowAfter(repository, "issue-lint.yml", startedAt);
    }

    execFileSync("git", ["-C", targetRoot, "push", "-u", "origin", `HEAD:${branch}`], { stdio: ["ignore", "pipe", "pipe"] });
    const prBodyPath = join(tmp, "pr-body.md");
    const prBody = execFileSync(process.execPath, [
      formatter,
      "pr-body",
      "--summary",
      details.summary,
      "--implementation",
      details.implementation,
      "--test-command",
      details.testCommand,
      "--issue",
      issueNumber,
      "--final",
      "yes"
    ], { encoding: "utf8" });
    writeFileSync(prBodyPath, prBody, "utf8");
    const prUrl = execFileSync("gh", [
      "pr",
      "create",
      "--repo",
      repository,
      "--base",
      base,
      "--head",
      branch,
      "--title",
      details.title,
      "--body-file",
      prBodyPath
    ], { encoding: "utf8" }).trim();
    prNumber = prUrl.split("/").pop() ?? "";
    execFileSync("gh", ["pr", "checks", prNumber, "--repo", repository, "--watch", "--fail-fast"], { stdio: ["ignore", "pipe", "pipe"] });
    execFileSync("gh", ["pr", "merge", prNumber, "--repo", repository, "--merge", "--delete-branch"], {
      stdio: ["ignore", "pipe", "pipe"]
    });
  } catch (error) {
    if (prNumber) {
      bestEffortExec("gh", ["pr", "close", prNumber, "--repo", repository, "--comment", "Dayu Harness finalize validation cleanup.", "--delete-branch"]);
    } else {
      bestEffortExec("git", ["-C", targetRoot, "push", "origin", "--delete", branch]);
    }
    throw error;
  } finally {
    if (issueNumber) {
      bestEffortExec("gh", ["issue", "close", issueNumber, "--repo", repository, "--comment", "Dayu Harness finalize validation complete."]);
    }
    rmSync(tmp, { recursive: true, force: true });
  }
}

function runReleasePleaseReadiness(_targetRoot: string, repository?: string): NonNullable<FinalizeReport["releaseE2e"]> {
  return repository
    ? { status: "skipped", description: "已完成 Release Please 就绪检查，但未执行真实发版验证。" }
    : { status: "failed", description: "缺少 GitHub 仓库信息，无法验证 Release Please。" };
}

function runReleasePleaseRealValidation(targetRoot: string, repository?: string): NonNullable<FinalizeReport["releaseE2e"]> {
  if (!repository) {
    return { status: "failed", description: "缺少 GitHub 仓库信息，无法执行真实发版验证。" };
  }
  const base = currentBranchBase(targetRoot);
  const startedAt = new Date().toISOString();
  const releaseBranch = `dayu-harness/release-e2e-${Date.now()}`;
  const markerRelativePath = `src/dayu-harness-release-e2e-${Date.now()}.ts`;
  const marker = join(targetRoot, markerRelativePath);
  let markerMerged = false;
  let releaseVersion = "";
  let validationError: unknown;
  try {
    syncLocalDefaultBranch(targetRoot, base);
    execFileSync("git", ["-C", targetRoot, "switch", "-c", releaseBranch], { stdio: ["ignore", "pipe", "pipe"] });
    mkdirSync(dirname(marker), { recursive: true });
    writeFileSync(marker, "export const dayuHarnessReleaseValidation = true;\n", "utf8");
    execFileSync("git", ["-C", targetRoot, "add", relative(targetRoot, marker)], { stdio: ["ignore", "pipe", "pipe"] });
    execFileSync("git", ["-C", targetRoot, "commit", "-m", "feat: validate Dayu Harness release automation"], {
      stdio: ["ignore", "pipe", "pipe"]
    });
    const before = readVersion(targetRoot);
    mergeCurrentBranchViaPullRequest(targetRoot, repository, base, releaseBranch, {
      title: "Dayu Harness release validation",
      summary: "Validate Dayu Harness Release Please automation.",
      implementation: "Adds a temporary release validation marker through a PR so protected branches are respected.",
      testCommand: `gh run list --repo ${repository} --workflow release-please.yml --limit 1`
    });
    markerMerged = true;
    syncLocalDefaultBranch(targetRoot, base);
    waitForWorkflowAfter(repository, "release-please.yml", startedAt);
    execFileSync("git", ["-C", targetRoot, "pull", "--ff-only", "origin", base], { stdio: ["ignore", "pipe", "pipe"] });
    const after = readVersion(targetRoot);
    if (!after || after === before) {
      throw new CliError("release-validation-failed", "Release Please did not advance VERSION");
    }
    waitForRelease(repository, `v${after}`, startedAt);
    releaseVersion = after;
  } catch (error) {
    validationError = error;
  }

  const cleanupError = markerMerged ? cleanupReleaseMarker(targetRoot, repository, markerRelativePath, base) : cleanupLocalReleaseMarker(targetRoot, markerRelativePath);
  bestEffortExec("git", ["-C", targetRoot, "switch", base]);
  bestEffortExec("git", ["-C", targetRoot, "branch", "-D", releaseBranch]);

  if (validationError) {
    const cleanupNote = cleanupError ? `；清理也失败：${cleanupError}` : "";
    return { status: "failed", description: `${validationError instanceof Error ? validationError.message : String(validationError)}${cleanupNote}` };
  }
  if (cleanupError) {
    return {
      status: "failed",
      description: `Release Please 已真实发布 v${releaseVersion}，但临时 marker 清理失败：${cleanupError}`
    };
  }
  return { status: "passed", description: `Release Please 已真实发布 v${releaseVersion}，tag/release 保留在目标仓库。` };
}

function cleanupLocalReleaseMarker(targetRoot: string, markerRelativePath: string): string | undefined {
  try {
    const marker = join(targetRoot, markerRelativePath);
    if (existsSync(marker)) {
      unlinkSync(marker);
      bestEffortExec("git", ["-C", targetRoot, "reset", "--", markerRelativePath]);
    }
    return undefined;
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }
}

function cleanupReleaseMarker(targetRoot: string, repository: string, markerRelativePath: string, base: string): string | undefined {
  try {
    syncLocalDefaultBranch(targetRoot, base);
    const marker = join(targetRoot, markerRelativePath);
    if (!existsSync(marker)) {
      return;
    }
    const cleanupBranch = `dayu-harness/release-cleanup-${Date.now()}`;
    execFileSync("git", ["-C", targetRoot, "switch", "-c", cleanupBranch], { stdio: ["ignore", "pipe", "pipe"] });
    unlinkSync(marker);
    execFileSync("git", ["-C", targetRoot, "add", "-A", "--", markerRelativePath], { stdio: ["ignore", "pipe", "pipe"] });
    const hasCleanup = execFileSync("git", ["-C", targetRoot, "diff", "--cached", "--name-only", "--", markerRelativePath], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"]
    }).trim();
    if (!hasCleanup) {
      return;
    }
    execFileSync("git", ["-C", targetRoot, "commit", "-m", "chore: clean Dayu Harness release validation marker"], {
      stdio: ["ignore", "pipe", "pipe"]
    });
    mergeCurrentBranchViaPullRequest(targetRoot, repository, base, cleanupBranch, {
      title: "Clean Dayu Harness release validation marker",
      summary: "Remove the temporary Dayu Harness release validation marker.",
      implementation: "Deletes the marker after the release validation completed.",
      testCommand: `test ! -f ${markerRelativePath}`
    });
    syncLocalDefaultBranch(targetRoot, base);
    bestEffortExec("git", ["-C", targetRoot, "branch", "-D", cleanupBranch]);
    return undefined;
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  } finally {
    bestEffortExec("git", ["-C", targetRoot, "switch", base]);
  }
}

function waitForRelease(repository: string, tag: string, startedAt: string): void {
  const deadline = Date.now() + 15 * 60 * 1000;
  while (Date.now() < deadline) {
    try {
      execFileSync("gh", ["release", "view", tag, "--repo", repository], { stdio: ["ignore", "pipe", "pipe"] });
      return;
    } catch {
      try {
        waitForWorkflowAfter(repository, "release-please.yml", startedAt);
      } catch {
        // The push run may finish before the publish dispatch starts; keep polling the release.
      }
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 15000);
    }
  }
  throw new CliError("release-timeout", `${tag} was not visible on GitHub before timeout`);
}

function waitForWorkflowAfter(repository: string, workflow: string, startedAt: string): void {
  const deadline = Date.now() + 15 * 60 * 1000;
  while (Date.now() < deadline) {
    const output = execFileSync("gh", [
      "run",
      "list",
      "--repo",
      repository,
      "--workflow",
      workflow,
      "--json",
      "databaseId,status,conclusion,createdAt",
      "--limit",
      "1"
    ], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    const [run] = JSON.parse(output) as Array<{ databaseId?: number; status?: string; conclusion?: string; createdAt?: string }>;
    if (run?.createdAt && new Date(run.createdAt).getTime() < new Date(startedAt).getTime()) {
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 15000);
      continue;
    }
    if (run?.status === "completed") {
      if (run.conclusion === "success") {
        return;
      }
      throw new CliError("workflow-failed", `${workflow} concluded ${run.conclusion ?? "unknown"}`);
    }
    if (run?.databaseId) {
      try {
        execFileSync("gh", ["run", "watch", String(run.databaseId), "--repo", repository, "--exit-status"], {
          stdio: ["ignore", "pipe", "pipe"]
        });
        return;
      } catch (error) {
        throw new CliError("workflow-failed", error instanceof Error ? error.message : String(error));
      }
    }
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 15000);
  }
  throw new CliError("workflow-timeout", `${workflow} did not finish in time`);
}

function readVersion(targetRoot: string): string {
  return existsSync(join(targetRoot, "VERSION")) ? readFileSync(join(targetRoot, "VERSION"), "utf8").trim() : "";
}

function currentBranchBase(targetRoot: string): string {
  return execFileSync("git", ["-C", targetRoot, "rev-parse", "--abbrev-ref", "HEAD"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"]
  }).trim();
}

function ensureGitRepository(targetRoot: string): void {
  if (!existsSync(join(targetRoot, ".git"))) {
    throw new CliError("not-a-git-repository", "finalize requires a Git repository");
  }
}

function collectCleanupError(errors: string[], label: string, command: string, args: string[]): void {
  try {
    execFileSync(command, args, { stdio: ["ignore", "pipe", "pipe"] });
  } catch (error) {
    errors.push(`${label}: ${errorMessage(error)}`);
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function bestEffortExec(command: string, args: string[]): void {
  try {
    execFileSync(command, args, { stdio: ["ignore", "pipe", "pipe"] });
  } catch {
    // best-effort cleanup
  }
}
