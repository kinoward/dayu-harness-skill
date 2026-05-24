import type { ArchitectureLayerId } from "./layers.js";

export type CliCommandName = "init" | "apply" | "diagnose" | "validate" | "merge" | "generate" | "status" | "repair";

export interface CliCommandSpec {
  name: CliCommandName;
  layer: ArchitectureLayerId;
  purpose: string;
  mapsFromMode: string;
  reads: readonly string[];
  writes: readonly string[];
  delegatesTo: readonly CliCommandName[];
  supportsDryRun: boolean;
  supportsJson: boolean;
  interactive: boolean;
  phase1Slice: boolean;
}

export const CLI_COMMAND_TREE: readonly CliCommandSpec[] = [
  {
    name: "init",
    layer: "tool",
    purpose: "Create a default dayu.config.yaml when missing, then call apply.",
    mapsFromMode: "scaffold entrypoint",
    reads: ["target project root", "dayu.config.yaml if present", "default capability preset"],
    writes: ["dayu.config.yaml", "product artifacts via apply"],
    delegatesTo: ["apply"],
    supportsDryRun: true,
    supportsJson: true,
    interactive: false,
    phase1Slice: false
  },
  {
    name: "apply",
    layer: "tool",
    purpose: "Read config, resolve the deployment DAG, render files, run installers, report drift, and record journaled writes.",
    mapsFromMode: "scaffold execution phase",
    reads: ["dayu.config.yaml", "manifest v2 registry", "templates", "assets", "target project state"],
    writes: ["product artifacts", ".dayu-log.jsonl"],
    delegatesTo: [],
    supportsDryRun: true,
    supportsJson: true,
    interactive: false,
    phase1Slice: false
  },
  {
    name: "diagnose",
    layer: "tool",
    purpose: "Check deployed governance health and include maintain-style inconsistency detection.",
    mapsFromMode: "diagnose + maintain detection",
    reads: ["target project product artifacts", "deployed sensors"],
    writes: ["diagnostic report"],
    delegatesTo: [],
    supportsDryRun: false,
    supportsJson: true,
    interactive: false,
    phase1Slice: false
  },
  {
    name: "validate",
    layer: "tool",
    purpose: "Validate manifest schema, config schema, dependency contracts, and deployed product consistency.",
    mapsFromMode: "new validation command",
    reads: ["manifest v2 registry", "dayu.config.yaml", "target project product artifacts"],
    writes: ["validation report"],
    delegatesTo: [],
    supportsDryRun: false,
    supportsJson: true,
    interactive: false,
    phase1Slice: false
  },
  {
    name: "merge",
    layer: "tool",
    purpose: "Plan or apply capability-level keep/replace/skip merging for existing projects.",
    mapsFromMode: "merge",
    reads: ["dayu.config.yaml", "manifest v2 registry", "target project state"],
    writes: ["product artifacts when --apply is used"],
    delegatesTo: ["apply"],
    supportsDryRun: true,
    supportsJson: true,
    interactive: false,
    phase1Slice: false
  },
  {
    name: "generate",
    layer: "tool",
    purpose: "Render managed content previews without writing product artifacts.",
    mapsFromMode: "generate + maintain repair preview",
    reads: ["dayu.config.yaml", "manifest v2 registry", "templates", "assets"],
    writes: ["generated preview report"],
    delegatesTo: [],
    supportsDryRun: false,
    supportsJson: true,
    interactive: false,
    phase1Slice: false
  },
  {
    name: "status",
    layer: "tool",
    purpose: "Show the grouped governance map by hard, soft, and infra capabilities.",
    mapsFromMode: "status",
    reads: ["dayu.config.yaml", "manifest v2 registry", "target project state"],
    writes: ["status report"],
    delegatesTo: ["diagnose"],
    supportsDryRun: false,
    supportsJson: true,
    interactive: false,
    phase1Slice: false
  },
  {
    name: "repair",
    layer: "tool",
    purpose: "Repair drift for one capability or the active deployment plan using journaled apply semantics.",
    mapsFromMode: "maintain repair",
    reads: ["dayu.config.yaml", "manifest v2 registry", "target project state", ".dayu/journal.jsonl"],
    writes: ["product artifacts", ".dayu/journal.jsonl"],
    delegatesTo: ["apply"],
    supportsDryRun: false,
    supportsJson: true,
    interactive: false,
    phase1Slice: false
  }
];

export function getCliCommandSpec(name: CliCommandName): CliCommandSpec {
  const command = CLI_COMMAND_TREE.find((candidate) => candidate.name === name);
  if (!command) {
    throw new Error(`unknown CLI command '${name}'`);
  }
  return command;
}
