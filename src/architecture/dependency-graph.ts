import type { CapabilityId, ManifestV2 } from "../schemas/index.js";

export type DependencyGraphKind = "deployment" | "conceptual";

export interface CapabilityDependencyEdge {
  kind: DependencyGraphKind;
  capabilityId: CapabilityId;
  dependsOn: CapabilityId;
}

export interface CapabilityDependencyGraph {
  kind: DependencyGraphKind;
  nodes: readonly CapabilityId[];
  edges: readonly CapabilityDependencyEdge[];
}

export interface CapabilityDependencyModel {
  deployment: CapabilityDependencyGraph;
  conceptual: CapabilityDependencyGraph;
}

export interface DependencyGraphIssue {
  code: "duplicate-capability" | "missing-dependency" | "cycle";
  kind?: DependencyGraphKind;
  capabilityId: CapabilityId;
  dependsOn?: CapabilityId;
  cycle?: readonly CapabilityId[];
  message: string;
}

export class DependencyGraphError extends Error {
  readonly issues: readonly DependencyGraphIssue[];

  constructor(message: string, issues: readonly DependencyGraphIssue[]) {
    super(message);
    this.name = "DependencyGraphError";
    this.issues = issues;
  }
}

export function buildCapabilityDependencyModel(manifests: readonly ManifestV2[]): CapabilityDependencyModel {
  return {
    deployment: buildCapabilityDependencyGraph(manifests, "deployment"),
    conceptual: buildCapabilityDependencyGraph(manifests, "conceptual")
  };
}

export function buildCapabilityDependencyGraph(
  manifests: readonly ManifestV2[],
  kind: DependencyGraphKind
): CapabilityDependencyGraph {
  const { manifestById, issues } = createManifestMap(manifests);
  const edges: CapabilityDependencyEdge[] = [];

  for (const manifest of manifests) {
    for (const dependsOn of getManifestDependencyIds(manifest, kind)) {
      if (!manifestById.has(dependsOn)) {
        issues.push({
          code: "missing-dependency",
          kind,
          capabilityId: manifest.id,
          dependsOn,
          message: `${manifest.id} declares missing ${kind} dependency '${dependsOn}'`
        });
        continue;
      }

      edges.push({ kind, capabilityId: manifest.id, dependsOn });
    }
  }

  if (issues.length === 0) {
    issues.push(...detectGraphCycles(manifestById, kind));
  }

  assertNoIssues(issues);

  return {
    kind,
    nodes: [...manifestById.keys()].sort(),
    edges: edges.sort(compareEdges)
  };
}

export function resolveDeploymentOrder(
  manifests: readonly ManifestV2[],
  requestedIds: readonly CapabilityId[]
): CapabilityId[] {
  return resolveDependencyOrder(manifests, requestedIds, "deployment");
}

export function resolveConceptualOrder(
  manifests: readonly ManifestV2[],
  requestedIds: readonly CapabilityId[]
): CapabilityId[] {
  return resolveDependencyOrder(manifests, requestedIds, "conceptual");
}

export function resolveDependencyOrder(
  manifests: readonly ManifestV2[],
  requestedIds: readonly CapabilityId[],
  kind: DependencyGraphKind
): CapabilityId[] {
  const { manifestById, issues } = createManifestMap(manifests);
  const closure = new Set<CapabilityId>();
  const states = new Map<CapabilityId, "visiting" | "visited">();
  const requested = new Set(uniqueIds(requestedIds));

  const collectClosure = (capabilityId: CapabilityId, stack: CapabilityId[]): void => {
    const state = states.get(capabilityId);
    if (state === "visited") {
      return;
    }
    if (state === "visiting") {
      const cycleStart = stack.indexOf(capabilityId);
      const cycle = [...(cycleStart >= 0 ? stack.slice(cycleStart) : stack), capabilityId];
      issues.push({
        code: "cycle",
        kind,
        capabilityId,
        cycle,
        message: `${kind} dependency cycle detected: ${cycle.join(" -> ")}`
      });
      return;
    }

    const manifest = manifestById.get(capabilityId);
    if (!manifest) {
      issues.push({
        code: "missing-dependency",
        kind,
        capabilityId,
        message: `requested capability '${capabilityId}' is not present in the manifest registry`
      });
      return;
    }

    states.set(capabilityId, "visiting");
    closure.add(capabilityId);
    const nextStack = [...stack, capabilityId];
    for (const dependsOn of sortCapabilityIds(getManifestDependencyIds(manifest, kind), manifestById)) {
      if (!manifestById.has(dependsOn)) {
        issues.push({
          code: "missing-dependency",
          kind,
          capabilityId,
          dependsOn,
          message: `${capabilityId} declares missing ${kind} dependency '${dependsOn}'`
        });
        continue;
      }
      collectClosure(dependsOn, nextStack);
    }
    states.set(capabilityId, "visited");
  };

  for (const capabilityId of requested) {
    if (!manifestById.has(capabilityId)) {
      issues.push({
        code: "missing-dependency",
        kind,
        capabilityId,
        message: `requested capability '${capabilityId}' is not present in the manifest registry`
      });
    }
  }

  if (issues.length === 0) {
    for (const capabilityId of sortCapabilityIds(requested, manifestById)) {
      if (requested.has(capabilityId)) {
        collectClosure(capabilityId, []);
      }
    }
  }

  assertNoIssues(issues);
  return topologicalOrder(closure, manifestById, kind);
}

export function getManifestDependencyIds(manifest: ManifestV2, kind: DependencyGraphKind): readonly CapabilityId[] {
  return kind === "deployment" ? manifest.deployment_deps : manifest.conceptual_deps;
}

function createManifestMap(manifests: readonly ManifestV2[]): {
  manifestById: Map<CapabilityId, ManifestV2>;
  issues: DependencyGraphIssue[];
} {
  const manifestById = new Map<CapabilityId, ManifestV2>();
  const issues: DependencyGraphIssue[] = [];

  for (const manifest of manifests) {
    if (manifestById.has(manifest.id)) {
      issues.push({
        code: "duplicate-capability",
        capabilityId: manifest.id,
        message: `duplicate capability '${manifest.id}' in manifest registry`
      });
      continue;
    }
    manifestById.set(manifest.id, manifest);
  }

  return { manifestById, issues };
}

function uniqueIds(ids: readonly CapabilityId[]): CapabilityId[] {
  const seen = new Set<CapabilityId>();
  const result: CapabilityId[] = [];
  for (const id of ids) {
    if (!seen.has(id)) {
      seen.add(id);
      result.push(id);
    }
  }
  return result;
}

function sortedManifestIds(manifestById: ReadonlyMap<CapabilityId, ManifestV2>): CapabilityId[] {
  return [...manifestById.keys()].sort();
}

function sortCapabilityIds(
  ids: Iterable<CapabilityId>,
  manifestById: ReadonlyMap<CapabilityId, ManifestV2>
): CapabilityId[] {
  return [...ids].sort((left, right) => compareCapabilityIds(left, right, manifestById));
}

function compareCapabilityIds(
  leftId: CapabilityId,
  rightId: CapabilityId,
  manifestById: ReadonlyMap<CapabilityId, ManifestV2>
): number {
  const left = manifestById.get(leftId);
  const right = manifestById.get(rightId);
  const leftPriority = left ? kindPriority(left.kind) : Number.MAX_SAFE_INTEGER;
  const rightPriority = right ? kindPriority(right.kind) : Number.MAX_SAFE_INTEGER;

  return leftPriority - rightPriority || leftId.localeCompare(rightId);
}

function kindPriority(kind: ManifestV2["kind"]): number {
  switch (kind) {
    case "infra":
      return 0;
    case "hard":
      return 1;
    case "soft":
      return 2;
  }
}

function compareEdges(left: CapabilityDependencyEdge, right: CapabilityDependencyEdge): number {
  return left.capabilityId.localeCompare(right.capabilityId) || left.dependsOn.localeCompare(right.dependsOn);
}

function topologicalOrder(
  closure: ReadonlySet<CapabilityId>,
  manifestById: ReadonlyMap<CapabilityId, ManifestV2>,
  kind: DependencyGraphKind
): CapabilityId[] {
  const order: CapabilityId[] = [];
  const scheduled = new Set<CapabilityId>();

  while (scheduled.size < closure.size) {
    const ready = sortCapabilityIds(
      [...closure].filter((capabilityId) => {
        if (scheduled.has(capabilityId)) {
          return false;
        }

        const manifest = manifestById.get(capabilityId);
        if (!manifest) {
          return false;
        }

        return getManifestDependencyIds(manifest, kind).every(
          (dependsOn) => !closure.has(dependsOn) || scheduled.has(dependsOn)
        );
      }),
      manifestById
    );

    if (ready.length === 0) {
      throw new DependencyGraphError("dependency graph could not be topologically sorted", [
        {
          code: "cycle",
          kind,
          capabilityId: [...closure][0] ?? ("" as CapabilityId),
          message: `${kind} dependency cycle detected`
        }
      ]);
    }

    const capabilityId = ready[0];
    scheduled.add(capabilityId);
    order.push(capabilityId);
  }

  return order;
}

function detectGraphCycles(
  manifestById: ReadonlyMap<CapabilityId, ManifestV2>,
  kind: DependencyGraphKind
): DependencyGraphIssue[] {
  const issues: DependencyGraphIssue[] = [];
  const states = new Map<CapabilityId, "visiting" | "visited">();

  const visit = (capabilityId: CapabilityId, stack: CapabilityId[]): void => {
    const state = states.get(capabilityId);
    if (state === "visited") {
      return;
    }
    if (state === "visiting") {
      const cycleStart = stack.indexOf(capabilityId);
      const cycle = [...(cycleStart >= 0 ? stack.slice(cycleStart) : stack), capabilityId];
      issues.push({
        code: "cycle",
        kind,
        capabilityId,
        cycle,
        message: `${kind} dependency cycle detected: ${cycle.join(" -> ")}`
      });
      return;
    }

    const manifest = manifestById.get(capabilityId);
    if (!manifest) {
      return;
    }

    states.set(capabilityId, "visiting");
    const nextStack = [...stack, capabilityId];
    for (const dependsOn of getManifestDependencyIds(manifest, kind)) {
      if (manifestById.has(dependsOn)) {
        visit(dependsOn, nextStack);
      }
    }
    states.set(capabilityId, "visited");
  };

  for (const capabilityId of sortedManifestIds(manifestById)) {
    visit(capabilityId, []);
  }

  return issues;
}

function assertNoIssues(issues: readonly DependencyGraphIssue[]): void {
  if (issues.length > 0) {
    throw new DependencyGraphError(
      issues.map((issue) => issue.message).join("; "),
      issues
    );
  }
}
