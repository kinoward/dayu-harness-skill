import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import test, { type TestContext } from "node:test";
import { fileURLToPath } from "node:url";

import {
  applyDayuConfig,
  applyDayuMerge,
  createDefaultDayuConfig,
  loadManifestRegistry,
  repairDayuCapability,
  statusDayuProject,
  stringifyDayuConfig
} from "../../src/cli/index.js";
import { loadLocaleCatalog } from "../../src/cli/render.js";
import { ManifestV2Schema, collectManifestI18nKeys, missingLocaleKeys } from "../../src/schemas/index.js";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));
const tmpRoot = join(repoRoot, ".tmp");

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
  assert.ok(existsSync(join(target, ".dayu/journal.jsonl")));
  assert.ok(existsSync(join(target, ".dayu/managed-paths.json")));

  const second = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(second.status, "no-op");
  assert.deepEqual(second.changedPaths, []);

  const status = statusDayuProject({ configPath, targetRoot: target });
  assert.equal(status.status, "healthy");
  assert.equal(status.summary.hard, 9);
  assert.equal(status.summary.soft, 3);
  assert.equal(status.summary.infra, 8);
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
  mkdirSync(join(target, ".dayu"), { recursive: true });
  writeFileSync(join(target, ".dayu", "apply.lock"), "999999\n2026-05-24T00:00:00.000Z\n", "utf8");
  writeFileSync(
    join(target, ".dayu", "journal.jsonl"),
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
  assert.equal(existsSync(join(target, ".dayu", "apply.lock")), false);
});

test("Phase 2 journal replay does not overwrite user edits after interruption", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core"]);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");

  const agentsPath = join(target, "AGENTS.md");
  const original = readFileSync(agentsPath, "utf8");
  const interrupted = "interrupted write\n";
  mkdirSync(join(target, ".dayu"), { recursive: true });
  writeFileSync(join(target, ".dayu", "apply.lock"), "999999\n2026-05-24T00:00:00.000Z\n", "utf8");
  writeFileSync(
    join(target, ".dayu", "journal.jsonl"),
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
  assert.match(readFileSync(join(target, ".dayu", "journal.jsonl"), "utf8"), /"completed":true/);
});

test("Phase 2 journal replay does not rollback preimage-only entries", (t) => {
  const target = makeTarget(t);
  const configPath = writeConfig(target, ["core"]);
  assert.equal(applyDayuConfig({ configPath, targetRoot: target }).status, "applied");

  const agentsPath = join(target, "AGENTS.md");
  const original = readFileSync(agentsPath, "utf8");
  mkdirSync(join(target, ".dayu"), { recursive: true });
  writeFileSync(join(target, ".dayu", "apply.lock"), "999999\n2026-05-24T00:00:00.000Z\n", "utf8");
  writeFileSync(
    join(target, ".dayu", "journal.jsonl"),
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
  assert.match(readFileSync(join(target, ".dayu", "journal.jsonl"), "utf8"), /"completed":true/);
});

function stringifyDefaultConfig(target: string): string {
  const configPath = join(target, "dayu.config.yaml");
  writeFileSync(configPath, stringifyDayuConfig(createDefaultDayuConfig(target)), "utf8");
  return configPath;
}

function sha256(content: string): string {
  return createHash("sha256").update(content).digest("hex");
}
