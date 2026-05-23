import type { DayuConfig, FileMapping, LocaleCode, ManifestV2 } from "../schemas/index.js";

export type CliCommandName = "init" | "apply" | "diagnose" | "validate";

export type ApplyStatus = "planned" | "applied" | "no-op" | "conflict" | "error";

export type FileOperationStatus = "create" | "chmod" | "skip" | "conflict" | "missing-source";

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
  fileOperations: readonly FileOperation[];
  installerOperations: readonly InstallerOperation[];
  managedPaths: readonly string[];
  summary: {
    create: number;
    chmod: number;
    merge: number;
    skip: number;
    conflict: number;
    missingSource: number;
    unsupported: number;
  };
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

export interface MergeCapabilityPlan {
  capabilityId: string;
  kind: ManifestV2["kind"];
  status: "clean" | "no-op" | "conflict" | "error";
  decisionGranularity: "capability";
  availableStrategies: readonly MergeStrategy[];
  defaultStrategy: MergeStrategy;
  recommendation: "apply" | "skip" | "review";
  rse: RseSummary;
  summary: {
    create: number;
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
  status: "planned" | "conflict" | "error";
  dryRun: boolean;
  decisionGranularity: "capability";
  strategyOptions: readonly MergeStrategy[];
  targetRoot: string;
  configPath: string;
  capabilities: readonly MergeCapabilityPlan[];
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
  src: string;
  dst: string;
  content: string;
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
}

export interface InitOptions {
  configPath?: string;
  targetRoot?: string;
  dryRun?: boolean;
  locale?: LocaleCode;
}

export interface GenerateOptions {
  configPath?: string;
  targetRoot?: string;
  capabilityId?: string;
}
