#!/usr/bin/env node
// Deterministic renderer for fixed-format Dayu Harness content.

const VALID_COMMIT_TYPES = new Set([
  "feat",
  "fix",
  "docs",
  "style",
  "refactor",
  "perf",
  "test",
  "build",
  "ci",
  "chore",
  "revert",
]);

function usage() {
  console.error(`Usage:
  dayu-format.mjs pr-body --summary TEXT --implementation TEXT --test-command CMD --issue N [--final yes|no]
  dayu-format.mjs issue-body --summary TEXT [--background TEXT] [--depends-on N[,N]]
  dayu-format.mjs commit-message --type TYPE [--scope SCOPE] --subject TEXT`);
}

function fail(message) {
  console.error(`ERROR: ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const options = new Map();
  const mode = argv.shift();

  while (argv.length > 0) {
    const key = argv.shift();
    if (!key || !key.startsWith("--")) {
      fail(`Unexpected argument: ${key || ""}`);
    }
    if (argv.length === 0 || argv[0].startsWith("--")) {
      fail(`${key} requires a value`);
    }
    const name = key.slice(2);
    const value = argv.shift();
    if (!options.has(name)) {
      options.set(name, []);
    }
    options.get(name).push(value);
  }

  return { mode, options };
}

function values(options, name) {
  return options.get(name) || [];
}

function value(options, name, fallback = "") {
  const found = values(options, name);
  return found.length > 0 ? found[found.length - 1] : fallback;
}

function requiredValues(options, name) {
  const found = values(options, name)
    .map(cleanInline)
    .filter(Boolean);
  if (found.length === 0) {
    fail(`--${name} is required`);
  }
  return found;
}

function cleanInline(raw) {
  return String(raw || "")
    .replace(/\r/g, "")
    .replace(/\n+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function parseIssueNumber(raw) {
  const cleaned = cleanInline(raw).replace(/^#/, "");
  if (!/^[1-9][0-9]*$/.test(cleaned)) {
    fail("--issue must be a positive issue number");
  }
  return cleaned;
}

function renderBullets(lines) {
  return lines.map((line) => `- ${line}`).join("\n");
}

function renderPrBody(options) {
  const summaries = requiredValues(options, "summary");
  const implementation = requiredValues(options, "implementation");
  const commands = requiredValues(options, "test-command");
  const issue = parseIssueNumber(value(options, "issue"));
  const finalValue = cleanInline(value(options, "final", "yes")).toLowerCase();
  const isFinal = !["no", "false"].includes(finalValue);
  const finalLine = isFinal ? "Final PR: yes" : "Final PR: no";
  const trailer = isFinal ? `Closes #${issue}` : `Refs #${issue}`;

  const testPlan = commands
    .map((command) => cleanInline(command))
    .filter(Boolean)
    .map((command) => `- [x] \`${command.replace(/`/g, "'")}\``)
    .join("\n");

  if (!testPlan) {
    fail("--test-command must contain at least one executable command");
  }

  return `## Summary
<!-- dayu-harness:summary -->

${renderBullets(summaries)}

## Implementation notes
<!-- dayu-harness:implementation-notes -->

${renderBullets(implementation)}

## Test plan
<!-- dayu-harness:test-plan -->

${testPlan}

${finalLine}
${trailer}
`;
}

function parseDependsOn(rawValues) {
  const tokens = rawValues
    .flatMap((raw) => String(raw || "").split(","))
    .map((token) => token.trim().replace(/^#/, ""))
    .filter(Boolean);

  if (tokens.some((token) => !/^[1-9][0-9]*$/.test(token))) {
    fail("--depends-on accepts positive issue numbers, optionally comma-separated");
  }

  return tokens;
}

function renderIssueBody(options) {
  const summaries = requiredValues(options, "summary");
  const background = values(options, "background")
    .map(cleanInline)
    .filter(Boolean);
  const dependencies = parseDependsOn(values(options, "depends-on"));
  const dependencyLine =
    dependencies.length > 0
      ? `\nDepends on: ${dependencies.map((item) => `#${item}`).join(", ")}\n`
      : "";

  const backgroundBlock =
    background.length > 0
      ? `\n## Background\n\n${renderBullets(background)}\n`
      : "";

  return `## Summary

${renderBullets(summaries)}
${backgroundBlock}${dependencyLine}`;
}

function renderCommitMessage(options) {
  const type = cleanInline(value(options, "type"));
  const scope = cleanInline(value(options, "scope"));
  const subject = cleanInline(value(options, "subject"));

  if (!VALID_COMMIT_TYPES.has(type)) {
    fail(`--type must be one of: ${Array.from(VALID_COMMIT_TYPES).join(", ")}`);
  }
  if (!subject) {
    fail("--subject is required");
  }
  if (scope && !/^[A-Za-z0-9._-]+$/.test(scope)) {
    fail("--scope may contain only letters, numbers, dot, underscore, and dash");
  }

  return `${type}${scope ? `(${scope})` : ""}: ${subject}\n`;
}

const { mode, options } = parseArgs(process.argv.slice(2));

if (!mode || mode === "--help" || mode === "-h") {
  usage();
  process.exit(mode ? 0 : 1);
}

switch (mode) {
  case "pr-body":
    process.stdout.write(renderPrBody(options));
    break;
  case "issue-body":
    process.stdout.write(renderIssueBody(options));
    break;
  case "commit-message":
    process.stdout.write(renderCommitMessage(options));
    break;
  default:
    usage();
    fail(`Unknown mode: ${mode}`);
}
