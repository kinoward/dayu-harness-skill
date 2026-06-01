#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";

const README_PATHS = ["README.md", "README.en.md"];
const CONTRIBUTORS_START = "<!-- contributors:start -->";
const CONTRIBUTORS_END = "<!-- contributors:end -->";
const DEFAULT_REPOSITORY = "kinoward/dayu-harness-skill";

interface GitHubContributor {
  login?: string;
  html_url?: string;
  avatar_url?: string;
}

function resolveRepository(): string {
  if (process.env.GITHUB_REPOSITORY) return process.env.GITHUB_REPOSITORY;

  try {
    const remote = execFileSync("git", ["config", "--get", "remote.origin.url"], {
      encoding: "utf8"
    }).trim();
    const match = remote.match(/github\.com[:/](.+?)(?:\.git)?$/);
    if (match?.[1]) return match[1];
  } catch {
    // Fall back to this repository when git metadata is unavailable.
  }

  return DEFAULT_REPOSITORY;
}

async function fetchContributors(repository: string): Promise<GitHubContributor[]> {
  const headers = githubHeaders();
  const contributors: GitHubContributor[] = [];
  for (let page = 1; page <= 10; page += 1) {
    const url = `https://api.github.com/repos/${repository}/contributors?per_page=100&page=${page}`;
    const response = await fetch(url, { headers });
    if (!response.ok) {
      throw new Error(`GitHub contributors API returned ${response.status} for ${url}`);
    }

    const pageContributors = (await response.json()) as GitHubContributor[];
    contributors.push(...pageContributors);
    if (pageContributors.length < 100) break;
  }

  return contributors;
}

function githubHeaders(): HeadersInit {
  const headers: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "User-Agent": "dayu-harness-skill-readme-updater"
  };

  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  return headers;
}

function renderContributors(contributors: readonly GitHubContributor[], readmePath: string): string {
  if (!contributors.length) {
    const emptyMessage = readmePath.endsWith(".en.md") ? "No contributor data available yet." : "暂无贡献者数据。";
    return `${CONTRIBUTORS_START}\n\n${emptyMessage}\n\n${CONTRIBUTORS_END}`;
  }

  const cells = contributors
    .filter((contributor) => contributor.login && contributor.html_url && contributor.avatar_url)
    .map((contributor) => {
      const login = escapeHtml(contributor.login);
      const profileUrl = escapeHtml(contributor.html_url);
      const avatarUrl = escapeHtml(`${contributor.avatar_url}&s=96`);

      return [
        '    <td align="center" width="96">',
        `      <a href="${profileUrl}">`,
        `        <img src="${avatarUrl}" width="64" height="64" alt="${login}"><br>`,
        `        <sub><b>${login}</b></sub>`,
        "      </a>",
        "    </td>"
      ].join("\n");
    });

  const rows: string[] = [];
  for (let index = 0; index < cells.length; index += 6) {
    rows.push(["  <tr>", ...cells.slice(index, index + 6), "  </tr>"].join("\n"));
  }

  return `${CONTRIBUTORS_START}\n<table>\n${rows.join("\n")}\n</table>\n${CONTRIBUTORS_END}`;
}

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

async function updateReadme(readmePath: string, contributorsBlock: string): Promise<boolean> {
  const readme = await readFile(readmePath, "utf8");

  for (const marker of [CONTRIBUTORS_START, CONTRIBUTORS_END]) {
    if (!readme.includes(marker)) {
      throw new Error(`${readmePath} must contain ${marker}`);
    }
  }

  const nextReadme = readme.replace(
    new RegExp(`${escapeRegex(CONTRIBUTORS_START)}[\\s\\S]*?${escapeRegex(CONTRIBUTORS_END)}`),
    contributorsBlock
  );

  if (nextReadme !== readme) {
    await writeFile(readmePath, nextReadme);
    return true;
  }

  return false;
}

function escapeHtml(value: unknown): string {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

const repository = resolveRepository();
const contributors = await fetchContributors(repository);

for (const readmePath of README_PATHS) {
  const contributorsBlock = renderContributors(contributors, readmePath);
  await updateReadme(readmePath, contributorsBlock);
}
