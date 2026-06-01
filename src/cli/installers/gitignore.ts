import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { writeFileAtomically } from "../filesystem.js";

const SUPPORTED_TYPES = ["Node", "Python", "Go", "Rust", "Java", "VisualStudio"] as const;

type ProjectType = (typeof SUPPORTED_TYPES)[number];

const DAYU_LOCAL_BLOCK = `# === Dayu Harness local exclusions ===
.claude/
skills-lock.json
.dayu-harness/apply.lock
.dayu-harness/journal.jsonl
.dayu-harness/log.jsonl
.dayu-harness/tmp/
.dayu-harness/*.tmp
`;

export function applyGitignoreInstaller(input: {
  targetRoot: string;
  skillRoot: string;
  strategy: "merge" | "replace" | "skip";
}): void {
  if (input.strategy === "skip") {
    return;
  }

  const gitignorePath = join(input.targetRoot, ".gitignore");
  const projectTypes = detectProjectTypes(input.targetRoot);
  const combined = emitCombinedTemplate(input.skillRoot, projectTypes);

  if (input.strategy === "replace" || !existsSync(gitignorePath)) {
    writeFileAtomically(gitignorePath, combined);
    return;
  }

  const existing = readFileSync(gitignorePath, "utf8");
  const sections: string[] = [];

  const universal = readOptional(join(input.skillRoot, "assets", "gitignore", "universal.gitignore"));
  if (universal) {
    const missing = missingLines(universal, existing);
    if (missing.length > 0) {
      sections.push(section("universal.gitignore", missing));
    }
  }

  for (const type of projectTypes) {
    const template = readOptional(templatePathForType(input.skillRoot, type));
    if (!template) {
      continue;
    }
    const missing = missingLines(template, existing);
    if (missing.length > 0) {
      sections.push(section(`github/gitignore ${type}.gitignore snapshot`, missing));
    }
  }

  const localMissing = missingLines(DAYU_LOCAL_BLOCK, existing);
  if (localMissing.length > 0) {
    sections.push(section("Dayu Harness local exclusions", localMissing));
  }

  if (sections.length > 0) {
    writeFileAtomically(gitignorePath, `${existing.replace(/\s*$/, "\n")}${sections.join("")}`);
  }
}

export function gitignoreAlreadyManaged(targetRoot: string): boolean {
  const gitignorePath = join(targetRoot, ".gitignore");
  return existsSync(gitignorePath) && readFileSync(gitignorePath, "utf8").includes("Dayu Harness local exclusions");
}

function detectProjectTypes(targetRoot: string): ProjectType[] {
  const types = new Set<ProjectType>();

  if (
    existsSync(join(targetRoot, "package.json")) ||
    existsSync(join(targetRoot, "package-lock.json")) ||
    existsSync(join(targetRoot, "pnpm-lock.yaml")) ||
    existsSync(join(targetRoot, "yarn.lock"))
  ) {
    types.add("Node");
  }
  if (
    existsSync(join(targetRoot, "requirements.txt")) ||
    existsSync(join(targetRoot, "setup.py")) ||
    existsSync(join(targetRoot, "pyproject.toml")) ||
    findAnyFile(targetRoot, ".py")
  ) {
    types.add("Python");
  }
  if (existsSync(join(targetRoot, "go.mod")) || findAnyFile(targetRoot, ".go")) {
    types.add("Go");
  }
  if (existsSync(join(targetRoot, "Cargo.toml")) || findAnyFile(targetRoot, ".rs")) {
    types.add("Rust");
  }
  if (
    existsSync(join(targetRoot, "pom.xml")) ||
    existsSync(join(targetRoot, "build.gradle")) ||
    existsSync(join(targetRoot, "build.gradle.kts")) ||
    findAnyFile(targetRoot, ".java")
  ) {
    types.add("Java");
  }
  if (findAnyFile(targetRoot, ".sln") || findAnyFile(targetRoot, ".csproj") || findAnyFile(targetRoot, ".fsproj") || findAnyFile(targetRoot, ".vbproj")) {
    types.add("VisualStudio");
  }

  if (types.size === 0) {
    types.add("Node");
  }

  return [...types];
}

function findAnyFile(root: string, suffix: string): boolean {
  const ignored = new Set([".git", "node_modules", ".claude"]);
  const stack = [root];

  while (stack.length > 0) {
    const dir = stack.pop()!;
    let entries: string[];
    try {
      entries = readdirSync(dir);
    } catch {
      continue;
    }

    for (const entry of entries) {
      if (ignored.has(entry)) {
        continue;
      }
      const path = join(dir, entry);
      try {
        const stat = existsSync(path) ? readdirOrFile(path) : "missing";
        if (stat === "directory") {
          stack.push(path);
        } else if (stat === "file" && entry.endsWith(suffix)) {
          return true;
        }
      } catch {
        continue;
      }
    }
  }

  return false;
}

function readdirOrFile(path: string): "directory" | "file" | "missing" {
  try {
    const dirEntries = readdirSync(path);
    void dirEntries;
    return "directory";
  } catch {
    return existsSync(path) ? "file" : "missing";
  }
}

function emitCombinedTemplate(skillRoot: string, projectTypes: readonly ProjectType[]): string {
  const parts: string[] = [];
  const universal = readOptional(join(skillRoot, "assets", "gitignore", "universal.gitignore"));
  if (universal) {
    parts.push(`# === universal.gitignore ===\n${universal.trimEnd()}\n`);
  }

  for (const type of projectTypes) {
    const template = readOptional(templatePathForType(skillRoot, type));
    if (template) {
      parts.push(`# === github/gitignore ${type}.gitignore snapshot ===\n${template.trimEnd()}\n`);
    }
  }

  parts.push(DAYU_LOCAL_BLOCK.trimEnd());
  return `${parts.join("\n\n")}\n`;
}

function templatePathForType(skillRoot: string, type: ProjectType): string {
  return join(skillRoot, "assets", "gitignore", "github", `${type}.gitignore`);
}

function readOptional(path: string): string | undefined {
  return existsSync(path) ? readFileSync(path, "utf8") : undefined;
}

function missingLines(template: string, existing: string): string[] {
  const existingLines = new Set(existing.split(/\r?\n/));
  return template
    .split(/\r?\n/)
    .map((line) => line.trimEnd())
    .filter((line) => line.length > 0 && !existingLines.has(line));
}

function section(title: string, lines: readonly string[]): string {
  return `\n# === Added by dayu-harness: ${title} ===\n${lines.join("\n")}\n`;
}
