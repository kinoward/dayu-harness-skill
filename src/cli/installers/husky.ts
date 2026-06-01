import { chmodSync, existsSync, lstatSync, mkdirSync, readFileSync, readlinkSync, statSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";

import { CliError } from "../errors.js";
import { writeFileAtomically } from "../filesystem.js";

const HOOK_BY_CAPABILITY: Readonly<Record<string, string>> = {
  "git.commit-format": "commit-msg",
  "quality.node-tooling": "pre-commit",
  "github.branch-protection": "pre-push",
  "release.versioning": "pre-push"
};

const RUNTIME_MARKER = "// dayu-harness hook runtime";

const RUNTIME_BLOCK = `${RUNTIME_MARKER}
const dayuHarnessFs = require("node:fs");
const dayuHarnessChildProcess = require("node:child_process");

function dayuHarnessCommandExists(command) {
  const result = dayuHarnessChildProcess.spawnSync(command, ["--version"], { stdio: "ignore" });
  return !result.error && result.status === 0;
}

function dayuHarnessRun(command, args, options = {}) {
  const result = dayuHarnessChildProcess.spawnSync(command, args, { stdio: "inherit", ...options });
  if (result.error) {
    console.error(result.error.message);
    process.exit(1);
  }
  if (typeof result.status === "number" && result.status !== 0) {
    process.exit(result.status);
  }
}

function dayuHarnessReadPrePushInput() {
  if (globalThis.__DAYU_HARNESS_PRE_PUSH_INPUT__ === undefined) {
    try {
      globalThis.__DAYU_HARNESS_PRE_PUSH_INPUT__ = dayuHarnessFs.readFileSync(0, "utf8");
    } catch {
      globalThis.__DAYU_HARNESS_PRE_PUSH_INPUT__ = "";
    }
  }
  return globalThis.__DAYU_HARNESS_PRE_PUSH_INPUT__;
}
`;

const SNIPPETS: Readonly<Record<string, string>> = {
  "git.commit-format": `
// Conventional Commits format validation.
{
  const commitMessageFile = process.env.COMMIT_MSG_FILE || process.argv[2] || "";
  if (!commitMessageFile) {
    console.error("ERROR: commit message file path is missing.");
    process.exit(2);
  }

  if (dayuHarnessCommandExists("npx") && dayuHarnessFs.existsSync("commitlint.config.cjs")) {
    const version = dayuHarnessChildProcess.spawnSync("npx", ["--no-install", "commitlint", "--version"], { stdio: "ignore" });
    if (!version.error && version.status === 0) {
      const lint = dayuHarnessChildProcess.spawnSync("npx", ["--no-install", "commitlint", "--edit", commitMessageFile], {
        stdio: "inherit"
      });
      if (lint.status !== 0) {
        console.error("");
        console.error("ERROR: commit message does not follow Conventional Commits format.");
        console.error("Format: type(scope): description");
        console.error("Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert");
        process.exit(lint.status || 1);
      }
    } else {
      console.log("SKIP: commitlint package is not installed locally.");
    }
  }
}
`,
  "quality.node-tooling": `
// lint-staged runner for Node.js projects.
{
  if (dayuHarnessCommandExists("npx") && dayuHarnessFs.existsSync(".lintstagedrc.json")) {
    dayuHarnessRun("npx", ["--no-install", "lint-staged"]);
  }
}
`,
  "github.branch-protection": `
// Protect default/main/master branches from destructive pushes.
{
  const input = dayuHarnessReadPrePushInput();
  const protectedBranches = (process.env.DAYU_HARNESS_PROTECTED_BRANCHES || "__DAYU_DEFAULT_BRANCH__ main master")
    .split(/\\s+/)
    .filter(Boolean);

  for (const line of input.split(/\\r?\\n/)) {
    if (!line.trim()) continue;
    const [localRef = "", localSha = "", remoteRef = "", remoteSha = ""] = line.trim().split(/\\s+/);
    const refName = remoteRef.replace(/^refs\\/(heads|tags)\\//, "");
    const protectedMatch = protectedBranches.some((branch) => remoteRef === \`refs/heads/\${branch}\`);
    if (!protectedMatch) continue;

    if (localSha === "0000000000000000000000000000000000000000") {
      console.error(\`ERROR: deleting \${refName} is not allowed.\`);
      console.error("Use repository settings for exceptional branch administration.");
      process.exit(1);
    }

    if (process.env.DAYU_HARNESS_ALLOW_DEFAULT_BRANCH_CREATION === "1" && remoteSha === "0000000000000000000000000000000000000000") {
      continue;
    }

    console.error(\`ERROR: direct push to \${refName} is not allowed.\`);
    console.error("Use a feature branch and pull request workflow.");
    process.exit(1);
  }
}
`,
  "release.versioning": `
// Protect v* release tags from deletion and overwrite.
{
  const input = dayuHarnessReadPrePushInput();
  for (const line of input.split(/\\r?\\n/)) {
    if (!line.trim()) continue;
    const [localRef = "", localSha = "", remoteRef = "", remoteSha = ""] = line.trim().split(/\\s+/);
    const refName = remoteRef.replace(/^refs\\/(heads|tags)\\//, "");
    if (!remoteRef.startsWith("refs/tags/v")) continue;

    if (localSha === "0000000000000000000000000000000000000000") {
      console.error(\`ERROR: deleting release tag \${refName} is not allowed.\`);
      process.exit(1);
    }

    if (remoteSha !== "0000000000000000000000000000000000000000") {
      console.error(\`ERROR: overwriting release tag \${refName} is not allowed.\`);
      console.error("Create a new version tag instead.");
      process.exit(1);
    }
  }
}
`
};

export function huskyHookForCapability(capabilityId: string): string | undefined {
  return HOOK_BY_CAPABILITY[capabilityId];
}

export function huskyMarker(capabilityId: string): string {
  return `// >>> dayu-harness:${capabilityId} >>>`;
}

export function huskyHookPath(targetRoot: string, capabilityId: string): string {
  const hook = huskyHookForCapability(capabilityId);
  return hook ? join(targetRoot, ".husky", hook) : join(targetRoot, ".husky");
}

export function canMergeHuskyHook(path: string): boolean {
  if (!existsSync(path)) {
    return true;
  }

  const content = readFileSync(path, "utf8");
  return content.includes(RUNTIME_MARKER) || content.startsWith("#!/usr/bin/env node") || content.startsWith("#!/usr/bin/node");
}

export function applyHuskyInstaller(input: {
  targetRoot: string;
  capabilityId: string;
  defaultBranch: string;
  strategy: "merge" | "replace" | "skip";
}): void {
  if (input.strategy === "skip") {
    return;
  }

  const hook = huskyHookForCapability(input.capabilityId);
  if (!hook) {
    if (input.capabilityId === "git.hooks") {
      return;
    }
    throw new CliError("unsupported-husky-capability", `unsupported husky capability '${input.capabilityId}'`);
  }

  const snippet = SNIPPETS[input.capabilityId];
  if (!snippet) {
    throw new CliError("missing-husky-snippet", `missing husky snippet for '${input.capabilityId}'`);
  }

  const hookPath = join(input.targetRoot, ".husky", hook);
  mkdirSync(dirname(hookPath), { recursive: true });

  if (input.strategy === "replace" || !existsSync(hookPath)) {
    writeHook(hookPath, renderNewHook(hook, input.capabilityId, snippet, input.defaultBranch), 0o755);
    return;
  }

  if (!canMergeHuskyHook(hookPath)) {
    throw new CliError("unsupported-husky-hook", `existing ${hookPath} is not a Node hook; use --force to replace it`);
  }

  const marker = huskyMarker(input.capabilityId);
  const existing = readFileSync(hookPath, "utf8");
  if (existing.includes(marker)) {
    return;
  }

  const mode = hookMode(hookPath);
  const runtime = existing.includes(RUNTIME_MARKER) ? "" : `\n${RUNTIME_BLOCK}`;
  const next = `${existing.replace(/\s*$/, "\n")}${runtime}\n${renderMarkedSnippet(input.capabilityId, snippet, input.defaultBranch)}`;
  writeHook(hookPath, next, mode);
}

function renderNewHook(hook: string, capabilityId: string, snippet: string, defaultBranch: string): string {
  const commitArg = hook === "commit-msg" ? "\n// Git passes the commit message file path as process.argv[2].\n" : "";
  return `#!/usr/bin/env node
// ${hook} hook managed by dayu-harness snippets.${commitArg}
${RUNTIME_BLOCK}
${renderMarkedSnippet(capabilityId, snippet, defaultBranch)}`;
}

function renderMarkedSnippet(capabilityId: string, snippet: string, defaultBranch: string): string {
  return `${huskyMarker(capabilityId)}
// The following snippet is added by dayu-harness.
// Remove this marked section to revert this capability.
${snippet.replaceAll("__DAYU_DEFAULT_BRANCH__", defaultBranch).trimEnd()}
// <<< dayu-harness:${capabilityId} <<<
`;
}

function hookMode(path: string): number {
  try {
    return statSync(path).mode & 0o777;
  } catch {
    return 0o755;
  }
}

function writeHook(path: string, content: string, mode: number): void {
  const target = hookWriteTarget(path);
  mkdirSync(dirname(target), { recursive: true });
  writeFileAtomically(target, content);
  // Preserve executable hooks even when the previous file mode was too strict.
  const normalizedMode = (mode | 0o111) & 0o777;
  chmodSync(target, normalizedMode);
}

function hookWriteTarget(path: string): string {
  const stat = existsSync(path) ? lstatSync(path) : undefined;
  if (!stat?.isSymbolicLink()) {
    return path;
  }

  const link = readlinkSync(path);
  return isAbsolute(link) ? link : resolve(dirname(path), link);
}
