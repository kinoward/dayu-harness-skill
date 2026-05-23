import type { ArchitectureLayerId } from "./layers.js";

export type CliCommandName = "init" | "apply" | "diagnose" | "validate";

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
    phase1Slice: true
  },
  {
    name: "apply",
    layer: "tool",
    purpose: "Read config, resolve the deployment DAG, render files, run installers, and report drift.",
    mapsFromMode: "scaffold execution phase",
    reads: ["dayu.config.yaml", "manifest v2 registry", "templates", "assets", "target project state"],
    writes: ["product artifacts", ".dayu-log.jsonl"],
    delegatesTo: [],
    supportsDryRun: true,
    supportsJson: true,
    interactive: false,
    phase1Slice: true
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
    phase1Slice: true
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
    phase1Slice: true
  }
];

export function getCliCommandSpec(name: CliCommandName): CliCommandSpec {
  const command = CLI_COMMAND_TREE.find((candidate) => candidate.name === name);
  if (!command) {
    throw new Error(`unknown CLI command '${name}'`);
  }
  return command;
}
