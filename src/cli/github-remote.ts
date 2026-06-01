import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

export interface GithubRemoteResult {
  status: string;
  repository?: string;
  defaultBranch?: string;
  visibility?: string;
  description: string;
  items: Array<Record<string, unknown>>;
}

export function runGithubRemote(input: {
  targetRoot: string;
  mode: "check" | "apply" | "verify";
  remoteActions: readonly Record<string, unknown>[];
  repository?: string;
  visibility?: "private" | "public";
}): GithubRemoteResult {
  const items: Array<Record<string, unknown>> = [];
  const hasGit = commandOk("git", ["--version"]);
  const hasGh = commandOk("gh", ["--version"]);
  const ghAuthed = hasGh && commandOk("gh", ["auth", "status"]);
  const gitRepo = existsSync(join(input.targetRoot, ".git"));
  const repository = input.repository || process.env.DAYU_HARNESS_GITHUB_REPOSITORY || repositoryFromOrigin(input.targetRoot);
  const defaultBranch = normalizeBranch(process.env.DAYU_HARNESS_DEFAULT_BRANCH || currentBranch(input.targetRoot) || "main");

  if (!hasGit) items.push({ kind: "tool", name: "git", status: "needs_initialization", description_nl: "未安装 git，无法读取远端及进行推送。" });
  if (!hasGh) items.push({ kind: "tool", name: "gh", status: "error", description_nl: "缺少 GitHub CLI（gh），无法读取或管理远端仓库。" });
  else if (ghAuthed) items.push({ kind: "auth", name: "gh", status: "ok", description_nl: "GitHub CLI 已登录。" });
  else items.push({ kind: "auth", name: "gh", status: "needs_user_action", description_nl: "GitHub CLI 未登录，请先执行 gh auth login。" });
  if (!gitRepo) items.push({ kind: "project", name: ".git", status: "needs_initialization", description_nl: "目标目录未初始化为 Git 仓库。" });
  if (repository) items.push({ kind: "repository", name: "repository", status: "ok", description_nl: `使用仓库 ${repository}。` });
  else items.push({ kind: "repository", name: "repository", status: "needs_initialization", description_nl: "未设置仓库且未能从 origin 解析 GitHub 仓库。" });

  if (input.mode === "check") {
    return emit(statusFromItems(items), repository, defaultBranch, input.visibility, items, "远端检查完成，未写入远端配置。");
  }

  if (!hasGit || !hasGh || !ghAuthed || !gitRepo || !repository) {
    return emit(statusFromItems(items), repository, defaultBranch, input.visibility, items, "远端编排前置条件不足。");
  }

  if (input.mode === "apply") {
    ensureOrigin(input.targetRoot, repository, items);
    pushDefaultBranch(input.targetRoot, defaultBranch, items);
    applyRemoteActions(input.targetRoot, repository, input.remoteActions, items);
    return emit(statusFromItems(items), repository, defaultBranch, input.visibility, items, "apply 已执行完成。");
  }

  verifyRemoteActions(input.targetRoot, repository, defaultBranch, input.remoteActions, items);
  return emit(statusFromItems(items), repository, defaultBranch, input.visibility, items, "verify 已执行完成。");
}

function commandOk(command: string, args: readonly string[]): boolean {
  try {
    execFileSync(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    return true;
  } catch {
    return false;
  }
}

function execJson(command: string, args: readonly string[]): unknown {
  const output = execFileSync(command, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  return JSON.parse(output) as unknown;
}

function execText(command: string, args: readonly string[]): string {
  return execFileSync(command, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
}

function repositoryFromOrigin(targetRoot: string): string | undefined {
  try {
    const url = execText("git", ["-C", targetRoot, "remote", "get-url", "origin"]);
    const match = url.match(/github\.com[:/]([A-Za-z0-9._-]+\/[A-Za-z0-9._-]+)(?:\.git)?$/);
    return match?.[1];
  } catch {
    return undefined;
  }
}

function currentBranch(targetRoot: string): string | undefined {
  try {
    return execText("git", ["-C", targetRoot, "symbolic-ref", "--quiet", "--short", "HEAD"]);
  } catch {
    try {
      return execText("git", ["-C", targetRoot, "rev-parse", "--abbrev-ref", "HEAD"]);
    } catch {
      return undefined;
    }
  }
}

function normalizeBranch(branch: string): string {
  if (!branch || branch === "HEAD" || branch === "null") return "main";
  return /^dayu-harness\/init(?:-|$)/.test(branch) ? "main" : branch;
}

function ensureOrigin(targetRoot: string, repository: string, items: Array<Record<string, unknown>>): void {
  if (commandOk("git", ["-C", targetRoot, "remote", "get-url", "origin"])) {
    items.push({ kind: "remote", action: "bind", status: "ok", description_nl: "检测到已存在 origin，已保留现有远端。" });
    return;
  }

  if (!commandOk("gh", ["api", `repos/${repository}`])) {
    try {
      execFileSync("gh", ["repo", "create", repository, "--private", "--source=.", "--remote=origin"], {
        cwd: targetRoot,
        stdio: ["ignore", "pipe", "pipe"]
      });
      items.push({ kind: "remote", action: "create", status: "ok", description_nl: "已创建仓库并设置 origin。" });
      return;
    } catch (error) {
      items.push({ kind: "remote", action: "create", status: "error", description_nl: `gh repo create 执行失败：${message(error)}` });
      return;
    }
  }

  try {
    execFileSync("git", ["-C", targetRoot, "remote", "add", "origin", `https://github.com/${repository}.git`], {
      stdio: ["ignore", "pipe", "pipe"]
    });
    items.push({ kind: "remote", action: "bind", status: "ok", description_nl: "远端仓库已存在，已绑定 origin。" });
  } catch (error) {
    items.push({ kind: "remote", action: "bind", status: "error", description_nl: `绑定 origin 失败：${message(error)}` });
  }
}

function pushDefaultBranch(targetRoot: string, defaultBranch: string, items: Array<Record<string, unknown>>): void {
  try {
    execFileSync("git", ["-C", targetRoot, "push", "-u", "origin", `HEAD:${defaultBranch}`], {
      env: { ...process.env, DAYU_HARNESS_ALLOW_DEFAULT_BRANCH_CREATION: "1" },
      stdio: ["ignore", "pipe", "pipe"]
    });
    items.push({ kind: "remote", action: "push", status: "ok", description_nl: `已执行 git push -u origin ${defaultBranch}。` });
  } catch (error) {
    items.push({ kind: "remote", action: "push", status: "error", description_nl: `git push 失败：${message(error)}` });
  }
}

function applyRemoteActions(targetRoot: string, repository: string, actions: readonly Record<string, unknown>[], items: Array<Record<string, unknown>>): void {
  for (const action of actions) {
    const kind = String(action.kind ?? "");
    if (kind === "repository_settings") {
      applyRepositorySettings(targetRoot, repository, items);
    } else if (kind === "workflow_permissions") {
      applyWorkflowPermissions(repository, items);
    } else if (kind === "ruleset") {
      const name = String(action.name ?? "");
      const file = name === "protect-tags" ? ".github/rulesets/protect-tags.json" : ".github/rulesets/protect-main.json";
      applyRuleset(targetRoot, repository, file, name, items);
    } else if (kind === "secret_check" || kind === "variable_check") {
      items.push({ kind, name: action.name, status: "needs_user_action", description_nl: "该远端项需要用户在 GitHub 中配置。" });
    }
  }
}

function verifyRemoteActions(targetRoot: string, repository: string, defaultBranch: string, actions: readonly Record<string, unknown>[], items: Array<Record<string, unknown>>): void {
  try {
    const repo = execJson("gh", ["api", `repos/${repository}`]) as { default_branch?: string };
    if (repo.default_branch && normalizeBranch(repo.default_branch) === defaultBranch) {
      items.push({ kind: "default_branch", status: "ok", description_nl: `默认分支为 ${defaultBranch}。` });
    } else {
      items.push({ kind: "default_branch", status: "missing", description_nl: `远端默认分支不是 ${defaultBranch}。` });
    }
  } catch (error) {
    items.push({ kind: "repository", status: "error", description_nl: `无法读取仓库对象：${message(error)}` });
  }

  for (const action of actions) {
    const kind = String(action.kind ?? "");
    if (kind === "ruleset") {
      const name = String(action.name ?? "");
      const present = rulesetExists(repository, name);
      items.push({ kind: "ruleset", name, status: present ? "ok" : "missing", description_nl: present ? `ruleset ${name} 已存在。` : `ruleset ${name} 缺失。` });
    } else if (kind === "secret_check" || kind === "variable_check") {
      items.push({ kind, name: action.name, status: "needs_user_action", description_nl: "请在 GitHub 端确认该项已配置。" });
    }
  }
}

function applyRepositorySettings(targetRoot: string, repository: string, items: Array<Record<string, unknown>>): void {
  const settingsPath = join(targetRoot, ".github/repository/pull-request-settings.json");
  if (!existsSync(settingsPath)) return;
  const settings = JSON.parse(readFileSync(settingsPath, "utf8")) as Record<string, unknown>;
  try {
    execFileSync(
      "gh",
      [
        "api",
        "-X",
        "PATCH",
        `repos/${repository}`,
        "-F",
        `allow_merge_commit=${String(settings.allow_merge_commit ?? true)}`,
        "-F",
        `allow_squash_merge=${String(settings.allow_squash_merge ?? false)}`,
        "-F",
        `allow_rebase_merge=${String(settings.allow_rebase_merge ?? false)}`,
        "-F",
        `allow_auto_merge=${String(settings.allow_auto_merge ?? true)}`,
        "-F",
        `delete_branch_on_merge=${String(settings.delete_branch_on_merge ?? true)}`
      ],
      { stdio: ["ignore", "pipe", "pipe"] }
    );
    items.push({ kind: "repository_settings", action: "patch", status: "ok", description_nl: "已同步 GitHub 仓库 PR 设置。" });
  } catch (error) {
    items.push({ kind: "repository_settings", action: "patch", status: "error", description_nl: `GitHub 仓库设置同步失败：${message(error)}` });
  }
}

function applyWorkflowPermissions(repository: string, items: Array<Record<string, unknown>>): void {
  try {
    execFileSync(
      "gh",
      ["api", "-X", "PUT", `repos/${repository}/actions/permissions/workflow`, "-f", "default_workflow_permissions=write", "-F", "can_approve_pull_request_reviews=true"],
      { stdio: ["ignore", "pipe", "pipe"] }
    );
    items.push({ kind: "workflow_permissions", action: "put", status: "ok", description_nl: "已同步 GitHub Actions workflow permissions。" });
  } catch (error) {
    items.push({ kind: "workflow_permissions", action: "put", status: "error", description_nl: `GitHub Actions workflow permissions 同步失败：${message(error)}` });
  }
}

function applyRuleset(targetRoot: string, repository: string, file: string, fallbackName: string, items: Array<Record<string, unknown>>): void {
  const path = join(targetRoot, file);
  if (!existsSync(path)) return;
  const ruleset = JSON.parse(readFileSync(path, "utf8")) as { name?: string };
  const name = ruleset.name || fallbackName;
  const existingId = rulesetId(repository, name);
  const endpoint = existingId ? `repos/${repository}/rulesets/${existingId}` : `repos/${repository}/rulesets`;
  try {
    execFileSync("gh", ["api", "-X", existingId ? "PUT" : "POST", endpoint, "--input", path], { stdio: ["ignore", "pipe", "pipe"] });
    items.push({ kind: "ruleset", name, action: existingId ? "update" : "create", status: "ok", description_nl: `已同步 ruleset：${name}。` });
  } catch (error) {
    items.push({ kind: "ruleset", name, action: existingId ? "update" : "create", status: "error", description_nl: `GitHub Rulesets API 失败：${message(error)}` });
  }
}

function rulesetExists(repository: string, name: string): boolean {
  return Boolean(rulesetId(repository, name));
}

function rulesetId(repository: string, name: string): string | undefined {
  try {
    const rulesets = execJson("gh", ["api", `repos/${repository}/rulesets`]) as Array<{ id?: number; name?: string }>;
    const match = rulesets.find((ruleset) => ruleset.name === name);
    return match?.id ? String(match.id) : undefined;
  } catch {
    return undefined;
  }
}

function emit(
  status: string,
  repository: string | undefined,
  defaultBranch: string,
  visibility: string | undefined,
  items: Array<Record<string, unknown>>,
  description: string
): GithubRemoteResult {
  return {
    status,
    repository,
    defaultBranch,
    visibility,
    items,
    description
  };
}

function statusFromItems(items: readonly Record<string, unknown>[]): string {
  if (items.some((item) => item.status === "error")) return "error";
  if (items.some((item) => item.status === "needs_user_action")) return "needs_user_action";
  if (items.some((item) => item.status === "needs_initialization" || item.status === "missing")) return "needs_initialization";
  return "ok";
}

function message(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}
