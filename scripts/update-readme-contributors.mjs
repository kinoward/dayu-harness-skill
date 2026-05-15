#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";

const README_PATH = "README.md";
const START = "<!-- contributors:start -->";
const END = "<!-- contributors:end -->";
const DEFAULT_REPOSITORY = "kinoward/dayu-harness-skill";

function resolveRepository() {
  if (process.env.GITHUB_REPOSITORY) return process.env.GITHUB_REPOSITORY;

  try {
    const remote = execFileSync("git", ["config", "--get", "remote.origin.url"], {
      encoding: "utf8",
    }).trim();
    const match = remote.match(/github\.com[:/](.+?)(?:\.git)?$/);
    if (match) return match[1];
  } catch {
    // Fall back to this repository when git metadata is unavailable.
  }

  return DEFAULT_REPOSITORY;
}

async function fetchContributors(repository) {
  const headers = {
    Accept: "application/vnd.github+json",
    "User-Agent": "dayu-harness-skill-readme-contributors",
  };

  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }

  const contributors = [];
  for (let page = 1; page <= 10; page += 1) {
    const url = `https://api.github.com/repos/${repository}/contributors?per_page=100&page=${page}`;
    const response = await fetch(url, { headers });
    if (!response.ok) {
      throw new Error(`GitHub contributors API returned ${response.status} for ${url}`);
    }

    const pageContributors = await response.json();
    contributors.push(...pageContributors);
    if (pageContributors.length < 100) break;
  }

  return contributors;
}

function renderContributors(contributors) {
  if (!contributors.length) {
    return `${START}\n\n暂无贡献者数据。\n\n${END}`;
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
        "    </td>",
      ].join("\n");
    });

  const rows = [];
  for (let index = 0; index < cells.length; index += 6) {
    rows.push(["  <tr>", ...cells.slice(index, index + 6), "  </tr>"].join("\n"));
  }

  return `${START}\n<table>\n${rows.join("\n")}\n</table>\n${END}`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

const repository = resolveRepository();
const contributors = await fetchContributors(repository);
const block = renderContributors(contributors);
const readme = await readFile(README_PATH, "utf8");

if (!readme.includes(START) || !readme.includes(END)) {
  throw new Error(`README.md must contain ${START} and ${END} markers`);
}

const nextReadme = readme.replace(new RegExp(`${START}[\\s\\S]*?${END}`), block);

if (nextReadme !== readme) {
  await writeFile(README_PATH, nextReadme);
}
