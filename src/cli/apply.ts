import { execFileSync } from "node:child_process";
import { appendFileSync, chmodSync, existsSync, mkdirSync, readFileSync, statSync, unlinkSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

import { resolveDeploymentOrder } from "../architecture/index.js";
import type { CapabilityId, DayuConfig, FileMapping, ManifestV2 } from "../schemas/index.js";
import { createDefaultDayuConfig, enabledCapabilityIds, readDayuConfig, writeDayuConfig } from "./config.js";
import { capabilityDisplay } from "./display.js";
import { CliError } from "./errors.js";
import { writeFileAtomically } from "./filesystem.js";
import { applyGitignoreInstaller, gitignoreAlreadyManaged } from "./installers/gitignore.js";
import { applyHuskyInstaller, canMergeHuskyHook, huskyHookForCapability, huskyMarker } from "./installers/husky.js";
import {
  acquireApplyLock,
  appendJournalEntry,
  capturePreimage,
  createTransactionId,
  journalPath,
  managedPathsFile,
  readManagedPaths,
  recoverInterruptedTransactions,
  rollbackPaths,
  writeManagedPaths,
  type JournalEntry
} from "./journal.js";
import { assertConfigCapabilitiesKnown, loadManifestRegistry } from "./manifest-registry.js";
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

const DAYU_LOG_FILE = ".dayu-harness/log.jsonl";
const SUPPORTED_INSTALLERS = new Set(["husky", "gitignore"]);

interface ResolvedApplyInputs {
  targetRoot: string;
  configPath: string;
  config: DayuConfig;
  registry: ManifestRegistry;
}

export function buildApplyPlan(options: ApplyOptions = {}): ApplyPlan {
  const inputs = resolveApplyInputs(options);
  const enabledCapabilities = enabledCapabilityIds(inputs.config);

  assertConfigCapabilitiesKnown(inputs.config, inputs.registry);

  const requestedCapabilities = resolveRequestedCapabilities(enabledCapabilities, options.onlyCapabilityId);
  const deploymentOrder = resolveDeploymentOrder(
    inputs.registry.manifests,
    requestedCapabilities
  ) as CapabilityId[];
  const fullDeploymentOrder = resolveDeploymentOrder(inputs.registry.manifests, enabledCapabilities) as CapabilityId[];
  const context = createRenderContext(inputs.targetRoot, inputs.config, inputs.registry);
  const capabilitySummaries = deploymentOrder.map((capabilityId) =>
    capabilityDisplay(capabilityId, inputs.registry, context.localeCatalog)
  );
  const fileOperations: FileOperation[] = [];

  for (const manifest of manifestsInOrder(inputs.registry, deploymentOrder)) {
    for (const item of manifestFileMappings(manifest, context)) {
      fileOperations.push(planFileOperation(item, options.force ?? false));
    }
  }

  const installerOperations = manifestsInOrder(inputs.registry, deploymentOrder).flatMap((manifest) =>
    planInstallerOperation(manifest, inputs.registry, inputs.targetRoot, options.force ?? false)
  );
  const desiredManagedPaths = desiredManagedPathsForOrder(inputs.registry, fullDeploymentOrder, context, inputs.targetRoot, options.force ?? false);
  const plannedManagedPaths = uniqueSorted([
    ...fileOperations.map((operation) => operation.dst),
    ...installerOperations.map((operation) => operation.dst)
  ]);
  const existingManagedPaths = readManagedPaths(inputs.targetRoot, { migrate: !options.dryRun });
  const orphanPaths = existingManagedPaths.filter((managedPath) => !desiredManagedPaths.includes(managedPath));

  if (options.pruneOrphans) {
    for (const orphanPath of orphanPaths) {
      fileOperations.push({
        capabilityId: "core",
        kind: "asset",
        src: "",
        dst: orphanPath,
        status: "delete",
        executable: false,
        reason: "previously managed path is no longer in the active deployment plan"
      });
    }
  }

  const managedPaths = uniqueSorted([
    ...existingManagedPaths.filter((managedPath) => desiredManagedPaths.includes(managedPath)),
    ...plannedManagedPaths,
    managedPathsFile(),
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
    capabilitySummaries,
    fileOperations,
    installerOperations,
    managedPaths,
    orphanPaths,
    summary: summarizePlan(fileOperations, installerOperations)
  };
}

export function applyDayuConfig(options: ApplyOptions = {}): ApplyReport {
  let lock: ReturnType<typeof acquireApplyLock> | undefined;
  if (!options.dryRun) {
    const inputs = resolveApplyInputs(options);
    lock = acquireApplyLock(inputs.targetRoot);
    recoverInterruptedTransactions(inputs.targetRoot);
  }

  let plan: ApplyPlan;
  try {
    plan = buildApplyPlan(options);
  } catch (error) {
    lock?.release();
    throw error;
  }
  const blockingStatus = blockingApplyStatus(plan);

  if (plan.dryRun || blockingStatus) {
    lock?.release();
    return {
      ...plan,
      status: blockingStatus ?? "planned",
      changedPaths: []
    };
  }

  const transactionId = createTransactionId();
  const changedPaths: string[] = [];
  const preimages = new Map<string, JournalEntry>();

  try {
    appendJournalEntry(plan.targetRoot, {
      id: transactionId,
      command: "apply",
      phase: "begin",
      detail: {
        deploymentOrder: plan.deploymentOrder,
        force: options.force ?? false,
        pruneOrphans: options.pruneOrphans ?? false
      }
    });

    for (const operation of plan.fileOperations) {
      if (!["create", "overwrite", "chmod", "delete"].includes(operation.status)) {
        continue;
      }

      const targetPath = resolveInsideRoot(plan.targetRoot, operation.dst);
      rememberPreimage(plan.targetRoot, transactionId, operation.dst, preimages);
      if (operation.status === "delete") {
        if (existsSync(targetPath)) {
          unlinkSync(targetPath);
        }
      } else {
        if (operation.status === "create" || operation.status === "overwrite") {
          const rendered = renderFileByPlan(plan, operation);
          mkdirSync(dirname(targetPath), { recursive: true });
          writeFileAtomically(targetPath, rendered.content);
        }
        if (operation.executable) {
          chmodSync(targetPath, 0o755);
        }
      }
      changedPaths.push(operation.dst);
      appendJournalEntry(plan.targetRoot, {
        id: transactionId,
        command: "apply",
        phase: "write",
        path: operation.dst,
        checksum: capturePreimage(plan.targetRoot, operation.dst).checksum
      });
    }

    for (const operation of plan.installerOperations) {
      if (operation.status !== "create" && operation.status !== "merge") {
        continue;
      }

      rememberPreimage(plan.targetRoot, transactionId, operation.dst, preimages);
      applyInstallerOperation(plan.targetRoot, operation);
      changedPaths.push(operation.dst);
      appendJournalEntry(plan.targetRoot, {
        id: transactionId,
        command: "apply",
        phase: "write",
        path: operation.dst,
        checksum: capturePreimage(plan.targetRoot, operation.dst).checksum
      });
    }

    writeManagedPaths(plan.targetRoot, plan.managedPaths.filter((managedPath) => managedPath !== DAYU_LOG_FILE));

    if (changedPaths.length > 0) {
      appendDayuLog(plan.targetRoot, {
        command: "apply",
        status: "applied",
        changedPaths,
        deploymentOrder: plan.deploymentOrder,
        timestamp: new Date().toISOString()
      });
    }

    appendJournalEntry(plan.targetRoot, {
      id: transactionId,
      command: "apply",
      phase: "commit",
      detail: {
        changedPaths
      }
    });

    return {
      ...plan,
      status: changedPaths.length > 0 ? "applied" : "no-op",
      changedPaths: uniqueSorted(changedPaths)
    };
  } catch (error) {
    rollbackPaths(plan.targetRoot, transactionId, preimages);
    throw error;
  } finally {
    lock?.release();
  }
}

export function initDayuConfig(options: InitOptions = {}): InitReport {
  const explicitConfigPath = options.configPath ? resolve(options.configPath) : undefined;
  const seedTargetRoot = options.targetRoot
    ? resolveTargetRoot(options.targetRoot)
    : explicitConfigPath
      ? dirname(explicitConfigPath)
      : resolveTargetRoot();
  const configPath = explicitConfigPath ?? resolveConfigPath(seedTargetRoot);
  const dryRun = options.dryRun ?? true;
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
    dryRun,
    force: options.force,
    pruneOrphans: options.pruneOrphans
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
  const registry = loadManifestRegistry();

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

function desiredManagedPathsForOrder(
  registry: ManifestRegistry,
  order: readonly CapabilityId[],
  context: RenderContext,
  targetRoot: string,
  force: boolean
): string[] {
  const filePaths = manifestsInOrder(registry, order)
    .flatMap((manifest) => manifestFileMappings(manifest, context))
    .map((item) => item.mapping.dst);
  const installerPaths = manifestsInOrder(registry, order)
    .flatMap((manifest) => planInstallerOperation(manifest, registry, targetRoot, force))
    .map((operation) => operation.dst);
  return uniqueSorted([...filePaths, ...installerPaths, managedPathsFile()]);
}

function resolveRequestedCapabilities(
  enabledCapabilities: readonly CapabilityId[],
  onlyCapabilityId?: string
): CapabilityId[] {
  if (!onlyCapabilityId) {
    return [...enabledCapabilities];
  }

  if (!enabledCapabilities.includes(onlyCapabilityId as CapabilityId)) {
    throw new CliError(
      "capability-not-enabled",
      `capability '${onlyCapabilityId}' is not enabled in dayu.config.yaml`,
      [
        {
          code: "capability-not-enabled",
          message: `add '${onlyCapabilityId}' to dayu.config.yaml before using --only`,
          path: "capabilities"
        }
      ]
    );
  }

  return [onlyCapabilityId as CapabilityId];
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

function planFileOperation(item: RenderedFileMapping, force: boolean): FileOperation {
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

  if (force) {
    return {
      capabilityId: item.capabilityId,
      kind: item.kind,
      src: item.mapping.src,
      dst: item.mapping.dst,
      status: "overwrite",
      executable,
      reason: "target exists with different content; --force will overwrite it",
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
    reason: "target exists with different content; use --force or merge --apply --strategy replace to overwrite"
  };
}

function planInstallerOperation(
  manifest: ManifestV2,
  registry: ManifestRegistry,
  targetRoot: string,
  force: boolean
): InstallerOperation[] {
  if (!manifest.installer) {
    return [];
  }

  if (!SUPPORTED_INSTALLERS.has(manifest.installer.script)) {
    return [
      {
        capabilityId: manifest.id,
        script: manifest.installer.script,
        dst: ".dayu-installer",
        status: "unsupported",
        reason: `unsupported installer '${manifest.installer.script}'`
      }
    ];
  }

  const dst = installerDestination(manifest);
  const targetPath = join(targetRoot, dst);
  if (!existsSync(targetPath)) {
    return [
      {
        capabilityId: manifest.id,
        script: manifest.installer.script,
        dst,
        status: "create",
        strategy: installerStrategy(manifest, force)
      }
    ];
  }

  if (
    manifest.installer.script === "gitignore" &&
    !force &&
    gitignoreAlreadyManaged(targetRoot)
  ) {
    return [
      {
        capabilityId: manifest.id,
        script: manifest.installer.script,
        dst,
        status: "skip",
        reason: ".gitignore already contains the dayu-harness local exclusions"
      }
    ];
  }

  if (manifest.installer.script === "husky" && readFileSync(targetPath, "utf8").includes(huskyMarker(manifest.id))) {
    return [
      {
        capabilityId: manifest.id,
        script: manifest.installer.script,
        dst,
        status: "skip",
        reason: `${dst} already contains the dayu-harness ${manifest.id} snippet`
      }
    ];
  }

  if (manifest.installer.script === "husky" && !force && !canMergeHuskyHook(targetPath)) {
    return [
      {
        capabilityId: manifest.id,
        script: manifest.installer.script,
        dst,
        status: "unsupported",
        reason: `existing ${dst} is not a Node hook; use --force to replace it`
      }
    ];
  }

  return [
    {
      capabilityId: manifest.id,
      script: manifest.installer.script,
      dst,
      status: "merge",
      strategy: installerStrategy(manifest, force),
      reason: force
        ? `existing ${dst} will be replaced or force-merged according to installer support`
        : `existing ${dst} will be preserved and the dayu-harness snippet appended`
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
  if (!SUPPORTED_INSTALLERS.has(operation.script)) {
    throw new CliError("unsupported-installer", `unsupported installer '${operation.script}'`);
  }

  const registry = loadManifestRegistry();
  if (operation.script === "gitignore") {
    applyGitignoreInstaller({
      targetRoot,
      skillRoot: registry.skillRoot,
      strategy: operation.strategy ?? "merge"
    });
  } else {
    applyHuskyInstaller({
      targetRoot,
      capabilityId: operation.capabilityId,
      defaultBranch: detectDefaultBranch(targetRoot),
      strategy: operation.strategy ?? "merge"
    });
  }

  const hookPath = join(targetRoot, operation.dst);
  if (!existsSync(hookPath)) {
    throw new CliError("installer-failed", `installer '${operation.script}' did not create ${operation.dst}`);
  }
  if (operation.script === "husky" && !readFileSync(hookPath, "utf8").includes(huskyMarker(operation.capabilityId))) {
    throw new CliError("installer-failed", `installer '${operation.script}' did not create ${operation.dst}`);
  }
}

function installerStrategy(manifest: ManifestV2, force: boolean): "merge" | "replace" {
  if (force && manifest.installer?.safe_strategies.includes("replace")) {
    return "replace";
  }

  return "merge";
}

function installerDestination(manifest: ManifestV2): string {
  if (manifest.installer?.script === "gitignore") {
    return ".gitignore";
  }

  if (manifest.installer?.script === "husky") {
    const hook = huskyHookForCapability(manifest.id);
    return hook ? `.husky/${hook}` : ".husky";
  }

  return ".dayu-installer";
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

function rememberPreimage(
  targetRoot: string,
  transactionId: string,
  relativePath: string,
  preimages: Map<string, JournalEntry>
): void {
  if (preimages.has(relativePath)) {
    return;
  }

  const preimage = {
    id: transactionId,
    command: "apply",
    phase: "preimage" as const,
    path: relativePath,
    ...capturePreimage(targetRoot, relativePath)
  };
  preimages.set(relativePath, {
    ...preimage,
    timestamp: new Date().toISOString()
  });
  appendJournalEntry(targetRoot, preimage);
}

function summarizePlan(fileOperations: readonly FileOperation[], installerOperations: readonly InstallerOperation[]) {
  return {
    create:
      fileOperations.filter((operation) => operation.status === "create").length +
      installerOperations.filter((operation) => operation.status === "create").length,
    overwrite: fileOperations.filter((operation) => operation.status === "overwrite").length,
    delete: fileOperations.filter((operation) => operation.status === "delete").length,
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
