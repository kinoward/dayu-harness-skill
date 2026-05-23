import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  ARCHITECTURE_LAYERS,
  CLI_COMMAND_TREE,
  DependencyGraphError,
  assertLayerDependency,
  buildCapabilityDependencyModel,
  canLayerDependOn,
  getCliCommandSpec,
  resolveDeploymentOrder
} from "../../src/architecture/index.js";
import { ManifestV2Schema, type CapabilityId, type ManifestV2 } from "../../src/schemas/index.js";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));
const phase1cCapabilityIds = ["core", "git.hooks", "git.commit-format", "ai.execution"] as const;

function readJson(relativePath: string): unknown {
  return JSON.parse(readFileSync(join(repoRoot, relativePath), "utf8"));
}

function readManifest(id: (typeof phase1cCapabilityIds)[number]): ManifestV2 {
  return ManifestV2Schema.parse(readJson(`capabilities/${id}.json`));
}

function readTrialManifests(): ManifestV2[] {
  return phase1cCapabilityIds.map((id) => readManifest(id));
}

test("Phase 1c CLI command tree defines the six non-interactive tool commands", () => {
  assert.deepEqual(
    CLI_COMMAND_TREE.map((command) => command.name),
    ["init", "apply", "diagnose", "merge", "validate", "generate"]
  );

  for (const command of CLI_COMMAND_TREE) {
    assert.equal(command.layer, "tool", command.name);
    assert.equal(command.interactive, false, command.name);
    assert.equal(command.supportsJson, true, command.name);
    assert.equal(command.phase1dSlice, true, command.name);
  }

  assert.deepEqual(getCliCommandSpec("init").delegatesTo, ["apply"]);
  assert.equal(getCliCommandSpec("apply").supportsDryRun, true);
});

test("architecture layer contracts preserve frontend, tool, and product separation", () => {
  assert.deepEqual(
    ARCHITECTURE_LAYERS.map((layer) => layer.id),
    ["frontend", "tool", "product"]
  );

  assert.equal(canLayerDependOn("frontend", "tool"), true);
  assert.equal(canLayerDependOn("tool", "product"), true);
  assert.equal(canLayerDependOn("tool", "frontend"), false);
  assert.equal(canLayerDependOn("product", "tool"), false);

  assert.doesNotThrow(() => assertLayerDependency("frontend", "tool"));
  assert.throws(() => assertLayerDependency("product", "tool"), /product layer must not depend on tool layer/);
});

test("deployment graph resolves manifest v2 deployment_deps in prerequisite-first order", () => {
  const manifests = readTrialManifests();
  const expectedOrder = ["core", "git.hooks", "git.commit-format", "ai.execution"];
  const shuffledManifests = [manifests[2], manifests[3], manifests[1], manifests[0]];

  assert.deepEqual(resolveDeploymentOrder(manifests, ["git.commit-format", "ai.execution"]), expectedOrder);
  assert.deepEqual(resolveDeploymentOrder(manifests, ["ai.execution", "git.commit-format"]), expectedOrder);
  assert.deepEqual(resolveDeploymentOrder(shuffledManifests, ["ai.execution", "git.commit-format"]), expectedOrder);
});

test("conceptual dependencies are modeled but do not expand the deployment closure", () => {
  const manifests = readTrialManifests();
  const aiExecution = manifests.find((manifest) => manifest.id === "ai.execution");
  assert.ok(aiExecution);

  const withConceptualDep: ManifestV2[] = manifests.map((manifest) =>
    manifest.id === "ai.execution"
      ? {
          ...manifest,
          conceptual_deps: ["git.commit-format"]
        }
      : manifest
  );
  const model = buildCapabilityDependencyModel(withConceptualDep);

  assert.deepEqual(resolveDeploymentOrder(withConceptualDep, ["ai.execution"]), ["core", "ai.execution"]);
  assert.deepEqual(
    model.conceptual.edges.map((edge) => `${edge.capabilityId}->${edge.dependsOn}`),
    ["ai.execution->git.commit-format"]
  );
});

test("deployment graph reports missing dependencies and cycles with structured issues", () => {
  const manifests = readTrialManifests();
  const core = readManifest("core");
  const gitHooks = readManifest("git.hooks");

  const missingDep: ManifestV2 = {
    ...core,
    deployment_deps: ["missing.capability" as CapabilityId]
  };
  assert.throws(
    () => resolveDeploymentOrder([missingDep], ["core"]),
    (error: unknown) =>
      error instanceof DependencyGraphError &&
      error.issues[0]?.code === "missing-dependency" &&
      /missing deployment dependency/.test(error.message)
  );

  const cycleCore: ManifestV2 = {
    ...core,
    deployment_deps: ["git.hooks"]
  };
  const cycleHooks: ManifestV2 = {
    ...gitHooks,
    deployment_deps: ["core"]
  };

  assert.throws(
    () => resolveDeploymentOrder([...manifests.filter((manifest) => !["core", "git.hooks"].includes(manifest.id)), cycleCore, cycleHooks], ["git.hooks"]),
    (error: unknown) =>
      error instanceof DependencyGraphError &&
      error.issues.some((issue) => issue.code === "cycle") &&
      /deployment dependency cycle detected/.test(error.message)
  );

  assert.throws(
    () => buildCapabilityDependencyModel([cycleCore, cycleHooks]),
    (error: unknown) =>
      error instanceof DependencyGraphError &&
      error.issues.some((issue) => issue.code === "cycle") &&
      /deployment dependency cycle detected/.test(error.message)
  );
});
