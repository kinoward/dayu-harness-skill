import { parse as parseYaml } from "yaml";
import { z } from "zod";
import { CapabilityIdSchema, ConfigLocaleSchema } from "./shared.js";

export const DAYU_CONFIG_SCHEMA_VERSION = "1.0.0";

const CapabilitySelectionSchema = z
  .object({
    id: CapabilityIdSchema,
    enabled: z.boolean().default(true),
    options: z.record(z.string(), z.unknown()).optional()
  })
  .strict();

export const DayuConfigSchema = z
  .object({
    schemaVersion: z.literal(DAYU_CONFIG_SCHEMA_VERSION),
    locale: ConfigLocaleSchema.default("zh"),
    capabilities: z.array(CapabilitySelectionSchema).min(1),
    project: z
      .object({
        name: z.string().min(1).optional(),
        root: z.string().min(1).optional()
      })
      .strict()
      .optional()
  })
  .strict()
  .superRefine((config, ctx) => {
    const seen = new Set<string>();
    for (const [index, capability] of config.capabilities.entries()) {
      if (seen.has(capability.id)) {
        ctx.addIssue({
          code: "custom",
          path: ["capabilities", index, "id"],
          message: `duplicate capability '${capability.id}'`
        });
      }
      seen.add(capability.id);
    }
  });

export type DayuConfig = z.infer<typeof DayuConfigSchema>;

export function parseDayuConfigYaml(source: string): DayuConfig {
  const parsed = parseYaml(source);
  return DayuConfigSchema.parse(parsed);
}

export function validateDayuConfigCapabilities(config: DayuConfig, availableCapabilityIds: Iterable<string>): string[] {
  const available = new Set(availableCapabilityIds);
  const unknown = new Set<string>();

  for (const capability of config.capabilities) {
    if (!available.has(capability.id)) {
      unknown.add(capability.id);
    }
  }

  return [...unknown].sort();
}
