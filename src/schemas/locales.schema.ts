import { z } from "zod";
import { I18nKeySchema } from "./shared.js";

export const DAYU_I18N_TOKEN_PATTERN = /\{\{dayu:([a-z][a-z0-9]*(?:[._-][a-z0-9]+)+)\}\}/g;

export const LocaleCatalogSchema = z.record(I18nKeySchema, z.string().min(1));

export type LocaleCatalog = z.infer<typeof LocaleCatalogSchema>;

export function extractDayuI18nKeys(input: string): string[] {
  const keys = new Set<string>();

  for (const match of input.matchAll(DAYU_I18N_TOKEN_PATTERN)) {
    keys.add(match[1]);
  }

  return [...keys].sort();
}

export function missingLocaleKeys(catalog: LocaleCatalog, keys: Iterable<string>): string[] {
  return [...keys].filter((key) => !(key in catalog)).sort();
}
