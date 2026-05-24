import { buildApplyPlan } from "./apply.js";
import { capabilityDisplay } from "./display.js";
import { loadManifestRegistry } from "./manifest-registry.js";
import { loadLocaleCatalog } from "./render.js";
import { summarizeRse } from "./rse.js";
import type {
  ApplyOptions,
  CapabilityDisplaySummary,
  CapabilityDiagnosticSummary,
  DiagnoseReport,
  DiagnosticItem,
  FileOperation,
  InstallerOperation
} from "./types.js";

export function diagnoseDayuProject(options: ApplyOptions = {}): DiagnoseReport {
  const plan = buildApplyPlan({ ...options, dryRun: true });
  const registry = loadManifestRegistry();
  const localeCatalog = loadLocaleCatalog(registry.skillRoot, plan.locale);
  const displayByCapability = new Map(plan.capabilitySummaries.map((capability) => [capability.capabilityId, capability]));
  const items: DiagnosticItem[] = [
    ...plan.fileOperations.map((operation) => fileOperationToDiagnostic(operation, displayByCapability)),
    ...plan.installerOperations.map((operation) => installerOperationToDiagnostic(operation, displayByCapability))
  ];
  const summary = {
    present: items.filter((item) => item.status === "present").length,
    missing: items.filter((item) => item.status === "missing").length,
    wrongMode: items.filter((item) => item.status === "wrong-mode").length,
    drift: items.filter((item) => item.status === "drift").length,
    needsMerge: items.filter((item) => item.status === "needs-merge").length,
    sourceMissing: items.filter((item) => item.status === "source-missing").length,
    unsupported: items.filter((item) => item.status === "unsupported").length
  };
  const healthy =
    summary.missing === 0 &&
    summary.wrongMode === 0 &&
    summary.drift === 0 &&
    summary.needsMerge === 0 &&
    summary.sourceMissing === 0 &&
    summary.unsupported === 0;
  const capabilities = plan.deploymentOrder.map((capabilityId): CapabilityDiagnosticSummary => {
    const manifest = registry.manifestById.get(capabilityId);
    if (!manifest) {
      throw new Error(`capability '${capabilityId}' is not loaded`);
    }
    const capabilityItems = items.filter((item) => item.capabilityId === capabilityId);
    const capabilitySummary = summarizeDiagnosticItems(capabilityItems);
    const capabilityHealthy =
      capabilitySummary.missing === 0 &&
      capabilitySummary.wrongMode === 0 &&
      capabilitySummary.drift === 0 &&
      capabilitySummary.needsMerge === 0 &&
      capabilitySummary.sourceMissing === 0 &&
      capabilitySummary.unsupported === 0;

    return {
      capabilityId,
      displayName: capabilityDisplay(capabilityId, registry, localeCatalog).displayName,
      displaySummary: capabilityDisplay(capabilityId, registry, localeCatalog).summary,
      kind: manifest.kind,
      status: capabilityHealthy ? "healthy" : "unhealthy",
      rse: summarizeRse(manifest),
      summary: capabilitySummary
    };
  });

  return {
    command: "diagnose",
    status: healthy ? "healthy" : "unhealthy",
    targetRoot: plan.targetRoot,
    configPath: plan.configPath,
    healthy,
    items,
    capabilities,
    summary
  };
}

function summarizeDiagnosticItems(items: readonly DiagnosticItem[]) {
  return {
    present: items.filter((item) => item.status === "present").length,
    missing: items.filter((item) => item.status === "missing").length,
    wrongMode: items.filter((item) => item.status === "wrong-mode").length,
    drift: items.filter((item) => item.status === "drift").length,
    needsMerge: items.filter((item) => item.status === "needs-merge").length,
    sourceMissing: items.filter((item) => item.status === "source-missing").length,
    unsupported: items.filter((item) => item.status === "unsupported").length
  };
}

function fileOperationToDiagnostic(
  operation: FileOperation,
  displayByCapability: ReadonlyMap<string, CapabilityDisplaySummary>
): DiagnosticItem {
  const display = displayForOperation(operation.capabilityId, displayByCapability);
  switch (operation.status) {
    case "skip":
      return {
        capabilityId: operation.capabilityId,
        ...display,
        path: operation.dst,
        status: "present",
        reason: operation.reason
      };
    case "create":
      return {
        capabilityId: operation.capabilityId,
        ...display,
        path: operation.dst,
        status: "missing"
      };
    case "chmod":
      return {
        capabilityId: operation.capabilityId,
        ...display,
        path: operation.dst,
        status: "wrong-mode",
        reason: operation.reason
      };
    case "conflict":
    case "overwrite":
      return {
        capabilityId: operation.capabilityId,
        ...display,
        path: operation.dst,
        status: "drift",
        reason: operation.reason
      };
    case "delete":
      return {
        capabilityId: operation.capabilityId,
        ...display,
        path: operation.dst,
        status: "drift",
        reason: operation.reason
      };
    case "missing-source":
      return {
        capabilityId: operation.capabilityId,
        ...display,
        path: operation.dst,
        status: "source-missing",
        reason: operation.reason
      };
  }
}

function installerOperationToDiagnostic(
  operation: InstallerOperation,
  displayByCapability: ReadonlyMap<string, CapabilityDisplaySummary>
): DiagnosticItem {
  const display = displayForOperation(operation.capabilityId, displayByCapability);
  switch (operation.status) {
    case "skip":
      return {
        capabilityId: operation.capabilityId,
        ...display,
        path: operation.dst,
        status: "present",
        reason: operation.reason
      };
    case "create":
      return {
        capabilityId: operation.capabilityId,
        ...display,
        path: operation.dst,
        status: "missing"
      };
    case "merge":
      return {
        capabilityId: operation.capabilityId,
        ...display,
        path: operation.dst,
        status: "needs-merge",
        reason: operation.reason
      };
    case "missing-source":
      return {
        capabilityId: operation.capabilityId,
        ...display,
        path: operation.dst,
        status: "source-missing",
        reason: operation.reason
      };
    case "unsupported":
      return {
        capabilityId: operation.capabilityId,
        ...display,
        path: operation.dst,
        status: "unsupported",
        reason: operation.reason
      };
  }
}

function displayForOperation(
  capabilityId: string,
  displayByCapability: ReadonlyMap<string, CapabilityDisplaySummary>
): Pick<DiagnosticItem, "displayName" | "displaySummary"> {
  const display = displayByCapability.get(capabilityId);
  return {
    displayName: display?.displayName ?? capabilityId,
    displaySummary: display?.summary ?? capabilityId
  };
}
