import type { ManifestV2 } from "../schemas/index.js";
import type { RseSummary } from "./types.js";

export function summarizeRse(manifest: ManifestV2): RseSummary {
  return {
    rule: {
      present: Boolean(manifest.rse.rule),
      type: manifest.rse.rule?.type,
      artifacts: manifest.rse.rule?.artifacts ?? []
    },
    sensor: {
      present: Boolean(manifest.rse.sensor),
      type: manifest.rse.sensor?.type,
      checks: manifest.rse.sensor?.checks ?? []
    },
    enforcer: {
      present: Boolean(manifest.rse.enforcer),
      type: manifest.rse.enforcer?.type,
      mechanisms: manifest.rse.enforcer?.mechanisms ?? []
    }
  };
}
