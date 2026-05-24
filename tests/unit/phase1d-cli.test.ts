import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import test, { type TestContext } from "node:test";
import { fileURLToPath } from "node:url";

import {
  applyDayuConfig,
  createDefaultDayuConfig,
  diagnoseDayuProject,
  generateDayuContent,
  initDayuConfig,
  planDayuMerge,
  stringifyDayuConfig,
  validateDayuProject
} from "../../src/cli/index.js";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));
const tmpRoot = join(repoRoot, ".tmp");
const cliPath = join(repoRoot, "src/cli/main.ts");

function makeTarget(t: TestContext): string {
  mkdirSync(tmpRoot, { recursive: true });
  const target = mkdtempSync(join(tmpRoot, "phase1d-"));
  t.after(() => rmSync(target, { recursive: true, force: true }));
  return target;
}

function writeDefaultConfig(target: string, locale: "zh" | "en" = "zh"): string {
  const configPath = join(target, "dayu.config.yaml");
  writeFileSync(configPath, stringifyDayuConfig(createDefaultDayuConfig(target, locale)), "utf8");
  return configPath;
}

function runCli(args: string[]) {
  return spawnSync(process.execPath, ["--import", "tsx", cliPath, ...args], { cwd: repoRoot, encoding: "utf8" });
}

test("Phase 1d apply dry-run emits deterministic JSON deployment plan", (t) => {
  const target = makeTarget(t);
  const configPath = writeDefaultConfig(target);

  const result = runCli(["apply", "--config", configPath, "--target", target, "--dry-run", "--json"]);

  assert.equal(result.status, 0, result.stderr);
  const report = JSON.parse(result.stdout) as ReturnType<typeof applyDayuConfig>;

  assert.equal(report.command, "apply");
  assert.equal(report.status, "planned");
  assert.deepEqual(report.deploymentOrder, ["core", "git.hooks", "git.commit-format", "ai.execution"]);
  assert.ok(report.fileOperations.some((operation) => operation.dst === "docs/harness/guides/commit-guidelines.md"));
  assert.ok(report.installerOperations.some((operation) => operation.dst === ".husky/commit-msg"));
  assert.equal(report.summary.conflict, 0);

  const second = applyDayuConfig({ configPath, targetRoot: target, dryRun: true });
  assert.deepEqual(
    report.fileOperations.map((operation) => [operation.capabilityId, operation.dst, operation.status]),
    second.fileOperations.map((operation) => [operation.capabilityId, operation.dst, operation.status])
  );
});

test("Phase 1d apply deploys the vertical slice and second apply is no-op", (t) => {
  const target = makeTarget(t);
  const configPath = writeDefaultConfig(target);

  const first = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(first.status, "applied");
  assert.ok(first.changedPaths.includes("commitlint.config.cjs"));
  assert.ok(first.changedPaths.includes(".husky/commit-msg"));
  assert.ok(existsSync(join(target, "AGENTS.md")));
  assert.ok(existsSync(join(target, "docs/harness/guides/ai-execution.md")));
  assert.match(readFileSync(join(target, ".husky/commit-msg"), "utf8"), /dayu-harness:git\.commit-format/);
  assert.match(readFileSync(join(target, "docs/harness/guides/commit-guidelines.md"), "utf8"), /main/);

  const second = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(second.status, "no-op");
  assert.deepEqual(second.changedPaths, []);
  assert.equal(second.summary.conflict, 0);

  const diagnose = diagnoseDayuProject({ configPath, targetRoot: target });
  assert.equal(diagnose.status, "healthy");
  assert.equal(diagnose.summary.missing, 0);
  assert.equal(diagnose.summary.drift, 0);

  const validate = validateDayuProject({ configPath, targetRoot: target });
  assert.equal(validate.status, "valid");
  assert.deepEqual(validate.deployment.order, ["core", "git.hooks", "git.commit-format", "ai.execution"]);
});

test("Phase 1d apply reports conflicting files without overwriting them", (t) => {
  const target = makeTarget(t);
  const configPath = writeDefaultConfig(target);
  writeFileSync(join(target, "AGENTS.md"), "existing project instructions\n", "utf8");

  const report = applyDayuConfig({ configPath, targetRoot: target });

  assert.equal(report.status, "conflict");
  assert.deepEqual(report.changedPaths, []);
  assert.equal(readFileSync(join(target, "AGENTS.md"), "utf8"), "existing project instructions\n");
  assert.equal(existsSync(join(target, "docs/harness/maintenance.md")), false);

  const merge = planDayuMerge({ configPath, targetRoot: target });
  assert.equal(merge.status, "conflict");
  assert.equal(merge.capabilities.find((capability) => capability.capabilityId === "core")?.recommendation, "review");
});

test("Phase 1d apply reports missing template sources without writing partial output", (t) => {
  const target = makeTarget(t);
  const configPath = writeDefaultConfig(target);
  const skillRoot = mkdtempSync(join(tmpRoot, "phase1d-skill-"));
  const originalSkillRoot = process.env.DAYU_HARNESS_SKILL_ROOT;
  const originalNodeEnv = process.env.NODE_ENV;
  for (const entry of ["assets", "capabilities", "locales", "scripts", "templates", "templates.en", "package.json"]) {
    cpSync(join(repoRoot, entry), join(skillRoot, entry), { recursive: true });
  }
  rmSync(join(skillRoot, "templates", "AGENTS.md"));
  process.env.NODE_ENV = "test";
  process.env.DAYU_HARNESS_SKILL_ROOT = skillRoot;
  t.after(() => {
    if (originalSkillRoot === undefined) {
      delete process.env.DAYU_HARNESS_SKILL_ROOT;
    } else {
      process.env.DAYU_HARNESS_SKILL_ROOT = originalSkillRoot;
    }
    if (originalNodeEnv === undefined) {
      delete process.env.NODE_ENV;
    } else {
      process.env.NODE_ENV = originalNodeEnv;
    }
    rmSync(skillRoot, { recursive: true, force: true });
  });

  const report = applyDayuConfig({ configPath, targetRoot: target });

  assert.equal(report.status, "error");
  assert.equal(report.summary.missingSource, 1);
  assert.deepEqual(report.changedPaths, []);
  assert.equal(existsSync(join(target, "CLAUDE.md")), false);
  assert.equal(existsSync(join(target, "AGENTS.md")), false);
});

test("Phase 1d init roundtrip creates config that apply can consume", (t) => {
  const target = makeTarget(t);
  const dryRun = initDayuConfig({ targetRoot: target, dryRun: true, locale: "en" });

  assert.equal(dryRun.configOperation, "create");
  assert.equal(dryRun.apply.status, "planned");
  assert.equal(existsSync(join(target, "dayu.config.yaml")), false);

  const applied = initDayuConfig({ targetRoot: target, locale: "en", dryRun: false });
  assert.equal(applied.status, "applied");
  assert.equal(existsSync(join(target, "dayu.config.yaml")), true);

  const config = readFileSync(join(target, "dayu.config.yaml"), "utf8");
  assert.match(config, /locale: en/);
  assert.match(readFileSync(join(target, "docs/harness/guides/ai-execution.md"), "utf8"), /AI Execution Protocol/);
});

test("Phase 1d init infers target root from --config and existing project.root", (t) => {
  const target = makeTarget(t);
  const configPath = join(target, "dayu.config.yaml");
  const missingConfig = runCli(["init", "--config", configPath, "--dry-run", "--json"]);

  assert.equal(missingConfig.status, 0, missingConfig.stderr);
  const missingReport = JSON.parse(missingConfig.stdout) as ReturnType<typeof initDayuConfig>;
  assert.equal(missingReport.targetRoot, target);
  assert.equal(missingReport.apply.targetRoot, target);
  assert.equal(existsSync(configPath), false);

  const workspace = makeTarget(t);
  const configDir = join(workspace, "config");
  const projectRoot = join(workspace, "actual-project");
  mkdirSync(configDir, { recursive: true });
  mkdirSync(projectRoot, { recursive: true });
  const externalConfigPath = join(configDir, "dayu.config.yaml");
  writeFileSync(
    externalConfigPath,
    [
      'schemaVersion: "1.0.0"',
      "locale: zh",
      "project:",
      "  root: ../actual-project",
      "capabilities:",
      "  - id: core",
      ""
    ].join("\n"),
    "utf8"
  );

  const existingConfig = runCli(["init", "--config", externalConfigPath, "--dry-run", "--json"]);

  assert.equal(existingConfig.status, 0, existingConfig.stderr);
  const existingReport = JSON.parse(existingConfig.stdout) as ReturnType<typeof initDayuConfig>;
  assert.equal(existingReport.targetRoot, projectRoot);
  assert.equal(existingReport.apply.targetRoot, projectRoot);
  assert.equal(existingReport.configOperation, "skip");
});

test("Phase 1d apply preserves external default config path when project.root points elsewhere", (t) => {
  const workspace = makeTarget(t);
  const configDir = join(workspace, "config");
  const projectRoot = join(workspace, "actual-project");
  mkdirSync(configDir, { recursive: true });
  mkdirSync(projectRoot, { recursive: true });
  const configPath = join(configDir, "dayu.config.yaml");
  writeFileSync(
    configPath,
    [
      'schemaVersion: "1.0.0"',
      "locale: zh",
      "project:",
      "  root: ../actual-project",
      "capabilities:",
      "  - id: core",
      ""
    ].join("\n"),
    "utf8"
  );

  const result = spawnSync(process.execPath, ["--import", "tsx", cliPath, "apply", "--dry-run", "--json"], {
    cwd: configDir,
    encoding: "utf8"
  });

  assert.equal(result.status, 0, result.stderr);
  const report = JSON.parse(result.stdout) as ReturnType<typeof applyDayuConfig>;
  assert.equal(report.targetRoot, projectRoot);
  assert.equal(report.configPath, configPath);
});

test("Phase 1d generate previews requested capability content", (t) => {
  const target = makeTarget(t);
  const configPath = writeDefaultConfig(target);

  const report = generateDayuContent({ configPath, targetRoot: target, capabilityId: "ai.execution" });

  assert.equal(report.status, "generated");
  assert.deepEqual(report.deploymentOrder, ["ai.execution"]);
  assert.deepEqual(
    report.files.map((file) => file.dst),
    ["docs/harness/guides/ai-execution.md"]
  );
  assert.match(report.files[0]?.content ?? "", /AI 执行规约/);
});

test("Phase 1d CLI JSON entrypoints cover public diagnose and validate commands", (t) => {
  const target = makeTarget(t);
  const configPath = writeDefaultConfig(target);
  const apply = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(apply.status, "applied");

  for (const command of ["diagnose", "validate"] as const) {
    const result = runCli([command, "--config", configPath, "--target", target, "--json"]);
    assert.equal(result.status, 0, `${command}: ${result.stderr}`);
    const report = JSON.parse(result.stdout) as { command: string };
    assert.equal(report.command, command);
  }
});

test("Phase 1d apply repairs missing executable bits on managed scripts", (t) => {
  const target = makeTarget(t);
  const configPath = writeDefaultConfig(target);
  const first = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(first.status, "applied");

  const validateScript = join(target, "docs/harness/sensors/scripts/validate.sh");
  chmodSync(validateScript, 0o644);

  const unhealthy = diagnoseDayuProject({ configPath, targetRoot: target });
  assert.equal(unhealthy.status, "unhealthy");
  assert.equal(unhealthy.summary.wrongMode, 1);

  const invalid = validateDayuProject({ configPath, targetRoot: target });
  assert.equal(invalid.status, "invalid");
  assert.ok(invalid.issues.some((issue) => issue.includes("validate.sh: chmod")));

  const repaired = applyDayuConfig({ configPath, targetRoot: target });
  assert.equal(repaired.status, "applied");
  assert.ok(repaired.changedPaths.includes("docs/harness/sensors/scripts/validate.sh"));
  assert.ok((statSync(validateScript).mode & 0o111) !== 0);

  const healthy = diagnoseDayuProject({ configPath, targetRoot: target });
  assert.equal(healthy.status, "healthy");
  assert.equal(healthy.summary.wrongMode, 0);
});

test("Phase 1d apply can recover from a partially present managed file", (t) => {
  const target = makeTarget(t);
  const configPath = writeDefaultConfig(target);
  writeFileSync(join(target, "commitlint.config.cjs"), readFileSync(join(repoRoot, "assets/commitlint/commitlint.config.cjs")));

  const report = applyDayuConfig({ configPath, targetRoot: target });

  assert.equal(report.status, "applied");
  assert.ok(!report.changedPaths.includes("commitlint.config.cjs"));
  assert.ok(report.changedPaths.includes("docs/harness/guides/commit-guidelines.md"));
  assert.ok(report.changedPaths.includes(".husky/commit-msg"));
});
