import { readFileSync } from "node:fs";
import { join } from "node:path";

import { LocaleCatalogSchema, type FileMapping, type ManifestV2 } from "../schemas/index.js";
import { CliError } from "./errors.js";
import { fileExists, resolveInsideRoot } from "./paths.js";
import type { RenderContext, RenderedFileMapping } from "./types.js";

export function loadLocaleCatalog(skillRoot: string, locale: string): Record<string, string> {
  const localePath = join(skillRoot, "locales", `${locale}.json`);
  const raw = JSON.parse(readFileSync(localePath, "utf8")) as unknown;
  return LocaleCatalogSchema.parse(raw);
}

export function renderManifestFiles(manifest: ManifestV2, context: RenderContext): RenderedFileMapping[] {
  const mappings: RenderedFileMapping[] = [];

  for (const mapping of templateMappingsForLocale(manifest, context.locale, context.skillRoot)) {
    mappings.push(renderFileMapping(manifest.id, "template", mapping, context));
  }

  for (const mapping of manifest.asset_files) {
    mappings.push(renderFileMapping(manifest.id, "asset", mapping, context));
  }

  return mappings;
}

export function templateMappingsForLocale(manifest: ManifestV2, locale: string, skillRoot: string): FileMapping[] {
  if (locale === "en") {
    const explicitEnglish = manifest.template_files_i18n?.en;
    if (explicitEnglish && explicitEnglish.length > 0) {
      return explicitEnglish;
    }

    return manifest.template_files.map((mapping) => {
      const candidate = mapping.src.startsWith("templates/")
        ? { ...mapping, src: mapping.src.replace(/^templates\//, "templates.en/") }
        : mapping;

      return fileExists(join(skillRoot, candidate.src)) ? candidate : mapping;
    });
  }

  return manifest.template_files;
}

export function renderFileMapping(
  capabilityId: string,
  kind: "template" | "asset",
  mapping: FileMapping,
  context: RenderContext
): RenderedFileMapping {
  const sourcePath = resolveInsideRoot(context.skillRoot, mapping.src);
  const targetPath = resolveInsideRoot(context.targetRoot, mapping.dst);
  const source = readFileSync(sourcePath);

  return {
    capabilityId,
    kind,
    mapping,
    sourcePath,
    targetPath,
    content: renderBuffer(source, context)
  };
}

function renderBuffer(source: Buffer, context: RenderContext): Buffer {
  if (source.includes(0)) {
    return source;
  }

  const rendered = source
    .toString("utf8")
    .replaceAll("__DAYU_DEFAULT_BRANCH__", context.defaultBranch)
    .replaceAll("__DAYU_PROJECT_VERSION__", context.projectVersion)
    .replace(/\{\{dayu:([a-z][a-z0-9]*(?:[._-][a-z0-9]+)+)\}\}/g, (_token, key: string) => {
      const value = context.localeCatalog[key];
      if (!value) {
        throw new CliError("missing-i18n-key", `missing locale key '${key}'`, [
          { code: "missing-i18n-key", message: `missing locale key '${key}'`, path: key }
        ]);
      }
      return value;
    });

  return Buffer.from(rendered, "utf8");
}
