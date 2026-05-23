export type ArchitectureLayerId = "frontend" | "tool" | "product";

export interface ArchitectureLayerContract {
  id: ArchitectureLayerId;
  label: string;
  responsibility: string;
  allowedDependencies: readonly ArchitectureLayerId[];
  sourceSurfaces: readonly string[];
  outputSurfaces: readonly string[];
  forbiddenCouplings: readonly string[];
}

export const ARCHITECTURE_LAYERS: readonly ArchitectureLayerContract[] = [
  {
    id: "frontend",
    label: "Frontend",
    responsibility: "Guide users through configuration and hand off dayu.config.yaml to the CLI.",
    allowedDependencies: ["tool"],
    sourceSurfaces: ["SKILL.md", "Q&A-TEMPLATE.md", "dayu.config.yaml"],
    outputSurfaces: ["dayu.config.yaml", "CLI invocation"],
    forbiddenCouplings: [
      "Must not render templates directly.",
      "Must not write product-layer files directly.",
      "Must not bypass config schema validation."
    ]
  },
  {
    id: "tool",
    label: "Tool",
    responsibility: "Validate config and manifests, resolve dependencies, render assets, and deploy product artifacts.",
    allowedDependencies: ["product"],
    sourceSurfaces: ["src/", "capabilities/", "locales/", "templates/", "templates.en/", "assets/"],
    outputSurfaces: ["AGENTS.md", "docs/", ".husky/", ".github/", "tooling config files"],
    forbiddenCouplings: [
      "Must not depend on SKILL.md conversation state.",
      "Must not require an agent client at apply time.",
      "Must not treat conceptual dependencies as deployment blockers."
    ]
  },
  {
    id: "product",
    label: "Product",
    responsibility: "Run as the deployed governance system inside the target project after the tool disappears.",
    allowedDependencies: [],
    sourceSurfaces: ["AGENTS.md", "docs/", ".husky/", ".github/", "deployed config files"],
    outputSurfaces: ["validation reports", "audit reports", "hook and CI enforcement"],
    forbiddenCouplings: [
      "Must not import src/ from this Skill.",
      "Must not require capabilities/ manifests at runtime.",
      "Must not require templates/ or assets/ after deployment."
    ]
  }
];

export function getArchitectureLayer(id: ArchitectureLayerId): ArchitectureLayerContract {
  const layer = ARCHITECTURE_LAYERS.find((candidate) => candidate.id === id);
  if (!layer) {
    throw new Error(`unknown architecture layer '${id}'`);
  }
  return layer;
}

export function canLayerDependOn(consumer: ArchitectureLayerId, provider: ArchitectureLayerId): boolean {
  if (consumer === provider) {
    return true;
  }

  return getArchitectureLayer(consumer).allowedDependencies.includes(provider);
}

export function assertLayerDependency(consumer: ArchitectureLayerId, provider: ArchitectureLayerId): void {
  if (!canLayerDependOn(consumer, provider)) {
    throw new Error(`${consumer} layer must not depend on ${provider} layer`);
  }
}
