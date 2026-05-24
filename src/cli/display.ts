import type { ManifestV2 } from "../schemas/index.js";
import type { ManifestRegistry } from "./types.js";

export interface CapabilityDisplay {
  capabilityId: string;
  displayName: string;
  summary: string;
}

export function capabilityDisplayName(manifest: ManifestV2, localeCatalog: Readonly<Record<string, string>>): string {
  return localeCatalog[manifest.i18n.title_key] ?? manifest.description_nl;
}

export function capabilityDisplaySummary(manifest: ManifestV2, localeCatalog: Readonly<Record<string, string>>): string {
  return localeCatalog[manifest.i18n.description_key] ?? manifest.description_nl;
}

export function capabilityDisplay(
  capabilityId: string,
  registry: ManifestRegistry,
  localeCatalog: Readonly<Record<string, string>>
): CapabilityDisplay {
  const manifest = registry.manifestById.get(capabilityId);
  return {
    capabilityId,
    displayName: manifest ? capabilityDisplayName(manifest, localeCatalog) : capabilityId,
    summary: manifest ? capabilityDisplaySummary(manifest, localeCatalog) : capabilityId
  };
}

export function capabilityDisplayMap(
  registry: ManifestRegistry,
  localeCatalog: Readonly<Record<string, string>>
): ReadonlyMap<string, string> {
  return new Map(registry.manifests.map((manifest) => [manifest.id, capabilityDisplayName(manifest, localeCatalog)]));
}
