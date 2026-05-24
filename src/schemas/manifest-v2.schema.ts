import { z } from "zod";
import {
  CapabilityIdSchema,
  FileMappingSchema,
  I18nKeyRefSchema,
  I18nKeySchema,
  RelativePathSchema
} from "./shared.js";

export const MANIFEST_SCHEMA_VERSION = "2.0.0";

const InstallerSchema = z
  .object({
    script: RelativePathSchema,
    safe_strategies: z.array(z.enum(["merge", "replace", "skip"])).min(1),
    notes: z.string().min(1).optional()
  })
  .strict();

const RuleSchema = z
  .object({
    type: z.enum(["documentation", "configuration", "infrastructure"]),
    summary_key: I18nKeySchema,
    artifacts: z.array(RelativePathSchema).default([])
  })
  .strict();

const SensorSchema = z
  .object({
    type: z.enum(["script", "config", "manual"]),
    summary_key: I18nKeySchema,
    checks: z.array(z.string().min(1)).default([])
  })
  .strict();

const EnforcerSchema = z
  .object({
    type: z.enum(["hook", "ci", "manual"]),
    summary_key: I18nKeySchema,
    mechanisms: z.array(z.string().min(1)).default([])
  })
  .strict();

const RemoteActionSchema = z
  .object({
    kind: z.string().min(1)
  })
  .passthrough();

const TemplateFilesI18nSchema = z
  .object({
    zh: z.array(FileMappingSchema).optional(),
    en: z.array(FileMappingSchema).optional()
  })
  .strict();

export const ManifestV2Schema = z
  .object({
    id: CapabilityIdSchema,
    schemaVersion: z.literal(MANIFEST_SCHEMA_VERSION),
    kind: z.enum(["hard", "soft", "infra"]),
    description: z.string().min(1),
    description_nl: z.string().min(1),
    default: z.boolean(),
    internal: z.boolean().optional(),
    deployment_deps: z.array(CapabilityIdSchema).default([]),
    conceptual_deps: z.array(CapabilityIdSchema).default([]),

    // Compatibility bridge while scaffold.sh still reads the legacy field.
    dependencies: z.array(CapabilityIdSchema),

    i18n: I18nKeyRefSchema,
    rse: z
      .object({
        rule: RuleSchema.nullable(),
        sensor: SensorSchema.nullable(),
        enforcer: EnforcerSchema.nullable()
      })
      .strict(),
    template_files: z.array(FileMappingSchema).default([]),
    asset_files: z.array(FileMappingSchema).default([]),
    template_files_i18n: TemplateFilesI18nSchema.optional(),
    installer: InstallerSchema.nullable().default(null),
    remote_actions: z.array(RemoteActionSchema).optional(),
    acceptance: z.array(z.string().min(1)).default([]),
    requires: z.array(z.string().min(1)).optional(),
    suggested_when: z.string().min(1).optional()
  })
  .strict()
  .superRefine((manifest, ctx) => {
    const allDeps = [...manifest.deployment_deps, ...manifest.conceptual_deps];
    if (allDeps.includes(manifest.id)) {
      ctx.addIssue({
        code: "custom",
        path: ["deployment_deps"],
        message: "capability must not depend on itself"
      });
    }

    const legacyDeps = [...manifest.dependencies].sort();
    const deploymentDeps = [...manifest.deployment_deps].sort();
    if (JSON.stringify(legacyDeps) !== JSON.stringify(deploymentDeps)) {
      ctx.addIssue({
        code: "custom",
        path: ["dependencies"],
        message: "legacy dependencies must mirror deployment_deps during scaffold.sh compatibility"
      });
    }

    if (manifest.kind === "hard") {
      if (!manifest.rse.rule || !manifest.rse.sensor || !manifest.rse.enforcer) {
        ctx.addIssue({
          code: "custom",
          path: ["rse"],
          message: "hard capabilities require rule, sensor, and enforcer"
        });
      }
    }

    if (manifest.kind === "soft") {
      if (!manifest.rse.rule) {
        ctx.addIssue({
          code: "custom",
          path: ["rse", "rule"],
          message: "soft capabilities require a rule"
        });
      }
      if (manifest.rse.sensor || manifest.rse.enforcer) {
        ctx.addIssue({
          code: "custom",
          path: ["rse"],
          message: "soft capabilities must not declare sensor or enforcer"
        });
      }
    }

    if (manifest.kind === "infra" && (manifest.rse.sensor || manifest.rse.enforcer)) {
      ctx.addIssue({
        code: "custom",
        path: ["rse"],
        message: "infra capabilities must not declare sensor or enforcer"
      });
    }
  });

export type ManifestV2 = z.infer<typeof ManifestV2Schema>;

export function collectManifestI18nKeys(manifest: ManifestV2): string[] {
  const keys = new Set<string>([
    manifest.i18n.title_key,
    manifest.i18n.description_key,
    ...(manifest.i18n.acceptance_keys ?? [])
  ]);

  if (manifest.rse.rule) {
    keys.add(manifest.rse.rule.summary_key);
  }
  if (manifest.rse.sensor) {
    keys.add(manifest.rse.sensor.summary_key);
  }
  if (manifest.rse.enforcer) {
    keys.add(manifest.rse.enforcer.summary_key);
  }

  return [...keys].sort();
}
