import { execFileSync } from "node:child_process";
import { appendFileSync, chmodSync, existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

import { resolveDeploymentOrder } from "../architecture/index.js";
import type { CapabilityId, DayuConfig, FileMapping, ManifestV2 } from "../schemas/index.js";
import { createDefaultDayuConfig, enabledCapabilityIds, readDayuConfig, writeDayuConfig } from "./config.js";
import { CliError } from "./errors.js";
import { assertConfigCapabilitiesKnown, loadPhase1dManifestRegistry } from "./manifest-registry.js";
import {
  DEFAULT_CONFIG_FILE,
  fileExists,
  resolveConfigPath,
  resolveInsideRoot,
  resolveProjectRootFromConfig,
  resolveTargetRoot
} from "./paths.js";
import { loadLocaleCatalog, renderFileMapping, templateMappingsForLocale } from "./render.js";
import type {
  ApplyOptions,
  ApplyPlan,
  ApplyReport,
  FileOperation,
  InitOptions,
  InitReport,
  InstallerOperation,
  ManifestRegistry,
  RenderContext,
  RenderedFileMapping
} from "./types.js";

const DAYU_LOG_FILE = ".dayu-log.jsonl";
const COMMIT_FORMAT_HOOK_MARKER = "# >>> dayu-harness:git.commit-format >>>";

interface ResolvedApplyInputs {
  targetRoot: string;
  configPath: string;
  config: DayuConfig;
  registry: ManifestRegistry;
}

export function buildApplyPlan(options: ApplyOptions = {}): ApplyPlan {
  const inputs = resolveApplyInputs(options);
  const requestedCapabilities = enabledCapabilityIds(inputs.config);

  assertConfigCapabilitiesKnown(inputs.config, inputs.registry);

  const deploymentOrder = resolveDeploymentOrder(
    inputs.registry.manifests,
    requestedCapabilities
  ) as CapabilityId[];
  const context = createRenderContext(inputs.targetRoot, inputs.config, inputs.registry);
  const fileOperations: FileOperation[] = [];

  for (const manifest of manifestsInOrder(inputs.registry, deploymentOrder)) {
    for (const item of manifestFileMappings(manifest, context)) {
      fileOperations.push(planFileOperation(item));
    }
  }

  const installerOperations = manifestsInOrder(inputs.registry, deploymentOrder).flatMap((manifest) =>
    planInstallerOperation(manifest, inputs.registry, inputs.targetRoot)
  );
  const managedPaths = uniqueSorted([
    ...fileOperations.map((operation) => operation.dst),
    ...installerOperations.map((operation) => operation.dst),
    DAYU_LOG_FILE
  ]);

  return {
    command: "apply",
    dryRun: options.dryRun ?? false,
    targetRoot: inputs.targetRoot,
    configPath: inputs.configPath,
    locale: inputs.config.locale,
    requestedCapabilities,
    deploymentOrder,
    capabilities: deploymentOrder,
    fileOperations,
    installerOperations,
    managedPaths,
    summary: summarizePlan(fileOperations, installerOperations)
  };
}

export function applyDayuConfig(options: ApplyOptions = {}): ApplyReport {
  const plan = buildApplyPlan(options);
  const blockingStatus = blockingApplyStatus(plan);

  if (plan.dryRun || blockingStatus) {
    return {
      ...plan,
      status: blockingStatus ?? "planned",
      changedPaths: []
    };
  }

  const changedPaths: string[] = [];

  for (const operation of plan.fileOperations) {
    if (operation.status !== "create" && operation.status !== "chmod") {
      continue;
    }

    const targetPath = resolveInsideRoot(plan.targetRoot, operation.dst);
    if (operation.status === "create") {
      const rendered = renderFileByPlan(plan, operation);
      mkdirSync(dirname(targetPath), { recursive: true });
      writeFileSync(targetPath, rendered.content);
    }
    if (operation.executable) {
      chmodSync(targetPath, 0o755);
    }
    changedPaths.push(operation.dst);
  }

  for (const operation of plan.installerOperations) {
    if (operation.status !== "create" && operation.status !== "merge") {
      continue;
    }

    applyInstallerOperation(plan.targetRoot, operation);
    changedPaths.push(operation.dst);
  }

  if (changedPaths.length > 0) {
    appendDayuLog(plan.targetRoot, {
      command: "apply",
      status: "applied",
      changedPaths,
      deploymentOrder: plan.deploymentOrder,
      timestamp: new Date().toISOString()
    });
  }

  return {
    ...plan,
    status: changedPaths.length > 0 ? "applied" : "no-op",
    changedPaths: uniqueSorted(changedPaths)
  };
}

export function initDayuConfig(options: InitOptions = {}): InitReport {
  const explicitConfigPath = options.configPath ? resolve(options.configPath) : undefined;
  const seedTargetRoot = options.targetRoot
    ? resolveTargetRoot(options.targetRoot)
    : explicitConfigPath
      ? dirname(explicitConfigPath)
      : resolveTargetRoot();
  const configPath = explicitConfigPath ?? resolveConfigPath(seedTargetRoot);
  const dryRun = options.dryRun ?? false;
  const configExists = fileExists(configPath);
  const config = configExists ? readDayuConfig(configPath) : createDefaultDayuConfig(seedTargetRoot, options.locale ?? "zh");
  const targetRoot = options.targetRoot
    ? seedTargetRoot
    : (resolveProjectRootFromConfig(configPath, config.project?.root) ?? seedTargetRoot);

  if (!configExists && !dryRun) {
    mkdirSync(dirname(configPath), { recursive: true });
    writeDayuConfig(configPath, config);
  }

  const apply = applyDayuConfig({
    targetRoot: options.targetRoot ? targetRoot : undefined,
    configPath,
    config,
    dryRun
  });

  return {
    command: "init",
    status: apply.status,
    dryRun,
    targetRoot,
    configPath,
    configOperation: configExists ? "skip" : "create",
    apply
  };
}

export function resolveApplyInputs(options: ApplyOptions = {}): ResolvedApplyInputs {
  const explicitConfigPath = options.configPath ? resolve(options.configPath) : undefined;
  const initialTargetRoot = options.targetRoot
    ? resolveTargetRoot(options.targetRoot)
    : explicitConfigPath
      ? dirname(explicitConfigPath)
      : resolveTargetRoot();
  const initialConfigPath = explicitConfigPath ?? join(initialTargetRoot, DEFAULT_CONFIG_FILE);
  const config = options.config ?? readDayuConfig(initialConfigPath);
  const configuredRoot = options.targetRoot ? undefined : resolveProjectRootFromConfig(initialConfigPath, config.project?.root);
  const targetRoot = configuredRoot ?? initialTargetRoot;
  const configPath = initialConfigPath;
  const registry = loadPhase1dManifestRegistry();

  return { targetRoot, configPath, config, registry };
}

export function createRenderContext(targetRoot: string, config: DayuConfig, registry: ManifestRegistry): RenderContext {
  return {
    locale: config.locale,
    skillRoot: registry.skillRoot,
    targetRoot,
    defaultBranch: detectDefaultBranch(targetRoot),
    projectVersion: readPackageVersion(registry.skillRoot),
    localeCatalog: loadLocaleCatalog(registry.skillRoot, config.locale)
  };
}

function manifestsInOrder(registry: ManifestRegistry, order: readonly CapabilityId[]): ManifestV2[] {
  return order.map((capabilityId) => {
    const manifest = registry.manifestById.get(capabilityId);
    if (!manifest) {
      throw new CliError("unknown-capability", `capability '${capabilityId}' is not loaded`);
    }
    return manifest;
  });
}

function manifestFileMappings(manifest: ManifestV2, context: RenderContext): RenderedFileMapping[] {
  const mappings: Array<{ kind: "template" | "asset"; mapping: FileMapping }> = [
    ...templateMappingsForLocale(manifest, context.locale, context.skillRoot).map((mapping) => ({
      kind: "template" as const,
      mapping
    })),
    ...manifest.asset_files.map((mapping) => ({
      kind: "asset" as const,
      mapping
    }))
  ];

  return mappings.map(({ kind, mapping }) => {
    const sourcePath = resolveInsideRoot(context.skillRoot, mapping.src);
    const targetPath = resolveInsideRoot(context.targetRoot, mapping.dst);

    if (!existsSync(sourcePath)) {
      return {
        capabilityId: manifest.id,
        kind,
        mapping,
        sourcePath,
        targetPath,
        content: Buffer.alloc(0)
      };
    }

    return renderFileMapping(manifest.id, kind, mapping, context);
  });
}

function planFileOperation(item: RenderedFileMapping): FileOperation {
  const executable = item.mapping.executable ?? false;

  if (!existsSync(item.sourcePath)) {
    return {
      capabilityId: item.capabilityId,
      kind: item.kind,
      src: item.mapping.src,
      dst: item.mapping.dst,
      status: "missing-source",
      executable,
      reason: `source file '${item.mapping.src}' does not exist`
    };
  }

  if (!existsSync(item.targetPath)) {
    return {
      capabilityId: item.capabilityId,
      kind: item.kind,
      src: item.mapping.src,
      dst: item.mapping.dst,
      status: "create",
      executable,
      bytes: item.content.byteLength
    };
  }

  const existing = readFileSync(item.targetPath);
  if (existing.equals(item.content)) {
    if (executable && !hasAnyExecuteBit(item.targetPath)) {
      return {
        capabilityId: item.capabilityId,
        kind: item.kind,
        src: item.mapping.src,
        dst: item.mapping.dst,
        status: "chmod",
        executable,
        reason: "target content matches but executable bit is missing",
        bytes: item.content.byteLength
      };
    }

    return {
      capabilityId: item.capabilityId,
      kind: item.kind,
      src: item.mapping.src,
      dst: item.mapping.dst,
      status: "skip",
      executable,
      reason: "target already matches rendered content",
      bytes: item.content.byteLength
    };
  }

  return {
    capabilityId: item.capabilityId,
    kind: item.kind,
    src: item.mapping.src,
    dst: item.mapping.dst,
    status: "conflict",
    executable,
    reason: "target exists with different content; Phase 1d does not overwrite"
  };
}

function planInstallerOperation(
  manifest: ManifestV2,
  registry: ManifestRegistry,
  targetRoot: string
): InstallerOperation[] {
  if (!manifest.installer) {
    return [];
  }

  if (manifest.installer.script !== "install-husky.sh") {
    return [
      {
        capabilityId: manifest.id,
        script: manifest.installer.script,
        dst: ".dayu-installer",
        status: "unsupported",
        reason: `unsupported Phase 1d installer '${manifest.installer.script}'`
      }
    ];
  }

  const scriptPath = join(registry.skillRoot, "scripts", manifest.installer.script);
  if (!existsSync(scriptPath)) {
    return [
      {
        capabilityId: manifest.id,
        script: manifest.installer.script,
        dst: ".husky/commit-msg",
        status: "missing-source",
        reason: `installer script '${manifest.installer.script}' does not exist`
      }
    ];
  }

  const hookPath = join(targetRoot, ".husky", "commit-msg");
  if (!existsSync(hookPath)) {
    return [
      {
        capabilityId: manifest.id,
        script: manifest.installer.script,
        dst: ".husky/commit-msg",
        status: "create"
      }
    ];
  }

  const hook = readFileSync(hookPath, "utf8");
  if (hook.includes(COMMIT_FORMAT_HOOK_MARKER)) {
    return [
      {
        capabilityId: manifest.id,
        script: manifest.installer.script,
        dst: ".husky/commit-msg",
        status: "skip",
        reason: "commit-msg hook already contains the dayu-harness commit-format snippet"
      }
    ];
  }

  return [
    {
      capabilityId: manifest.id,
      script: manifest.installer.script,
      dst: ".husky/commit-msg",
      status: "merge",
      reason: "existing hook will be preserved and the dayu-harness snippet appended"
    }
  ];
}

function renderFileByPlan(plan: ApplyPlan, operation: FileOperation): RenderedFileMapping {
  const inputs = resolveApplyInputs({ targetRoot: plan.targetRoot, configPath: plan.configPath });
  const manifest = inputs.registry.manifestById.get(operation.capabilityId);
  if (!manifest) {
    throw new CliError("unknown-capability", `capability '${operation.capabilityId}' is not loaded`);
  }

  const context = createRenderContext(plan.targetRoot, inputs.config, inputs.registry);
  const mapping = [...templateMappingsForLocale(manifest, context.locale, context.skillRoot), ...manifest.asset_files].find(
    (candidate) => candidate.dst === operation.dst && candidate.src === operation.src
  );

  if (!mapping) {
    throw new CliError("operation-not-found", `file operation '${operation.dst}' is no longer present in manifest`);
  }

  return renderFileMapping(manifest.id, operation.kind, mapping, context);
}

function applyInstallerOperation(targetRoot: string, operation: InstallerOperation): void {
  if (operation.script !== "install-husky.sh") {
    throw new CliError("unsupported-installer", `unsupported installer '${operation.script}'`);
  }

  const scriptPath = join(loadPhase1dManifestRegistry().skillRoot, "scripts", operation.script);
  execFileSync("bash", [scriptPath, targetRoot, "--apply", "merge"], {
    env: {
      ...process.env,
      DAYU_HARNESS_CAPABILITY: operation.capabilityId
    },
    stdio: ["ignore", "pipe", "pipe"]
  });

  const hookPath = join(targetRoot, operation.dst);
  if (!existsSync(hookPath) || !readFileSync(hookPath, "utf8").includes(COMMIT_FORMAT_HOOK_MARKER)) {
    throw new CliError("installer-failed", `installer '${operation.script}' did not create ${operation.dst}`);
  }
}

function blockingApplyStatus(plan: ApplyPlan): "conflict" | "error" | undefined {
  if (plan.summary.missingSource > 0 || plan.summary.unsupported > 0) {
    return "error";
  }

  if (plan.summary.conflict > 0) {
    return "conflict";
  }

  return undefined;
}

function summarizePlan(fileOperations: readonly FileOperation[], installerOperations: readonly InstallerOperation[]) {
  return {
    create:
      fileOperations.filter((operation) => operation.status === "create").length +
      installerOperations.filter((operation) => operation.status === "create").length,
    chmod: fileOperations.filter((operation) => operation.status === "chmod").length,
    merge: installerOperations.filter((operation) => operation.status === "merge").length,
    skip:
      fileOperations.filter((operation) => operation.status === "skip").length +
      installerOperations.filter((operation) => operation.status === "skip").length,
    conflict: fileOperations.filter((operation) => operation.status === "conflict").length,
    missingSource:
      fileOperations.filter((operation) => operation.status === "missing-source").length +
      installerOperations.filter((operation) => operation.status === "missing-source").length,
    unsupported: installerOperations.filter((operation) => operation.status === "unsupported").length
  };
}

function appendDayuLog(targetRoot: string, entry: Record<string, unknown>): void {
  const logPath = join(targetRoot, DAYU_LOG_FILE);
  appendFileSync(logPath, `${JSON.stringify(entry)}\n`, "utf8");
}

function detectDefaultBranch(targetRoot: string): string {
  if (!existsSync(join(targetRoot, ".git"))) {
    return "main";
  }

  try {
    const branch = execFileSync("git", ["-C", targetRoot, "symbolic-ref", "--quiet", "--short", "HEAD"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"]
    }).trim();
    return branch.length > 0 && branch !== "HEAD" ? branch : "main";
  } catch {
    return "main";
  }
}

function readPackageVersion(skillRoot: string): string {
  const packageJson = JSON.parse(readFileSync(join(skillRoot, "package.json"), "utf8")) as { version?: string };
  return packageJson.version ?? "0.0.0";
}

function uniqueSorted(values: Iterable<string>): string[] {
  return [...new Set(values)].sort();
}

function hasAnyExecuteBit(path: string): boolean {
  return (statSync(path).mode & 0o111) !== 0;
}
