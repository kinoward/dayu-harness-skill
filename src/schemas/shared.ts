import { z } from "zod";

export const CapabilityIdSchema = z
  .string()
  .min(1)
  .regex(/^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$/, "must be a dotted or dashed lowercase capability id");

export const LocaleCodeSchema = z.enum(["zh", "en"]);

export const ConfigLocaleSchema = z
  .enum(["zh", "zh-CN", "en", "en-US"])
  .transform((locale) => (locale.startsWith("zh") ? "zh" : "en"));

export const I18nKeySchema = z
  .string()
  .min(1)
  .regex(/^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+$/, "must be a namespaced lowercase i18n key");

export const RelativePathSchema = z.string().superRefine((value, ctx) => {
  if (value.length === 0) {
    ctx.addIssue({ code: "custom", message: "path must not be empty" });
    return;
  }

  if (value.includes("\0")) {
    ctx.addIssue({ code: "custom", message: "path must not contain NUL bytes" });
  }

  if (value.startsWith("/") || value.startsWith("\\") || /^[A-Za-z]:[\\/]/.test(value)) {
    ctx.addIssue({ code: "custom", message: "path must be relative to the project root" });
  }

  if (value.split(/[\\/]+/).includes("..")) {
    ctx.addIssue({ code: "custom", message: "path must not contain traversal segments" });
  }
});

export const FileMappingSchema = z
  .object({
    src: RelativePathSchema,
    dst: RelativePathSchema,
    executable: z.boolean().optional()
  })
  .strict();

export const I18nKeyRefSchema = z
  .object({
    title_key: I18nKeySchema,
    description_key: I18nKeySchema,
    acceptance_keys: z.array(I18nKeySchema).optional()
  })
  .strict();

export type CapabilityId = z.infer<typeof CapabilityIdSchema>;
export type LocaleCode = z.infer<typeof LocaleCodeSchema>;
export type ConfigLocale = z.infer<typeof ConfigLocaleSchema>;
export type FileMapping = z.infer<typeof FileMappingSchema>;
