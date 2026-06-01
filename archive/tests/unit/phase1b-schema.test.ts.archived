import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  DAYU_CONFIG_SCHEMA_VERSION,
  DayuConfigSchema,
  LocaleCatalogSchema,
  MANIFEST_SCHEMA_VERSION,
  ManifestV2Schema,
  collectManifestI18nKeys,
  extractDayuI18nKeys,
  formatZodError,
  missingLocaleKeys,
  parseDayuConfigYaml,
  validateDayuConfigCapabilities
} from "../../src/schemas/index.js";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));
const phase1bCapabilityIds = ["core", "git.hooks", "git.commit-format", "ai.execution"] as const;

function readJson(relativePath: string): unknown {
  return JSON.parse(readFileSync(join(repoRoot, relativePath), "utf8"));
}

function readManifest(id: (typeof phase1bCapabilityIds)[number]): Record<string, unknown> {
  return readJson(`capabilities/${id}.json`) as Record<string, unknown>;
}

test("Phase 1b trial capability manifests validate against manifest v2 schema", () => {
  const parsed = phase1bCapabilityIds.map((id) => ManifestV2Schema.parse(readManifest(id)));

  assert.deepEqual(
    parsed.map((manifest) => [manifest.id, manifest.schemaVersion, manifest.kind]),
    [
      ["core", MANIFEST_SCHEMA_VERSION, "infra"],
      ["git.hooks", MANIFEST_SCHEMA_VERSION, "infra"],
      ["git.commit-format", MANIFEST_SCHEMA_VERSION, "hard"],
      ["ai.execution", MANIFEST_SCHEMA_VERSION, "soft"]
    ]
  );

  const commitFormat = parsed.find((manifest) => manifest.id === "git.commit-format");
  assert.ok(commitFormat);
  assert.deepEqual(commitFormat.deployment_deps, ["core", "git.hooks"]);
  assert.deepEqual(commitFormat.conceptual_deps, []);
  assert.ok(commitFormat.rse.rule);
  assert.ok(commitFormat.rse.sensor);
  assert.ok(commitFormat.rse.enforcer);
});

test("manifest v2 schema rejects missing schemaVersion with readable field path", () => {
  const invalid = structuredClone(readManifest("core"));
  delete invalid.schemaVersion;

  const result = ManifestV2Schema.safeParse(invalid);
  assert.equal(result.success, false);
  if (!result.success) {
    assert.match(formatZodError(result.error), /schemaVersion/);
  }
});

test("manifest v2 schema requires legacy dependencies to mirror deployment_deps in Phase 1", () => {
  const missingLegacyDeps = structuredClone(readManifest("ai.execution"));
  delete missingLegacyDeps.dependencies;

  const missingResult = ManifestV2Schema.safeParse(missingLegacyDeps);
  assert.equal(missingResult.success, false);
  if (!missingResult.success) {
    assert.match(formatZodError(missingResult.error), /dependencies/);
  }

  const mismatchedLegacyDeps = structuredClone(readManifest("git.commit-format"));
  mismatchedLegacyDeps.dependencies = ["core"];

  const mismatchedResult = ManifestV2Schema.safeParse(mismatchedLegacyDeps);
  assert.equal(mismatchedResult.success, false);
  if (!mismatchedResult.success) {
    assert.match(formatZodError(mismatchedResult.error), /legacy dependencies must mirror deployment_deps/);
  }
});

test("manifest v2 schema rejects incomplete hard RSE chains", () => {
  const invalid = structuredClone(readManifest("git.commit-format"));
  invalid.rse = {
    ...(invalid.rse as Record<string, unknown>),
    enforcer: null
  };

  const result = ManifestV2Schema.safeParse(invalid);
  assert.equal(result.success, false);
  if (!result.success) {
    assert.match(formatZodError(result.error), /hard capabilities require rule, sensor, and enforcer/);
  }
});

test("manifest v2 schema rejects unsafe managed paths across schema surfaces", () => {
  const cases: Array<[string, (manifest: Record<string, unknown>) => void, RegExp]> = [
    [
      "template dst traversal",
      (manifest) => {
        const templateFiles = manifest.template_files as Array<Record<string, unknown>>;
        templateFiles[0] = { ...templateFiles[0], dst: "../AGENTS.md" };
      },
      /path must not contain traversal segments/
    ],
    [
      "template src absolute path",
      (manifest) => {
        const templateFiles = manifest.template_files as Array<Record<string, unknown>>;
        templateFiles[0] = { ...templateFiles[0], src: "/tmp/AGENTS.md" };
      },
      /path must be relative to the project root/
    ],
    [
      "asset dst Windows drive path",
      (manifest) => {
        const assetFiles = manifest.asset_files as Array<Record<string, unknown>>;
        assetFiles[0] = { ...assetFiles[0], dst: "C:\\temp\\commitlint.config.cjs" };
      },
      /path must be relative to the project root/
    ],
    [
      "asset dst UNC path",
      (manifest) => {
        const assetFiles = manifest.asset_files as Array<Record<string, unknown>>;
        assetFiles[0] = { ...assetFiles[0], dst: "\\\\server\\share\\commitlint.config.cjs" };
      },
      /path must be relative to the project root/
    ],
    [
      "installer script traversal",
      (manifest) => {
        const installer = manifest.installer as Record<string, unknown>;
        manifest.installer = { ...installer, script: "../install-husky.sh" };
      },
      /path must not contain traversal segments/
    ],
    [
      "RSE artifact traversal",
      (manifest) => {
        const rse = manifest.rse as Record<string, Record<string, unknown>>;
        const rule = rse.rule;
        manifest.rse = {
          ...rse,
          rule: {
            ...rule,
            artifacts: ["../docs/harness/guides/commit-guidelines.md"]
          }
        };
      },
      /path must not contain traversal segments/
    ]
  ];

  for (const [name, mutate, expected] of cases) {
    const invalid = structuredClone(readManifest("git.commit-format"));
    mutate(invalid);

    const result = ManifestV2Schema.safeParse(invalid);
    assert.equal(result.success, false, name);
    if (!result.success) {
      assert.match(formatZodError(result.error), expected, name);
    }
  }
});

test("dayu.config.yaml schema parses versioned Skill to CLI handoff config", () => {
  const config = parseDayuConfigYaml(`
schemaVersion: "${DAYU_CONFIG_SCHEMA_VERSION}"
locale: zh-CN
project:
  name: fixture-project
capabilities:
  - id: core
  - id: git.commit-format
  - id: ai.execution
    enabled: true
`);

  assert.equal(config.schemaVersion, DAYU_CONFIG_SCHEMA_VERSION);
  assert.equal(config.locale, "zh");
  assert.deepEqual(
    config.capabilities.map((capability) => [capability.id, capability.enabled]),
    [
      ["core", true],
      ["git.commit-format", true],
      ["ai.execution", true]
    ]
  );
});

test("dayu.config.yaml registry validation reports unknown capability ids", () => {
  const config = parseDayuConfigYaml(`
schemaVersion: "${DAYU_CONFIG_SCHEMA_VERSION}"
locale: en-US
capabilities:
  - id: core
  - id: unknown.capability
`);

  assert.equal(config.locale, "en");
  assert.deepEqual(validateDayuConfigCapabilities(config, phase1bCapabilityIds), ["unknown.capability"]);
  assert.deepEqual(validateDayuConfigCapabilities(config, ["core", "unknown.capability"]), []);
});

test("dayu.config.yaml schema rejects unsupported versions and duplicate capabilities", () => {
  const unsupportedVersion = DayuConfigSchema.safeParse({
    schemaVersion: "0.9.0",
    capabilities: [{ id: "core" }]
  });
  assert.equal(unsupportedVersion.success, false);
  if (!unsupportedVersion.success) {
    assert.match(formatZodError(unsupportedVersion.error), /schemaVersion/);
  }

  const duplicateCapabilities = DayuConfigSchema.safeParse({
    schemaVersion: DAYU_CONFIG_SCHEMA_VERSION,
    capabilities: [{ id: "core" }, { id: "core" }]
  });
  assert.equal(duplicateCapabilities.success, false);
  if (!duplicateCapabilities.success) {
    assert.match(formatZodError(duplicateCapabilities.error), /duplicate capability 'core'/);
  }
});

test("locale catalogs cover all Phase 1b manifest i18n keys", () => {
  const zh = LocaleCatalogSchema.parse(readJson("locales/zh.json"));
  const en = LocaleCatalogSchema.parse(readJson("locales/en.json"));
  const requiredKeys = new Set<string>();

  for (const id of phase1bCapabilityIds) {
    const manifest = ManifestV2Schema.parse(readManifest(id));
    for (const key of collectManifestI18nKeys(manifest)) {
      requiredKeys.add(key);
    }
  }

  assert.deepEqual(missingLocaleKeys(zh, requiredKeys), []);
  assert.deepEqual(missingLocaleKeys(en, requiredKeys), []);
});

test("dayu i18n token extraction uses the namespaced placeholder format", () => {
  assert.deepEqual(
    extractDayuI18nKeys(
      "Deploy {{dayu:capability.core.title}} with {{dayu:config.schema.version}} and {{dayu:capability.core.title}}."
    ),
    ["capability.core.title", "config.schema.version"]
  );
});
