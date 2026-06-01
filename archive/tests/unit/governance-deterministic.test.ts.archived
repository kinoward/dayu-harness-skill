import assert from "node:assert/strict";
import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import {
  cpSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test, { type TestContext } from "node:test";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));

const assets = {
  dayuFormat: join(repoRoot, "templates/docs/harness/sensors/scripts/dayu-format.mjs"),
  issueDependsOn: join(repoRoot, "assets/github/scripts/issue_depends_on.py"),
  prBodyStructure: join(repoRoot, "assets/github/scripts/pr_body_structure.py"),
  commitMsgHook: join(repoRoot, "assets/husky/snippets/commit-format.sh"),
  branchProtection: join(repoRoot, "assets/husky/snippets/branch-protection.sh"),
  tagProtection: join(repoRoot, "assets/husky/snippets/release-versioning.sh"),
  releasePolicyScript: join(repoRoot, "assets/github/scripts/release_please_policy.py"),
  releasePolicyFile: join(repoRoot, "assets/github/release-please-policy.json"),
  releaseConfigFile: join(repoRoot, "assets/github/release-please-config.json"),
  releaseWorkflow: join(repoRoot, "assets/github/workflows/release-please.yml"),
  prLintWorkflow: join(repoRoot, "assets/github/workflows/pr-lint.yml"),
  prSettings: join(repoRoot, "assets/github/repository/pull-request-settings.json"),
  manifestFile: join(repoRoot, "assets/github/.release-please-manifest.json"),
  rulesetMain: join(repoRoot, "assets/github/rulesets/protect-main.json"),
  rulesetTags: join(repoRoot, "assets/github/rulesets/protect-tags.json")
};

type ExecResult = SpawnSyncReturns<string>;

function mkWorkspace(t: TestContext): string {
  const tmpBase = tmpdir();
  const absoluteTmpBase = tmpBase.startsWith("/") ? tmpBase : join(process.cwd(), tmpBase);
  mkdirSync(absoluteTmpBase, { recursive: true });
  const path = mkdtempSync(join(absoluteTmpBase, "dayu-governance-"));
  t.after(() => rmSync(path, { recursive: true, force: true }));
  return path;
}

function mkTempWorkspace(prefix: string): string {
  const tmpBase = tmpdir();
  const absoluteTmpBase = tmpBase.startsWith("/") ? tmpBase : join(process.cwd(), tmpBase);
  mkdirSync(absoluteTmpBase, { recursive: true });
  return mkdtempSync(join(absoluteTmpBase, prefix));
}

function runCommand(
  command: string,
  args: string[],
  options: Record<string, string | undefined> = {}
): ExecResult {
  const { cwd, ...rest } = options;
  return spawnSync(command, args, {
    encoding: "utf8",
    env: {
      ...process.env,
      ...rest
    },
    ...(cwd ? { cwd } : {})
  }) as ExecResult;
}

function runInputCommand(
  command: string,
  args: string[],
  input: string,
  options: Record<string, string | undefined> = {}
): ExecResult {
  const { cwd, ...rest } = options;
  return spawnSync(command, args, {
    encoding: "utf8",
    cwd: cwd ?? undefined,
    input,
    env: {
      ...process.env,
      ...rest
    }
  }) as ExecResult;
}

function execOutput(result: ExecResult): string {
  return `${result.stdout ?? ""}${result.stderr ?? ""}`;
}

function write(path: string, content: string): void {
  writeFileSync(path, content, "utf8");
}

function json(path: string): unknown {
  return JSON.parse(readFileSync(path, "utf8"));
}

function copyTextFile(src: string, dst: string): void {
  mkdirSync(dirname(dst), { recursive: true });
  cpSync(src, dst);
}

function createPolicyFixture(workspace: string): void {
  mkdirSync(join(workspace, "assets"), { recursive: true });
  mkdirSync(join(workspace, ".github/workflows"), { recursive: true });
  mkdirSync(join(workspace, ".github/repository"), { recursive: true });
  copyTextFile(assets.releasePolicyFile, join(workspace, "release-please-policy.json"));
  copyTextFile(assets.releaseConfigFile, join(workspace, "release-please-config.json"));
  copyTextFile(assets.releaseWorkflow, join(workspace, ".github/workflows/release-please.yml"));
  copyTextFile(assets.prLintWorkflow, join(workspace, ".github/workflows/pr-lint.yml"));
  copyTextFile(assets.prSettings, join(workspace, ".github/repository/pull-request-settings.json"));
  copyTextFile(assets.manifestFile, join(workspace, ".release-please-manifest.json"));
}

function runReleasePolicy(workspace: string, policyFile: string): ExecResult {
  return runCommand("python3", [assets.releasePolicyScript, policyFile, workspace]);
}

function writeFakeNpxBin(workspace: string): string {
  const binDir = join(workspace, "bin");
  mkdirSync(binDir, { recursive: true });
  const npxPath = join(binDir, "npx");
  writeFileSync(
    npxPath,
    `#!/usr/bin/env bash
set -euo pipefail

if [ "$1" = "--no-install" ] && [ "$2" = "commitlint" ]; then
  if [ "$3" = "--version" ]; then
    exit 0
  fi

  if [ "$3" = "--edit" ]; then
    message_file="$4"
    if grep -Eq '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\\([A-Za-z0-9._-]+\\))?: .+' "$message_file"; then
      if grep -q "bad commit" "$message_file" 2>/dev/null; then
        exit 1
      fi
      exit 0
    fi
    exit 1
  fi
fi

exit 0
`,
    "utf8"
  );
  runCommand("chmod", ["+x", npxPath]);
  return binDir;
}

function runCommitMsgHook(workspace: string, messagePath: string, env: Record<string, string> = {}): ExecResult {
  const binDir = writeFakeNpxBin(workspace);
  return runCommand("bash", [assets.commitMsgHook, messagePath], {
    PATH: `${binDir}:${process.env.PATH ?? ""}`,
    cwd: workspace,
    ...env
  });
}

function runPrePushSnippet(workspace: string, snippet: string, record: string, env: Record<string, string> = {}): ExecResult {
  const inputPath = join(workspace, "pre-push-input.txt");
  write(inputPath, `${record}\n`);
  return runCommand("bash", [snippet], {
    DAYU_HARNESS_PRE_PUSH_INPUT: inputPath,
    PATH: `${join(workspace, "bin")}:${process.cwd()}/bin:${process.env.PATH ?? ""}`,
    cwd: workspace,
    ...env
  });
}

function runIssueValidator(workspace: string, body: string): ExecResult {
  const payload = join(workspace, "issue-payload.json");
  write(payload, JSON.stringify({ issue: { body } }));
  return runCommand("python3", [assets.issueDependsOn, payload]);
}

function runPrBodyValidator(workspace: string, body: string, args: string[] = []): ExecResult {
  const commandArgs = [...args];
  return runInputCommand("python3", [assets.prBodyStructure, ...commandArgs], body);
}

function runDayuFormat(args: string[], input?: string): ExecResult {
  if (input) {
    return runInputCommand("node", [assets.dayuFormat, ...args], input);
  }
  return runCommand("node", [assets.dayuFormat, ...args]);
}

function parseRuleset(payload: unknown): { name: string; target: string; conditions: unknown; rules: unknown[] } {
  if (!payload || typeof payload !== "object") {
    throw new Error("ruleset must be object");
  }

  const ruleset = payload as { [key: string]: unknown };
  if (typeof ruleset.name !== "string" || !ruleset.name) {
    throw new Error("ruleset.name must be a non-empty string");
  }
  if (typeof ruleset.target !== "string" || !ruleset.target) {
    throw new Error("ruleset.target must be a non-empty string");
  }
  if (!Array.isArray(ruleset.rules) || ruleset.rules.length === 0) {
    throw new Error("ruleset.rules must be a non-empty array");
  }
  if (!ruleset.conditions || typeof ruleset.conditions !== "object") {
    throw new Error("ruleset.conditions must be an object");
  }

  const conditions = ruleset.conditions as { [key: string]: unknown };
  const refName = conditions.ref_name;
  if (!refName || typeof refName !== "object") {
    throw new Error("ruleset.conditions.ref_name must be an object");
  }

  const refs = refName as { [key: string]: unknown };
  if (!Array.isArray(refs.include) || !Array.isArray(refs.exclude)) {
    throw new Error("ruleset.ref_name.include and ref_name.exclude must be arrays");
  }

  for (const rule of ruleset.rules) {
    if (!rule || typeof rule !== "object" || typeof (rule as { type?: unknown }).type !== "string") {
      throw new Error("each rule must have type string");
    }
  }

  return ruleset as { name: string; target: string; conditions: unknown; rules: unknown[] };
}

const zeroSha = "0000000000000000000000000000000000000000";
const hash1 = "1111111111111111111111111111111111111111";
const hash2 = "2222222222222222222222222222222222222222";

test("dayu-format renderer and validation examples", () => {
  const validCommit = runDayuFormat(["commit-message", "--type", "feat", "--scope", "governance", "--subject", "collect deterministic checks"]);
  assert.equal(validCommit.status, 0, validCommit.stderr);
  assert.match(validCommit.stdout, /^feat\(governance\): collect deterministic checks\n$/);

  const validCommitNoScope = runDayuFormat(["commit-message", "--type", "docs", "--subject", "document deterministic finalize"]);
  assert.equal(validCommitNoScope.status, 0, validCommitNoScope.stderr);
  assert.match(validCommitNoScope.stdout, /^docs: document deterministic finalize\n$/);

  const invalidCommit = runDayuFormat(["commit-message", "--type", "invalid", "--subject", "bad type"]);
  assert.equal(invalidCommit.status, 1, invalidCommit.stderr);

  const invalidCommitScope = runDayuFormat(["commit-message", "--type", "feat", "--scope", "bad scope", "--subject", "bad scope"]);
  assert.equal(invalidCommitScope.status, 1, invalidCommitScope.stderr);

  const validIssue = runDayuFormat(["issue-body", "--summary", "topic", "--depends-on", "12,34", "--background", "pre-check"]);
  assert.equal(validIssue.status, 0, validIssue.stderr);
  assert.match(validIssue.stdout, /Depends on: #12, #34/);

  const validIssueWithoutDependencies = runDayuFormat(["issue-body", "--summary", "standalone topic"]);
  assert.equal(validIssueWithoutDependencies.status, 0, validIssueWithoutDependencies.stderr);
  assert.doesNotMatch(validIssueWithoutDependencies.stdout, /Depends on:/);

  const missingSummary = runDayuFormat(["issue-body", "--depends-on", "12"]);
  assert.equal(missingSummary.status, 1, missingSummary.stderr);

  const invalidIssueDependency = runDayuFormat(["issue-body", "--summary", "topic", "--depends-on", "0"]);
  assert.equal(invalidIssueDependency.status, 1, invalidIssueDependency.stderr);

  const validPrFinal = runDayuFormat([
    "pr-body",
    "--summary",
    "final PR",
    "--implementation",
    "adds deterministic path",
    "--test-command",
    "npm -s test",
    "--issue",
    "12",
    "--final",
    "yes"
  ]);
  assert.equal(validPrFinal.status, 0, validPrFinal.stderr);
  assert.match(validPrFinal.stdout, /Final PR: yes\nCloses #12/);

  const validPrNonFinal = runDayuFormat([
    "pr-body",
    "--summary",
    "partial PR",
    "--implementation",
    "adds one slice",
    "--test-command",
    "npm -s test",
    "--issue",
    "12",
    "--final",
    "no"
  ]);
  assert.equal(validPrNonFinal.status, 0, validPrNonFinal.stderr);
  assert.match(validPrNonFinal.stdout, /Final PR: no\nRefs #12/);

  const invalidPrIssue = runDayuFormat(["pr-body", "--summary", "topic", "--implementation", "oops", "--test-command", "npm -s test", "--issue", "0", "--final", "yes"]);
  assert.equal(invalidPrIssue.status, 1, invalidPrIssue.stdout);

  const invalidPrMissingTest = runDayuFormat(["pr-body", "--summary", "topic", "--implementation", "oops", "--issue", "12"]);
  assert.equal(invalidPrMissingTest.status, 1, invalidPrMissingTest.stdout);
});

test("commit-msg hook governance contract", (t) => {
  const workspace = mkWorkspace(t);

  const validCommitPath = join(workspace, "valid-commit.txt");
  const invalidCommitPath = join(workspace, "invalid-commit.txt");
  const skipCommitPath = join(workspace, "skip-commit.txt");

  write(validCommitPath, "feat(scope): support deterministic governance checks\n");
  write(invalidCommitPath, "bad commit\n");
  write(skipCommitPath, "bad commit\n");
  write(join(workspace, "commitlint.config.cjs"), "module.exports = {}\n");

  const validHook = runCommitMsgHook(workspace, validCommitPath);
  assert.equal(validHook.status, 0, validHook.stderr);

  write(validCommitPath, "fix: repair deterministic remote path\n");
  const secondValidHook = runCommitMsgHook(workspace, validCommitPath);
  assert.equal(secondValidHook.status, 0, secondValidHook.stderr);

  const invalidHook = runCommitMsgHook(workspace, invalidCommitPath);
  assert.equal(invalidHook.status, 1, invalidHook.stdout);
  assert.match(execOutput(invalidHook), /ERROR: commit message does not follow Conventional Commits format/);

  write(invalidCommitPath, "feat: bad commit\n");
  const failingCommitlintHook = runCommitMsgHook(workspace, invalidCommitPath);
  assert.equal(failingCommitlintHook.status, 1, failingCommitlintHook.stdout);

  rmSync(join(workspace, "commitlint.config.cjs"));
  const skippedHook = runCommitMsgHook(workspace, skipCommitPath);
  assert.equal(skippedHook.status, 0, skippedHook.stderr);

  const missingArgHook = runCommand("bash", [assets.commitMsgHook]);
  assert.equal(missingArgHook.status, 2);
  assert.match(execOutput(missingArgHook), /commit message file path is missing/);
});

test("branch and tag pre-push snippets gate destructive operations", () => {
  const workspace = mkTempWorkspace("pre-push-");
  try {
    const mainProtectedFail = runPrePushSnippet(workspace, assets.branchProtection, `ref1 ${hash1} refs/heads/main ${hash1}`);
    assert.equal(mainProtectedFail.status, 1);

    const mainDeletion = runPrePushSnippet(workspace, assets.branchProtection, `ref1 ${zeroSha} refs/heads/main ${hash1}`);
    assert.equal(mainDeletion.status, 1);

    const featureBranch = runPrePushSnippet(workspace, assets.branchProtection, `ref1 ${hash1} refs/heads/feature ${hash2}`);
    assert.equal(featureBranch.status, 0, featureBranch.stderr);

    const allowedMainCreation = runPrePushSnippet(
      workspace,
      assets.branchProtection,
      `ref1 ${hash1} refs/heads/main ${zeroSha}`,
      { DAYU_HARNESS_ALLOW_DEFAULT_BRANCH_CREATION: "1" }
    );
    assert.equal(allowedMainCreation.status, 0, allowedMainCreation.stderr);

    const firstTagCreate = runPrePushSnippet(workspace, assets.tagProtection, `ref1 ${hash1} refs/tags/v2.0.0 ${zeroSha}`);
    assert.equal(firstTagCreate.status, 0, firstTagCreate.stderr);

    const nonReleaseTagOverwrite = runPrePushSnippet(workspace, assets.tagProtection, `ref1 ${hash2} refs/tags/test ${hash1}`);
    assert.equal(nonReleaseTagOverwrite.status, 0, nonReleaseTagOverwrite.stderr);

    const tagDeletion = runPrePushSnippet(workspace, assets.tagProtection, `ref1 ${zeroSha} refs/tags/v2.0.0 ${hash2}`);
    assert.equal(tagDeletion.status, 1);

    const tagOverwrite = runPrePushSnippet(workspace, assets.tagProtection, `ref1 ${hash2} refs/tags/v2.0.0 ${hash1}`);
    assert.equal(tagOverwrite.status, 1);
  } finally {
    rmSync(workspace, { recursive: true, force: true });
  }
});

test("default branch creation can be allowed while normal direct pushes remain blocked", (t) => {
  const workspace = mkWorkspace(t);

  const allowedCreation = runPrePushSnippet(
    workspace,
    assets.branchProtection,
    `ref1 ${hash1} refs/heads/main ${zeroSha}`,
    { DAYU_HARNESS_ALLOW_DEFAULT_BRANCH_CREATION: "1" }
  );
  assert.equal(allowedCreation.status, 0, allowedCreation.stderr);

  const normalProtectedFail = runPrePushSnippet(
    workspace,
    assets.branchProtection,
    `ref1 ${hash1} refs/heads/main ${hash2}`
  );
  assert.equal(normalProtectedFail.status, 1);
  assert.match(execOutput(normalProtectedFail), /direct push to main is not allowed/);
});

test("issue and PR body validators enforce issue-first and final-push semantics", (t) => {
  const workspace = mkWorkspace(t);

  const issueNoDepends = runIssueValidator(workspace, "## Summary\nNo depends line now");
  assert.equal(issueNoDepends.status, 0, issueNoDepends.stderr);
  assert.match(issueNoDepends.stdout, /dependency lint skipped/);

  const issueValid = runIssueValidator(workspace, "## Summary\nDepends on: #12, #34\n");
  assert.equal(issueValid.status, 0, issueValid.stderr);
  assert.match(issueValid.stdout, /OK: Issue depends-on line is valid\./);

  const issueInvalid = runIssueValidator(workspace, "## Summary\n- Depends on: #12\n");
  assert.equal(issueInvalid.status, 1);
  assert.match(issueInvalid.stderr, /Invalid issue dependency format/);

  const issueDouble = runIssueValidator(workspace, "## Summary\nDepends on: #12\nDepends on: #34\n");
  assert.equal(issueDouble.status, 1);
  assert.match(issueDouble.stderr, /at most one/);

  const prFinalNo = runDayuFormat([
    "pr-body",
    "--summary",
    "non final PR",
    "--implementation",
    "split task",
    "--test-command",
    "npm -s test",
    "--issue",
    "12",
    "--final",
    "no"
  ]);
  assert.equal(prFinalNo.status, 0, prFinalNo.stderr);
  const prFinalYes = runDayuFormat([
    "pr-body",
    "--summary",
    "final PR",
    "--implementation",
    "merge all",
    "--test-command",
    "npm -s test",
    "--issue",
    "12",
    "--final",
    "yes"
  ]);
  assert.equal(prFinalYes.status, 0, prFinalYes.stderr);

  const prValidNo = runPrBodyValidator(workspace, prFinalNo.stdout);
  assert.equal(prValidNo.status, 0, prValidNo.stderr);
  const prValidYes = runPrBodyValidator(workspace, prFinalYes.stdout);
  assert.equal(prValidYes.status, 0, prValidYes.stderr);

  const prInvalidTrailer = prFinalYes.stdout.replace("Closes #12", "Refs #12");
  const prInvalid = runPrBodyValidator(workspace, prInvalidTrailer);
  assert.equal(prInvalid.status, 1);
  assert.match(execOutput(prInvalid), /Final PRs must use a closing issue trailer|Non-final PRs must use a non-closing issue trailer|Non-closing issue trailers require an explicit 'Final PR: no' line/);

  const prConflictFixture = join(workspace, "open-prs.json");
  write(
    prConflictFixture,
    JSON.stringify({
      pulls: [
        {
          number: 99,
          body: "## Summary\n- existing\n## Implementation notes\n- done\n## Test plan\n- [x] `npm -s test`\n\nFinal PR: yes\nCloses #12"
        }
      ]
    })
  );
  const prConflict = runPrBodyValidator(workspace, prFinalYes.stdout, ["--pr-number", "100", "--open-prs-json", prConflictFixture]);
  assert.equal(prConflict.status, 1);
  assert.match(prConflict.stderr, /other open PRs reference the same issue #12/);
});

test("release policy acceptance and rejection examples", (t) => {
  const workspace = mkWorkspace(t);
  const policyPath = join(workspace, "release-please-policy.json");
  createPolicyFixture(workspace);

  const ok = runReleasePolicy(workspace, policyPath);
  assert.equal(ok.status, 0, ok.stderr);
  assert.match(ok.stdout, /OK: release-please policy checks passed/);

  const policyObject = json(policyPath) as Record<string, unknown>;
  const updatedPolicyObject = structuredClone(policyObject) as {
    release_please_config?: {
      pull_request_title_pattern?: string;
      [key: string]: unknown;
    };
  };
  delete updatedPolicyObject.release_please_config?.pull_request_title_pattern;
  write(policyPath, `${JSON.stringify(updatedPolicyObject, null, 2)}\n`);
  const okSecond = runReleasePolicy(workspace, policyPath);
  assert.equal(okSecond.status, 0, okSecond.stderr);

  const workflowPath = join(workspace, ".github/workflows/release-please.yml");
  const manifest = json(join(workspace, ".release-please-manifest.json")) as Record<string, unknown>;
  const workflowText = readFileSync(workflowPath, "utf8");
  assert.equal(manifest["."], "__DAYU_PROJECT_VERSION__");
  assert.match(workflowText, /sync_version_from_manifest/);
  assert.match(workflowText, /git -C "\$workdir" add VERSION/);

  write(workflowPath, workflowText.replaceAll("sync_version_from_manifest", "sync_version_missing"));
  const badVersionSync = runReleasePolicy(workspace, policyPath);
  assert.equal(badVersionSync.status, 1);
  assert.match(badVersionSync.stderr, /sync plain VERSION from \.release-please-manifest\.json/);
  copyTextFile(assets.releaseWorkflow, workflowPath);

  const policyMissingWorkflow = JSON.parse(readFileSync(policyPath, "utf8")) as Record<string, any>;
  policyMissingWorkflow.workflow = {
    ...(policyMissingWorkflow.workflow || {}),
    additional_workflows: [".github/workflows/pr-lint.yml"],
    merge_command: "echo not-allowed"
  };
  write(policyPath, `${JSON.stringify(policyMissingWorkflow, null, 2)}\n`);
  const badMerge = runReleasePolicy(workspace, policyPath);
  assert.equal(badMerge.status, 1);
  assert.match(badMerge.stderr, /merge_command/);

  const policyMissingAdditional = JSON.parse(readFileSync(policyPath, "utf8")) as Record<string, any>;
  delete policyMissingAdditional.workflow.additional_workflows;
  write(policyPath, `${JSON.stringify(policyMissingAdditional, null, 2)}\n`);
  const badAdditional = runReleasePolicy(workspace, policyPath);
  assert.equal(badAdditional.status, 1);
  assert.match(badAdditional.stderr, /workflow.additional_workflows must include/);
});

test("ruleset contract validation for API payload shape", (t) => {
  const workspace = mkWorkspace(t);
  const main = json(assets.rulesetMain);
  const tags = json(assets.rulesetTags);
  const mainRuleset = parseRuleset(main);
  const tagRuleset = parseRuleset(tags);

  assert.equal(mainRuleset.name, "protect-main");
  assert.equal(tagRuleset.target, "tag");
  assert.deepEqual((mainRuleset.conditions as { ref_name: { include: string[] } }).ref_name.include, ["refs/heads/__DAYU_DEFAULT_BRANCH__"]);
  assert.deepEqual((tagRuleset.conditions as { ref_name: { include: string[] } }).ref_name.include, ["refs/tags/v*"]);

  const invalidMissingName = {
    ...json(assets.rulesetMain) as Record<string, unknown>,
    name: ""
  };
  write(join(workspace, "ruleset-missing-name.json"), `${JSON.stringify(invalidMissingName, null, 2)}\n`);
  assert.throws(() => parseRuleset(json(join(workspace, "ruleset-missing-name.json")) as unknown));

  const invalidConditions = {
    ...json(assets.rulesetMain) as Record<string, unknown>,
    conditions: {}
  };
  write(join(workspace, "ruleset-missing-conditions.json"), `${JSON.stringify(invalidConditions, null, 2)}\n`);
  assert.throws(() => parseRuleset(json(join(workspace, "ruleset-missing-conditions.json")) as unknown));
});
