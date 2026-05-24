import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import test, { type TestContext } from "node:test";
import { fileURLToPath } from "node:url";

import {
  applyDayuConfig,
  applyDayuMerge,
  createDefaultDayuConfig,
  finalizeDayuProject,
  loadManifestRegistry,
  repairDayuCapability,
  statusDayuProject,
  stringifyDayuConfig
} from "../../src/cli/index.js";
import { loadLocaleCatalog } from "../../src/cli/render.js";
import { ManifestV2Schema, collectManifestI18nKeys, missingLocaleKeys } from "../../src/schemas/index.js";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));
const tmpRoot = join(repoRoot, ".tmp");
const cliPath = join(repoRoot, "src/cli/main.ts");
const stateDir = ".dayu-harness";

function makeTarget(t: TestContext): string {
  mkdirSync(tmpRoot, { recursive: true });
  const target = mkdtempSync(join(tmpRoot, "phase2-"));
  t.after(() => rmSync(target, { recursive: true, force: true }));
  return target;
}

function writeConfig(target: string, capabilityIds: readonly string[]): string {
  const configPath = join(target, "dayu.config.yaml");
  writeFileSync(
    configPath,
    stringifyDayuConfig({
      schemaVersion: "1.0.0",
      locale: "zh",
      project: {
        name: "phase2-fixture"
      },
      capabilities: capabilityIds.map((id) => ({ id, enabled: true }))
    }),
    "utf8"
  );
  return configPath;
}

function runCli(args: string[]) {
  return spawnSync(process.execPath, ["--import", "tsx", cliPath, ...args], { cwd: repoRoot, encoding: "utf8" });
}

test("Phase 2 registry loads all manifest v2 capabilities and locale keys", () => {
  const registry = loadManifestRegistry(repoRoot);
  const zh = loadLocaleCatalog(repoRoot, "zh");
  const en = loadLocaleCatalog(repoRoot, "en");
  const requiredKeys = new Set<string>();

  assert.equal(registry.manifests.length, 20);
  for (const manifest of registry.manifests) {
    ManifestV2Schema.parse(manifest);
    for (const key of collectManifestI18nKeys(manifest)) {
      requiredKeys.add(key);
    }
  }

  assert.deepEqual(missingLocaleKeys(zh, requiredKeys), []);
  assert.deepEqual(missingLocaleKeys(en, requiredKeys), []);
});

test("Phase 2 apply supports all non-internal capabilities and stays idempotent", (t) => {
  const target = makeTarget(t);
  const registry = loadManifestRegistry(repoRoot);
  const capabilityIds = registry.manifests.filter((manifest) => !manifest.internal).map((manifest) => manifest.id);
  const configPath = writeConfig(target, capabilityIds);

  const dryRun = applyDayuConfig({ configPath, targetRoot: target, dryRun: true });
  assert.equal(dryRun.status, "planned");
  assert.equal(dryRun.deploymentOrder.length, 20);
  assert.equal(dryRun.summary.missingSource, 0);
  assert.equal(dryRun.summary.unsupported, 0);

  const first = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(first.status, "applied");
  assert.ok(existsSync(join(target, stateDir, "journal.jsonl")));
  assert.ok(existsSync(join(target, stateDir, "managed-paths.json")));
  const managedPathsBefore = sha256(readFileSync(join(target, stateDir, "managed-paths.json"), "utf8"));

  const second = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(second.status, "no-op");
  assert.deepEqual(second.changedPaths, []);
  assert.equal(sha256(readFileSync(join(target, stateDir, "managed-paths.json"), "utf8")), managedPathsBefore);
  const prunePreview = applyDayuConfig({ configPath, targetRoot: target, dryRun: true, pruneOrphans: true });
  assert.equal(prunePreview.orphanPaths.includes(`${stateDir}/managed-paths.json`), false);
  assert.equal(
    prunePreview.fileOperations.some((operation) => operation.dst === `${stateDir}/managed-paths.json` && operation.status === "delete"),
    false
  );
  const prune = applyDayuConfig({ configPath, targetRoot: target, pruneOrphans: true });
  assert.equal(existsSync(join(target, stateDir, "managed-paths.json")), true);
  assert.equal(prune.changedPaths.includes(`${stateDir}/managed-paths.json`), false);

  const status = statusDayuProject({ configPath, targetRoot: target });
  assert.equal(status.status, "healthy");
  assert.equal(status.summary.hard, 9);
  assert.equal(status.summary.soft, 3);
  assert.equal(status.summary.infra, 8);
});

test("Phase 2 apply CLI JSON includes localized capability display summaries", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core", "git.commit-format"]);

  const result = runCli(["apply", "--config", configPath, "--target", target, "--dry-run", "--json"]);

  assert.equal(result.status, 0, result.stderr);
  const report = JSON.parse(result.stdout) as {
    deploymentOrder: string[];
    capabilitySummaries?: Array<{ capabilityId: string; displayName?: string; summary?: string }>;
  };
  assert.deepEqual(
    report.capabilitySummaries?.map((capability) => capability.capabilityId),
    report.deploymentOrder
  );
  assert.equal(
    report.capabilitySummaries?.find((capability) => capability.capabilityId === "core")?.displayName,
    "核心治理基础设施"
  );
  assert.equal(
    report.capabilitySummaries?.find((capability) => capability.capabilityId === "git.commit-format")?.displayName,
    "Git 提交格式约束"
  );
  assert.match(
    report.capabilitySummaries?.find((capability) => capability.capabilityId === "git.commit-format")?.summary ?? "",
    /Conventional Commits|提交格式/
  );
});

test("Phase 2 status human output shows capability display names instead of raw keys", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core", "git.commit-format"]);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");

  const result = runCli(["status", "--config", configPath, "--target", target]);

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Git 提交格式约束/);
  assert.doesNotMatch(result.stdout, /\bgit\.commit-format\b/);
});

test("Phase 2 JSON command surfaces include localized capability display summaries", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core", "git.commit-format"]);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");

  const diagnose = runCli(["diagnose", "--config", configPath, "--target", target, "--json"]);
  assert.equal(diagnose.status, 0, diagnose.stderr);
  const diagnoseReport = JSON.parse(diagnose.stdout) as {
    items?: Array<{ capabilityId: string; displayName?: string; displaySummary?: string }>;
    capabilities?: Array<{ capabilityId: string; displayName?: string; displaySummary?: string }>;
  };
  const diagnoseItem = diagnoseReport.items?.find((item) => item.capabilityId === "git.commit-format");
  assert.equal(diagnoseItem?.displayName, "Git 提交格式约束");
  assert.match(diagnoseItem?.displaySummary ?? "", /Conventional Commits|提交格式/);
  assert.equal(
    diagnoseReport.capabilities?.find((capability) => capability.capabilityId === "git.commit-format")?.displayName,
    "Git 提交格式约束"
  );

  const merge = runCli(["merge", "--config", configPath, "--target", target, "--json"]);
  assert.equal(merge.status, 0, merge.stderr);
  const mergeReport = JSON.parse(merge.stdout) as {
    capabilities?: Array<{ capabilityId: string; displayName?: string; displaySummary?: string }>;
  };
  const mergeCapability = mergeReport.capabilities?.find((capability) => capability.capabilityId === "git.commit-format");
  assert.equal(mergeCapability?.displayName, "Git 提交格式约束");
  assert.match(mergeCapability?.displaySummary ?? "", /Conventional Commits|提交格式/);

  const generated = runCli(["generate", "--config", configPath, "--target", target, "--capability", "git.commit-format", "--json"]);
  assert.equal(generated.status, 0, generated.stderr);
  const generateReport = JSON.parse(generated.stdout) as {
    files?: Array<{ capabilityId: string; displayName?: string; summary?: string }>;
  };
  assert.ok(generateReport.files?.length);
  assert.equal(generateReport.files?.[0]?.displayName, "Git 提交格式约束");
  assert.match(generateReport.files?.[0]?.summary ?? "", /Conventional Commits|提交格式/);
});

test("Phase 2 finalize stops before staging or commit when local checks fail", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core"]);
  git(target, ["init", "-b", "main"]);

  const report = finalizeDayuProject({ configPath, targetRoot: target });

  assert.equal(report.status, "failed");
  assert.deepEqual(report.stagedPaths, []);
  assert.equal(report.commitSha, undefined);
  assert.equal(spawnSync("git", ["-C", target, "rev-parse", "--verify", "HEAD"], { encoding: "utf8" }).status, 128);
});

test("Phase 2 finalize stages managed deletions and commits after local checks pass", (t) => {
  const target = makeTarget(t);
  const registry = loadManifestRegistry(repoRoot);
  const configPath = writeConfig(
    target,
    registry.manifests.filter((manifest) => !manifest.internal).map((manifest) => manifest.id)
  );
  git(target, ["init", "-b", "main"]);
  configureGitIdentity(target);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");
  writeFileSync(join(target, "package.json"), `${JSON.stringify({ name: "phase2-fixture", version: "0.1.0" }, null, 2)}\n`, "utf8");
  writeFileSync(join(target, "VERSION"), "0.1.0\n", "utf8");
  writeFileSync(join(target, "CHANGELOG.md"), "# Changelog\n\n## 0.1.0 - 2026-05-24\n\n- Initial baseline.\n", "utf8");

  const oldManagedPath = "old-managed-root.txt";
  const userOwnedOldPath = "user-owned-old-managed.txt";
  writeFileSync(join(target, oldManagedPath), "old managed file\n", "utf8");
  writeFileSync(join(target, userOwnedOldPath), "user-owned baseline\n", "utf8");
  const managedPathsPath = join(target, stateDir, "managed-paths.json");
  const managedPaths = JSON.parse(readFileSync(managedPathsPath, "utf8")) as {
    managedPaths: string[];
    previousManagedPaths?: string[];
    updatedAt: string;
  };
  managedPaths.managedPaths = [...new Set([...managedPaths.managedPaths, oldManagedPath, userOwnedOldPath])].sort();
  writeFileSync(managedPathsPath, `${JSON.stringify(managedPaths, null, 2)}\n`, "utf8");
  git(target, ["add", "."]);
  git(target, ["commit", "-m", "chore: baseline"]);

  managedPaths.managedPaths = managedPaths.managedPaths.filter((item) => item !== oldManagedPath && item !== userOwnedOldPath);
  managedPaths.previousManagedPaths = [...new Set([...(managedPaths.previousManagedPaths ?? []), oldManagedPath, userOwnedOldPath])].sort();
  writeFileSync(managedPathsPath, `${JSON.stringify(managedPaths, null, 2)}\n`, "utf8");
  rmSync(join(target, oldManagedPath), { force: true });
  writeFileSync(join(target, userOwnedOldPath), "user-owned edit\n", "utf8");
  const report = finalizeDayuProject({ configPath, targetRoot: target });

  assert.equal(report.status, "partial");
  assert.ok(report.commitSha);
  const nameStatus = git(target, ["show", "--name-status", "--format=", "HEAD"]);
  assert.match(nameStatus, new RegExp(`D\\s+${oldManagedPath}`));
  assert.doesNotMatch(nameStatus, new RegExp(userOwnedOldPath));
});

test("Phase 2 finalize blocks unrelated pre-staged files before committing", (t) => {
  const target = makeTarget(t);
  const registry = loadManifestRegistry(repoRoot);
  const configPath = writeConfig(
    target,
    registry.manifests.filter((manifest) => !manifest.internal).map((manifest) => manifest.id)
  );
  git(target, ["init", "-b", "main"]);
  configureGitIdentity(target);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");
  writeFileSync(join(target, "package.json"), `${JSON.stringify({ name: "phase2-fixture", version: "0.1.0" }, null, 2)}\n`, "utf8");
  writeFileSync(join(target, "VERSION"), "0.1.0\n", "utf8");
  writeFileSync(join(target, "CHANGELOG.md"), "# Changelog\n\n## 0.1.0 - 2026-05-24\n\n- Initial baseline.\n", "utf8");
  mkdirSync(join(target, "src"), { recursive: true });
  writeFileSync(join(target, "src", "user-work.js"), "export const userWork = true;\n", "utf8");
  git(target, ["add", "src/user-work.js"]);

  const report = finalizeDayuProject({ configPath, targetRoot: target });

  assert.equal(report.status, "failed");
  assert.equal(report.commitSha, undefined);
  assert.ok(report.checks.some((check) => check.name === "Git 暂存区边界" && check.status === "failed"));
  assert.equal(spawnSync("git", ["-C", target, "rev-parse", "--verify", "HEAD"], { encoding: "utf8" }).status, 128);
  assert.match(git(target, ["diff", "--cached", "--name-only"]), /src\/user-work\.js/);
});

test("Phase 2 dry-run apply does not migrate legacy state directory", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core"]);
  mkdirSync(join(target, ".dayu"), { recursive: true });
  writeFileSync(join(target, ".dayu", "managed-paths.json"), `${JSON.stringify({ managedPaths: ["AGENTS.md"], updatedAt: "2026-05-24T00:00:00.000Z" })}\n`, "utf8");

  const report = applyDayuConfig({ configPath, targetRoot: target, dryRun: true });

  assert.equal(report.status, "planned");
  assert.ok(existsSync(join(target, ".dayu", "managed-paths.json")));
  assert.equal(existsSync(join(target, stateDir, "managed-paths.json")), false);
});

test("Phase 2 dry-run prune previews legacy managed orphans without migrating state", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core"]);
  mkdirSync(join(target, ".dayu"), { recursive: true });
  writeFileSync(join(target, "legacy-orphan.md"), "legacy orphan\n", "utf8");
  writeFileSync(
    join(target, ".dayu", "managed-paths.json"),
    `${JSON.stringify({ managedPaths: ["legacy-orphan.md"], updatedAt: "2026-05-24T00:00:00.000Z" })}\n`,
    "utf8"
  );

  const report = applyDayuConfig({ configPath, targetRoot: target, dryRun: true, pruneOrphans: true });

  assert.equal(report.status, "planned");
  assert.ok(report.orphanPaths.includes("legacy-orphan.md"));
  assert.ok(report.fileOperations.some((operation) => operation.dst === "legacy-orphan.md" && operation.status === "delete"));
  assert.ok(existsSync(join(target, ".dayu", "managed-paths.json")));
  assert.equal(existsSync(join(target, stateDir, "managed-paths.json")), false);
});

test("Phase 2 repair force-overwrites drift for a selected capability", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core"]);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");

  writeFileSync(join(target, "AGENTS.md"), "manual drift\n", "utf8");
  const conflicted = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(conflicted.status, "conflict");
  assert.equal(readFileSync(join(target, "AGENTS.md"), "utf8"), "manual drift\n");

  const repaired = repairDayuCapability({ configPath, targetRoot: target, capabilityId: "core" });
  assert.equal(repaired.status, "repaired");
  assert.match(readFileSync(join(target, "AGENTS.md"), "utf8"), /项目级路由入口|project-level routing/i);
});

test("Phase 2 merge replace can be scoped to one capability", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core", "ai.memory"]);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");

  writeFileSync(join(target, "AGENTS.md"), "core drift\n", "utf8");
  writeFileSync(join(target, "docs/harness/guides/ai-memory.md"), "memory drift\n", "utf8");

  const merged = applyDayuMerge({
    configPath,
    targetRoot: target,
    strategy: "replace",
    onlyCapabilityId: "core",
    dryRun: false
  });

  assert.equal(merged.status, "merged");
  assert.match(readFileSync(join(target, "AGENTS.md"), "utf8"), /项目级路由入口|project-level routing/i);
  assert.equal(readFileSync(join(target, "docs/harness/guides/ai-memory.md"), "utf8"), "memory drift\n");
});

test("Phase 2 merge replace passes replace strategy to gitignore installer", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["project.gitignore"]);
  writeFileSync(join(target, ".gitignore"), "custom-rule\n", "utf8");

  const merged = applyDayuMerge({
    configPath,
    targetRoot: target,
    strategy: "replace",
    onlyCapabilityId: "project.gitignore",
    dryRun: false
  });

  assert.equal(merged.status, "merged");
  const gitignore = readFileSync(join(target, ".gitignore"), "utf8");
  assert.match(gitignore, /Dayu Harness local exclusions/);
  assert.doesNotMatch(gitignore, /custom-rule/);
});

test("Phase 2 orphan pruning removes previously managed paths only when explicit", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core", "ai.memory"]);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");
  assert.ok(existsSync(join(target, "docs/harness/guides/ai-memory.md")));

  writeConfig(target, ["core"]);
  const preview = applyDayuConfig({ configPath, targetRoot: target, dryRun: true });
  assert.equal(preview.status, "planned");
  assert.ok(preview.orphanPaths.includes("docs/harness/guides/ai-memory.md"));
  assert.ok(existsSync(join(target, "docs/harness/guides/ai-memory.md")));

  const pruned = applyDayuConfig({ configPath, targetRoot: target, pruneOrphans: true });
  assert.equal(pruned.status, "applied");
  assert.ok(pruned.changedPaths.includes("docs/harness/guides/ai-memory.md"));
  assert.equal(existsSync(join(target, "docs/harness/guides/ai-memory.md")), false);
});

test("Phase 2 scoped prune keeps files from other enabled capabilities", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core", "ai.memory"]);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");
  assert.ok(existsSync(join(target, "docs/harness/guides/ai-memory.md")));

  const preview = applyDayuConfig({
    configPath,
    targetRoot: target,
    onlyCapabilityId: "core",
    dryRun: true,
    pruneOrphans: true
  });

  assert.equal(preview.status, "planned");
  assert.equal(preview.orphanPaths.includes("docs/harness/guides/ai-memory.md"), false);
  assert.equal(
    preview.fileOperations.some((operation) => operation.dst === "docs/harness/guides/ai-memory.md" && operation.status === "delete"),
    false
  );
});

test("Phase 2 scoped apply does not claim unvisited enabled capabilities as managed", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core", "ai.memory"]);

  const scoped = applyDayuConfig({ configPath, targetRoot: target, onlyCapabilityId: "core" });
  assert.equal(scoped.status, "applied");
  assert.equal(existsSync(join(target, "docs/harness/guides/ai-memory.md")), false);
  const managedPaths = JSON.parse(readFileSync(join(target, stateDir, "managed-paths.json"), "utf8")) as {
    managedPaths: string[];
  };
  assert.ok(managedPaths.managedPaths.includes(`${stateDir}/managed-paths.json`));
  assert.equal(managedPaths.managedPaths.includes("docs/harness/guides/ai-memory.md"), false);

  mkdirSync(join(target, "docs/harness/guides"), { recursive: true });
  writeFileSync(join(target, "docs/harness/guides/ai-memory.md"), "user-owned memory notes\n", "utf8");
  writeConfig(target, ["core"]);

  const pruned = applyDayuConfig({ configPath, targetRoot: target, pruneOrphans: true });

  assert.equal(pruned.changedPaths.includes("docs/harness/guides/ai-memory.md"), false);
  assert.equal(readFileSync(join(target, "docs/harness/guides/ai-memory.md"), "utf8"), "user-owned memory notes\n");
});

test("Phase 2 apply repairs executable mode through journaled writes", (t) => {
  const target = makeTarget(t);
  const configPath = stringifyDefaultConfig(target);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");

  const validateScript = join(target, "docs/harness/sensors/scripts/validate.sh");
  chmodSync(validateScript, 0o644);

  const report = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(report.status, "applied");
  assert.ok(report.changedPaths.includes("docs/harness/sensors/scripts/validate.sh"));
});

test("Phase 2 apply replays an interrupted journal before planning", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core"]);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");

  const agentsPath = join(target, "AGENTS.md");
  const original = readFileSync(agentsPath, "utf8");
  mkdirSync(join(target, stateDir), { recursive: true });
  writeFileSync(join(target, stateDir, "apply.lock"), "999999\n2026-05-24T00:00:00.000Z\n", "utf8");
  writeFileSync(
    join(target, stateDir, "journal.jsonl"),
    `${JSON.stringify({
      id: "interrupted",
      command: "apply",
      phase: "preimage",
      path: "AGENTS.md",
      timestamp: "2026-05-24T00:00:00.000Z",
      checksum: "test",
      existed: true,
      contentBase64: Buffer.from(original).toString("base64")
    })}\n${JSON.stringify({
      id: "interrupted",
      command: "apply",
      phase: "write",
      path: "AGENTS.md",
      timestamp: "2026-05-24T00:00:01.000Z",
      checksum: sha256("interrupted write\n")
    })}\n`,
    "utf8"
  );
  writeFileSync(agentsPath, "interrupted write\n", "utf8");

  const report = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(report.status, "no-op");
  assert.equal(readFileSync(agentsPath, "utf8"), original);
  assert.equal(existsSync(join(target, stateDir, "apply.lock")), false);
});

test("Phase 2 journal replay does not overwrite user edits after interruption", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core"]);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");

  const agentsPath = join(target, "AGENTS.md");
  const original = readFileSync(agentsPath, "utf8");
  const interrupted = "interrupted write\n";
  mkdirSync(join(target, stateDir), { recursive: true });
  writeFileSync(join(target, stateDir, "apply.lock"), "999999\n2026-05-24T00:00:00.000Z\n", "utf8");
  writeFileSync(
    join(target, stateDir, "journal.jsonl"),
    `${JSON.stringify({
      id: "interrupted",
      command: "apply",
      phase: "preimage",
      path: "AGENTS.md",
      timestamp: "2026-05-24T00:00:00.000Z",
      checksum: "test",
      existed: true,
      contentBase64: Buffer.from(original).toString("base64")
    })}\n${JSON.stringify({
      id: "interrupted",
      command: "apply",
      phase: "write",
      path: "AGENTS.md",
      timestamp: "2026-05-24T00:00:01.000Z",
      checksum: sha256(interrupted)
    })}\n`,
    "utf8"
  );
  writeFileSync(agentsPath, "user edit after interruption\n", "utf8");

  const report = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(report.status, "conflict");
  assert.equal(readFileSync(agentsPath, "utf8"), "user edit after interruption\n");
  assert.match(readFileSync(join(target, stateDir, "journal.jsonl"), "utf8"), /"completed":true/);
});

test("Phase 2 journal replay does not rollback preimage-only entries", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core"]);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");

  const agentsPath = join(target, "AGENTS.md");
  const original = readFileSync(agentsPath, "utf8");
  mkdirSync(join(target, stateDir), { recursive: true });
  writeFileSync(join(target, stateDir, "apply.lock"), "999999\n2026-05-24T00:00:00.000Z\n", "utf8");
  writeFileSync(
    join(target, stateDir, "journal.jsonl"),
    `${JSON.stringify({
      id: "preimage-only",
      command: "apply",
      phase: "preimage",
      path: "AGENTS.md",
      timestamp: "2026-05-24T00:00:00.000Z",
      checksum: sha256(original),
      existed: true,
      contentBase64: Buffer.from(original).toString("base64")
    })}\n`,
    "utf8"
  );
  writeFileSync(agentsPath, "user edit after preimage only\n", "utf8");

  const report = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(report.status, "conflict");
  assert.equal(readFileSync(agentsPath, "utf8"), "user edit after preimage only\n");
  assert.match(readFileSync(join(target, stateDir, "journal.jsonl"), "utf8"), /"completed":true/);
});

function stringifyDefaultConfig(target: string): string {
  const configPath = join(target, "dayu.config.yaml");
  writeFileSync(configPath, stringifyDayuConfig(createDefaultDayuConfig(target)), "utf8");
  return configPath;
}

function sha256(content: string): string {
  return createHash("sha256").update(content).digest("hex");
}

function git(target: string, args: string[]): string {
  return execFileSync("git", ["-C", target, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}

function configureGitIdentity(target: string): void {
  git(target, ["config", "user.email", "dayu@example.test"]);
  git(target, ["config", "user.name", "Dayu Test"]);
}
