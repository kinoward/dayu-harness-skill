import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  symlinkSync,
  writeFileSync
} from "node:fs";
import { join } from "node:path";
import test, { type TestContext } from "node:test";
import { fileURLToPath } from "node:url";

import {
  applyDayuConfig,
  createDefaultDayuConfig,
  diagnoseDayuProject,
  stringifyDayuConfig,
  validateDayuProject
} from "../../src/cli/index.js";
import { writeFileAtomically } from "../../src/cli/filesystem.js";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));
const tmpRoot = join(repoRoot, ".tmp");
const cliPath = join(repoRoot, "src/cli/main.ts");
const huskyInstallerPath = join(repoRoot, "scripts/install-husky.sh");

function makeTarget(t: TestContext): string {
  mkdirSync(tmpRoot, { recursive: true });
  const target = mkdtempSync(join(tmpRoot, "phase1e-"));
  t.after(() => rmSync(target, { recursive: true, force: true }));
  return target;
}

function writeDefaultConfig(target: string): string {
  const configPath = join(target, "dayu.config.yaml");
  writeFileSync(configPath, stringifyDayuConfig(createDefaultDayuConfig(target)), "utf8");
  return configPath;
}

function runCli(args: string[], cwd = repoRoot) {
  return spawnSync(process.execPath, ["--import", "tsx", cliPath, ...args], { cwd, encoding: "utf8" });
}

test("Phase 2 public CLI exposes product commands", () => {
  const result = runCli(["--help"]);

  assert.equal(result.status, 0, result.stderr);
  for (const command of ["init", "apply", "merge", "generate", "repair", "status", "diagnose", "validate"]) {
    assert.match(result.stdout, new RegExp(`\\b${command}\\b`), command);
  }
});

test("Phase 1e init defaults to dry-run and requires --apply to write", (t) => {
  const target = makeTarget(t);

  const dryRun = runCli(["init", "--target", target, "--json"]);
  assert.equal(dryRun.status, 0, dryRun.stderr);
  const dryRunReport = JSON.parse(dryRun.stdout) as { command: string; dryRun: boolean; configOperation: string };
  assert.equal(dryRunReport.command, "init");
  assert.equal(dryRunReport.dryRun, true);
  assert.equal(dryRunReport.configOperation, "create");
  assert.equal(existsSync(join(target, "dayu.config.yaml")), false);

  const applied = runCli(["init", "--target", target, "--apply", "--json"]);
  assert.equal(applied.status, 0, applied.stderr);
  const appliedReport = JSON.parse(applied.stdout) as { dryRun: boolean; status: string };
  assert.equal(appliedReport.dryRun, false);
  assert.equal(appliedReport.status, "applied");
  assert.equal(existsSync(join(target, "dayu.config.yaml")), true);
});

test("Phase 1e init rejects conflicting --apply and --dry-run flags", (t) => {
  const target = makeTarget(t);

  const result = runCli(["init", "--target", target, "--apply", "--dry-run", "--json"]);

  assert.equal(result.status, 1);
  const error = JSON.parse(result.stderr) as { status: string; code: string };
  assert.equal(error.status, "error");
  assert.equal(error.code, "conflicting-options");
  assert.equal(existsSync(join(target, "dayu.config.yaml")), false);
});

test("Phase 1e apply --only deploys one enabled capability plus deployment dependencies", (t) => {
  const target = makeTarget(t);
  const configPath = writeDefaultConfig(target);

  const report = applyDayuConfig({ configPath, targetRoot: target, onlyCapabilityId: "git.commit-format" });

  assert.equal(report.status, "applied");
  assert.deepEqual(report.deploymentOrder, ["core", "git.hooks", "git.commit-format"]);
  assert.ok(existsSync(join(target, "docs/harness/guides/commit-guidelines.md")));
  assert.ok(existsSync(join(target, ".husky/commit-msg")));
  assert.equal(existsSync(join(target, "docs/harness/guides/ai-execution.md")), false);

  const validate = validateDayuProject({ configPath, targetRoot: target, onlyCapabilityId: "git.commit-format" });
  assert.equal(validate.status, "valid");
  assert.deepEqual(validate.deployment.order, ["core", "git.hooks", "git.commit-format"]);
});

test("Phase 1e diagnose JSON includes capability RSE summaries", (t) => {
  const target = makeTarget(t);
  const configPath = writeDefaultConfig(target);
  const apply = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(apply.status, "applied");

  const diagnose = diagnoseDayuProject({ configPath, targetRoot: target });
  const commitFormat = diagnose.capabilities.find((capability) => capability.capabilityId === "git.commit-format");
  const aiExecution = diagnose.capabilities.find((capability) => capability.capabilityId === "ai.execution");

  assert.equal(commitFormat?.rse.rule.present, true);
  assert.equal(commitFormat?.rse.sensor.present, true);
  assert.equal(commitFormat?.rse.enforcer.present, true);
  assert.equal(aiExecution?.rse.rule.present, true);
  assert.equal(aiExecution?.rse.sensor.present, false);
  assert.equal(aiExecution?.rse.enforcer.present, false);
});

test("Phase 1e husky installer preserves existing hook symlinks and modes", (t) => {
  const target = makeTarget(t);
  const huskyDir = join(target, ".husky");
  const actualHook = join(huskyDir, "actual-commit-msg");
  const symlinkedHook = join(huskyDir, "commit-msg");
  mkdirSync(huskyDir, { recursive: true });
  writeFileSync(actualHook, "#!/usr/bin/env bash\necho existing\n", "utf8");
  chmodSync(actualHook, 0o755);
  symlinkSync("actual-commit-msg", symlinkedHook);

  const result = spawnSync("bash", [huskyInstallerPath, target, "--apply", "merge"], {
    env: {
      ...process.env,
      DAYU_HARNESS_CAPABILITY: "git.commit-format"
    },
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
  assert.equal(lstatSync(symlinkedHook).isSymbolicLink(), true);
  assert.equal(statSync(actualHook).mode & 0o777, 0o755);
  assert.match(readFileSync(actualHook, "utf8"), /echo existing/);
  assert.match(readFileSync(actualHook, "utf8"), /dayu-harness:git\.commit-format/);
});

test("Phase 1e atomic write cleans temporary file when final rename fails", (t) => {
  const target = makeTarget(t);
  const blockedPath = join(target, "blocked");
  mkdirSync(blockedPath);

  assert.throws(() => writeFileAtomically(blockedPath, "new content"));

  assert.deepEqual(
    readdirSync(target).filter((entry) => entry.startsWith(".") && entry.endsWith(".tmp")),
    []
  );
});
