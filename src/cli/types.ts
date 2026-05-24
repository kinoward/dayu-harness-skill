import type { DayuConfig, FileMapping, LocaleCode, ManifestV2 } from "../schemas/index.js";

export type CliCommandName =
  | "init"
  | "apply"
  | "diagnose"
  | "validate"
  | "merge"
  | "generate"
  | "status"
  | "repair"
  | "finalize";

export type ApplyStatus = "planned" | "applied" | "no-op" | "conflict" | "error" | "repaired";

export type FileOperationStatus = "create" | "overwrite" | "delete" | "chmod" | "skip" | "conflict" | "missing-source";

export type InstallerOperationStatus = "create" | "merge" | "skip" | "missing-source" | "unsupported";

export interface ManifestRegistry {
  skillRoot: string;
  manifests: readonly ManifestV2[];
  manifestById: ReadonlyMap<string, ManifestV2>;
}

export interface RenderContext {
  locale: LocaleCode;
  skillRoot: string;
  targetRoot: string;
  defaultBranch: string;
  projectVersion: string;
  localeCatalog: Readonly<Record<string, string>>;
}

export interface RenderedFileMapping {
  capabilityId: string;
  kind: "template" | "asset";
  mapping: FileMapping;
  sourcePath: string;
  targetPath: string;
  content: Buffer;
}

export interface FileOperation {
  capabilityId: string;
  kind: "template" | "asset";
  src: string;
  dst: string;
  status: FileOperationStatus;
  executable: boolean;
  reason?: string;
  bytes?: number;
}

export interface InstallerOperation {
  capabilityId: string;
  script: string;
  dst: string;
  status: InstallerOperationStatus;
  strategy?: InstallerStrategy;
  reason?: string;
}

export interface ApplyPlan {
  command: "apply";
  dryRun: boolean;
  targetRoot: string;
  configPath: string;
  locale: LocaleCode;
  requestedCapabilities: readonly string[];
  deploymentOrder: readonly string[];
  capabilities: readonly string[];
  capabilitySummaries: readonly CapabilityDisplaySummary[];
  fileOperations: readonly FileOperation[];
  installerOperations: readonly InstallerOperation[];
  managedPaths: readonly string[];
  orphanPaths: readonly string[];
  summary: {
    create: number;
    overwrite: number;
    delete: number;
    chmod: number;
    merge: number;
    skip: number;
    conflict: number;
    missingSource: number;
    unsupported: number;
  };
}

export interface CapabilityDisplaySummary {
  capabilityId: string;
  displayName: string;
  summary: string;
}

export interface ApplyReport extends ApplyPlan {
  status: ApplyStatus;
  changedPaths: readonly string[];
}

export interface InitReport {
  command: "init";
  status: ApplyStatus;
  dryRun: boolean;
  targetRoot: string;
  configPath: string;
  configOperation: "create" | "skip";
  apply: ApplyReport;
}

export interface DiagnosticItem {
  capabilityId: string;
  displayName: string;
  displaySummary: string;
  path: string;
  status: "present" | "missing" | "wrong-mode" | "drift" | "needs-merge" | "source-missing" | "unsupported";
  reason?: string;
}

export interface RseSummary {
  rule: {
    present: boolean;
    type?: string;
    artifacts: readonly string[];
  };
  sensor: {
    present: boolean;
    type?: string;
    checks: readonly string[];
  };
  enforcer: {
    present: boolean;
    type?: string;
    mechanisms: readonly string[];
  };
}

export interface CapabilityDiagnosticSummary {
  capabilityId: string;
  displayName: string;
  displaySummary: string;
  kind: ManifestV2["kind"];
  status: "healthy" | "unhealthy";
  rse: RseSummary;
  summary: {
    present: number;
    missing: number;
    wrongMode: number;
    drift: number;
    needsMerge: number;
    sourceMissing: number;
    unsupported: number;
  };
}

export interface DiagnoseReport {
  command: "diagnose";
  status: "healthy" | "unhealthy" | "error";
  targetRoot: string;
  configPath: string;
  healthy: boolean;
  items: readonly DiagnosticItem[];
  capabilities: readonly CapabilityDiagnosticSummary[];
  summary: {
    present: number;
    missing: number;
    wrongMode: number;
    drift: number;
    needsMerge: number;
    sourceMissing: number;
    unsupported: number;
  };
}

export type MergeStrategy = "keep" | "replace" | "skip";
export type InstallerStrategy = "merge" | "replace" | "skip";

export interface MergeCapabilityPlan {
  capabilityId: string;
  displayName: string;
  displaySummary: string;
  kind: ManifestV2["kind"];
  status: "clean" | "no-op" | "conflict" | "error";
  decisionGranularity: "capability";
  availableStrategies: readonly MergeStrategy[];
  defaultStrategy: MergeStrategy;
  recommendation: "apply" | "skip" | "review";
  rse: RseSummary;
  summary: {
    create: number;
    overwrite: number;
    delete: number;
    chmod: number;
    merge: number;
    skip: number;
    conflict: number;
    missingSource: number;
    unsupported: number;
  };
  paths: readonly string[];
}

export interface MergeReport {
  command: "merge";
  status: "planned" | "merged" | "conflict" | "error";
  dryRun: boolean;
  decisionGranularity: "capability";
  strategyOptions: readonly MergeStrategy[];
  targetRoot: string;
  configPath: string;
  capabilities: readonly MergeCapabilityPlan[];
}

export interface StatusCapabilityGroup {
  kind: ManifestV2["kind"];
  capabilities: readonly CapabilityDiagnosticSummary[];
}

export interface StatusReport {
  command: "status";
  status: "healthy" | "unhealthy";
  targetRoot: string;
  configPath: string;
  groups: readonly StatusCapabilityGroup[];
  summary: {
    healthy: number;
    unhealthy: number;
    hard: number;
    soft: number;
    infra: number;
  };
}

export interface ValidationReport {
  command: "validate";
  status: "valid" | "invalid";
  targetRoot: string;
  configPath: string;
  registry: {
    status: "valid" | "invalid";
    capabilityCount: number;
  };
  config: {
    status: "valid" | "invalid";
    capabilityCount?: number;
  };
  deployment: {
    status: "valid" | "invalid";
    order?: readonly string[];
  };
  issues: readonly string[];
}

export interface GeneratedFilePreview {
  capabilityId: string;
  displayName: string;
  summary: string;
  src: string;
  dst: string;
  content: string;
}

export interface FinalizeCheck {
  name: string;
  status: "passed" | "failed" | "skipped";
  description: string;
}

export interface FinalizeReport {
  command: "finalize";
  status: "completed" | "partial" | "failed";
  targetRoot: string;
  configPath: string;
  githubRemote: "apply" | "skip";
  releaseValidation: "real" | "readiness";
  stagedPaths: readonly string[];
  commitSha?: string;
  checks: readonly FinalizeCheck[];
  remote?: {
    applyStatus?: string;
    verifyStatus?: string;
    repository?: string;
    initializationPullRequestMerged?: boolean;
    remoteActions?: readonly Record<string, unknown>[];
    applyItems?: readonly Record<string, unknown>[];
    verifyItems?: readonly Record<string, unknown>[];
  };
  issuePrE2e?: {
    status: "passed" | "failed" | "skipped";
    description: string;
  };
  releaseE2e?: {
    status: "passed" | "failed" | "skipped";
    description: string;
  };
}

export interface GenerateReport {
  command: "generate";
  status: "generated" | "error";
  targetRoot: string;
  configPath: string;
  locale: LocaleCode;
  deploymentOrder: readonly string[];
  files: readonly GeneratedFilePreview[];
}

export interface ApplyOptions {
  configPath?: string;
  targetRoot?: string;
  dryRun?: boolean;
  config?: DayuConfig;
  onlyCapabilityId?: string;
  force?: boolean;
  pruneOrphans?: boolean;
}

export interface FinalizeOptions {
  configPath?: string;
  targetRoot?: string;
  skillRoot?: string;
  githubRemote?: "apply" | "skip";
  releaseValidation?: "real" | "readiness";
}

export interface InitOptions {
  configPath?: string;
  targetRoot?: string;
  dryRun?: boolean;
  locale?: LocaleCode;
  force?: boolean;
  pruneOrphans?: boolean;
}

export interface GenerateOptions {
  configPath?: string;
  targetRoot?: string;
  capabilityId?: string;
}

export interface MergeOptions extends ApplyOptions {
  strategy?: MergeStrategy;
}

export interface RepairOptions extends ApplyOptions {
  capabilityId?: string;
}
