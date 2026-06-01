import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";

export function checkI18nDrift(targetRoot = process.cwd()) {
  const target = resolve(targetRoot);
  const checks: Array<{ name: string; status: "pass" | "fail"; detail: string }> = [];

  for (const readme of ["README.md", "README.en.md"]) {
    checks.push({
      name: "README pair",
      status: existsSync(join(target, readme)) ? "pass" : "fail",
      detail: existsSync(join(target, readme)) ? `存在 ${readme}` : `缺失 README 文件: ${readme}`
    });
  }

  if (existsSync(join(target, "README.md")) && existsSync(join(target, "README.en.md"))) {
    const zh = markdownFormatSignature(join(target, "README.md"));
    const en = markdownFormatSignature(join(target, "README.en.md"));
    checks.push({
      name: "README format parity",
      status: zh === en ? "pass" : "fail",
      detail: zh === en ? "README.md 与 README.en.md 的 Markdown 格式签名一致" : "README.md 与 README.en.md 的 Markdown 格式签名不一致"
    });
  }

  const zhFiles = collectFiles(join(target, "templates"));
  const enFiles = collectFiles(join(target, "templates.en"));
  const zhSet = new Set(zhFiles);
  const enSet = new Set(enFiles);
  const missingInEn = zhFiles.filter((file) => !enSet.has(file));
  const missingInZh = enFiles.filter((file) => !zhSet.has(file));
  checks.push({
    name: "Template tree mirror",
    status: missingInEn.length === 0 && missingInZh.length === 0 ? "pass" : "fail",
    detail:
      missingInEn.length === 0 && missingInZh.length === 0
        ? "templates 与 templates.en 文件树完全一致"
        : `模板树不一致：templates.en 缺 ${missingInEn.join(", ") || "无"}；templates 缺 ${missingInZh.join(", ") || "无"}`
  });

  for (const rel of zhFiles.filter((file) => file.endsWith(".md") && enSet.has(file))) {
    const zh = markdownFormatSignature(join(target, "templates", rel));
    const en = markdownFormatSignature(join(target, "templates.en", rel));
    checks.push({
      name: "Template format parity",
      status: zh === en ? "pass" : "fail",
      detail: zh === en ? `格式一致: ${rel}` : `Markdown 格式签名不一致: ${rel}`
    });
  }

  const failed = checks.filter((check) => check.status === "fail").length;
  return {
    status: failed === 0 ? "pass" : "needs_fix",
    target,
    checks,
    summary: {
      total: checks.length,
      passed: checks.length - failed,
      failed
    },
    description_nl: failed === 0 ? "i18n 漂移检查通过。" : `检测到 i18n 漂移问题：${failed} 项失败。`
  };
}

function collectFiles(root: string): string[] {
  const out: string[] = [];
  walk(root, (path) => out.push(toPosix(relative(root, path))));
  return out.sort();
}

function walk(root: string, visit: (path: string) => void): void {
  if (!existsSync(root)) return;
  for (const entry of readdirSync(root)) {
    const path = join(root, entry);
    const stat = existsSync(path) ? readdirSafe(path) : "missing";
    if (stat === "directory") walk(path, visit);
    if (stat === "file") visit(path);
  }
}

function readdirSafe(path: string): "directory" | "file" | "missing" {
  try {
    readdirSync(path);
    return "directory";
  } catch {
    return existsSync(path) ? "file" : "missing";
  }
}

function markdownFormatSignature(path: string): string {
  return readFileSync(path, "utf8")
    .split(/\r?\n/)
    .map((line) => {
      const trimmed = line.trim();
      if (!trimmed) return "";
      if (/^```/.test(trimmed)) return "code-fence";
      if (/^#{1,6}\s+/.test(trimmed)) return `heading:${trimmed.match(/^#+/)?.[0].length ?? 0}`;
      if (/^[-*+]\s+/.test(trimmed)) return `unordered-list:${line.match(/^\s*/)?.[0].length ?? 0}`;
      if (/^[0-9]+\.\s+/.test(trimmed)) return `ordered-list:${line.match(/^\s*/)?.[0].length ?? 0}`;
      if (/^>/.test(trimmed)) return "blockquote";
      if (/^\|.*\|$/.test(trimmed)) return "table-row";
      if (/^<!--.*-->$/.test(trimmed)) return "html-comment";
      return "";
    })
    .filter(Boolean)
    .join("\n");
}

function toPosix(path: string): string {
  return path.split("\\").join("/");
}
