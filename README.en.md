<div align="center">

<img src="assets/readme/dayu-harness-banner.png" alt="Dayu Harness Skill banner" width="100%">

<br>

# Dayu Harness Skill

### *“Turn one-off AI collaboration prompts into long-running repository governance.”*

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![AgentSkills](https://img.shields.io/badge/AgentSkills-Standard-green)](https://agentskills.io)
[![Stars](https://img.shields.io/github/stars/kinoward/dayu-harness-skill?style=social)](https://github.com/kinoward/dayu-harness-skill/stargazers)

[![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-blueviolet)](https://claude.ai/code)
[![Hermes](https://img.shields.io/badge/Hermes-Skill-orange)](https://github.com/kinoward/dayu-harness-skill)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-Skill-teal)](https://github.com/kinoward/dayu-harness-skill)
[![Codex](https://img.shields.io/badge/Codex-Skill-black)](https://github.com/kinoward/dayu-harness-skill)

<br>

中文说明文档见 [README.md](README.md)。

<br>

<table>
<tr><td align="left">

🤖 &nbsp;Has your project already started letting agents join development, review, troubleshooting, and documentation maintenance?<br>
📚 &nbsp;Are your rules still scattered across chat logs, PR comments, team conventions, and old documents?<br>
🧭 &nbsp;Do you want the project to keep knowing how to collaborate, check, and retain experience after the Skill is removed?

</td></tr>
</table>

### ✨ Dayu Harness can handle these problems.

<br>

From **one-off prompts to repository-level governance**, so rules no longer stay trapped in a single conversation.

Chat logs · PR comments · team conventions · old documents · troubleshooting experience can all become reviewable project assets.

**Maps, guides, check scripts, and automation feedback** go to their proper places, so the project knows how to collaborate, check, and retain knowledge.

<br>

[🧭 Introduction](#-introduction) · [🚀 Quick Start and Use](#-quick-start-and-use) · [📦 What Will Be Generated](#-what-will-be-generated) · [🌐 Bilingual Deployment](#-bilingual-deployment)

[📁 Project Structure](#-project-structure) · [🔎 More Details](#-more-details) · [📚 References](#-references) · [🤝 Contributing](#-contributing) · [⭐ Star History](#-star-history)

</div>

---

## 🧭 Introduction

Your project may already be letting agents participate in development, review, troubleshooting, and documentation maintenance, but are its rules still scattered across chat logs, PR comments, team conventions, and old documents?

Dayu Harness Skill is designed for [Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/)-style project governance. It is not about making one Agent obey better in one conversation; it deploys long-term rules into the target repository, making `AGENTS.md`, `docs/`, hooks, CI, and maintenance scripts the actual authority for collaboration.

The name “Dayu” comes from Great Yu’s flood-control story: do not block the current at one point, but guide, divide, and establish long-term order. This Skill follows the same goal: convert one-off prompts, constraints, and experience into versioned, reviewable, and portable governance assets.

## 🎯 When It Fits

- A new project wants an `AGENTS.md` root index, layered docs, and baseline engineering constraints from day one.
- An existing project has scattered docs, hooks, CI, or commit rules that need to be fused into a maintainable governance system.
- A team wants AI collaboration experience to persist instead of staying in unsearchable chat logs.
- A project needs portable rules across Claude Code, Codex, and general Agent Skills clients.

## 🚀 Quick Start and Use

Install this Skill only into the target repository that needs governance. Do not install it globally, and do not commit the Skill installation directory into the target project. Dayu Harness Skill is a one-time scaffold, fuse, diagnose, and maintenance entrypoint; after use it can be removed, while the long-lived effect remains in the target project’s `AGENTS.md`, `docs/`, hooks, CI, and check scripts.

### ⚡ Recommended: Vercel skills CLI

```bash
cd <target-project>
npx skills add kinoward/dayu-harness-skill
```

If you want to target a specific client explicitly:

```bash
# Claude Code -> .claude/skills/
npx skills add kinoward/dayu-harness-skill -a claude-code

# Codex -> .agents/skills/
npx skills add kinoward/dayu-harness-skill -a codex
```

After installation, open your Agent client in the target project and enter:

```text
/dayu-harness
```

Then follow the prompts to initialize, fuse existing rules, diagnose project completeness, or maintain current governance content. The Skill analyzes repository state first and proposes a change plan; existing hooks, CI, lint, and release configs receive merge plans instead of being overwritten directly.

After use, remove it with:

```bash
npx skills remove dayu-harness
```

<details>
<summary>Manual installation for Claude Code or Codex</summary>

For manual installation, copy the files and remove the nested `.git` directory to avoid leaving a nested Git repository in the target project.

Claude Code:

```bash
cd <target-project>
tmp_dir="$(mktemp -d)"
git clone --depth 1 https://github.com/kinoward/dayu-harness-skill.git "$tmp_dir/dayu-harness-skill"
mkdir -p .claude/skills
cp -R "$tmp_dir/dayu-harness-skill" .claude/skills/dayu-harness
rm -rf .claude/skills/dayu-harness/.git "$tmp_dir"
```

Codex:

```bash
cd <target-project>
tmp_dir="$(mktemp -d)"
git clone --depth 1 https://github.com/kinoward/dayu-harness-skill.git "$tmp_dir/dayu-harness-skill"
mkdir -p .agents/skills
cp -R "$tmp_dir/dayu-harness-skill" .agents/skills/dayu-harness
rm -rf .agents/skills/dayu-harness/.git "$tmp_dir"
```

Remove:

```bash
rm -rf .claude/skills/dayu-harness
rm -rf .agents/skills/dayu-harness
```

</details>

## 📦 What Will Be Generated

Dayu Harness Skill organizes project collaboration rules into the target repository. Common outputs include:

- A root `AGENTS.md` governance entrypoint and required subdirectory indexes.
- Collaboration guides, maintenance instructions, and check scripts under `docs/harness/`.
- Git hooks, CI workflows, commit conventions, PR guidelines, and quality check configs.
- The `dayu-format.mjs` fixed-format renderer for deterministic PR bodies, issue bodies, and commit messages.
- Long-lived knowledge directories such as `docs/design-docs/`, `docs/troubleshooting/`, and `docs/references/`.
- Repository settings policy docs, Issue dependency guidance, configurable TDD gate strategy files, and GitHub remote settings sync only after user confirmation.
- `docs/product-specs/project-status.md` as a short project status snapshot entry point.

These files stay in the target project and become the authority for future collaboration.

## 🌐 Bilingual Deployment

Dayu Harness Skill uses Chinese as the source language and recommends Chinese deployment by default; English content is mirrored from the Chinese semantics to help English users understand, not to rewrite the Chinese intent in reverse.

When running `/dayu-harness`, interactive questions and options are shown bilingually in Chinese and English, so English users can still choose correctly. Deployment writes only one language into the target project, defaults to Chinese, and writes English artifacts only when English is explicitly selected.

`templates/` is the Chinese source template tree, and `templates.en/` is the English mirror template tree. The two directories stay isomorphic; maintainers can use the drift check script to confirm the README mirror, template trees, capability mappings, and bilingual Q&A remain aligned.

The Q&A flow is grouped into blocking decision blocks, including version conflicts, GitHub remote creation, `.husky`/workflow merge, tracked `.claude` handling, and protected-branch scenarios, and always uses fixed bilingual options without requiring manual command input.

## 📁 Project Structure

The README only shows a high-level structure; the complete directory tree and ownership boundaries are maintained in AGENTS.md as the repository's long-lived governance source of truth.

- Entry points & indexes: `README.md`, `README.en.md`, `AGENTS.md` (including subdirectory indexes)
- Capabilities, schema, architecture contracts & deployment engine: `capabilities/`, `src/`, `locales/`, `templates/`, `templates.en/`, `assets/`, `scripts/`
- Local validation toolchain: `package.json`, `tsconfig.json`, `tests/unit/phase1b-schema.test.ts`, `tests/unit/phase1c-architecture.test.ts`, `tests/unit/phase1d-cli.test.ts`, `tests/unit/phase1e-cli-scope.test.ts`
- Outputs & maintenance materials: `docs/`, `marketing/`, `tests/`
- Publishing & repository automation: `.github/workflows/update-contributors.yml` refreshes README dynamic blocks; GitHub capability workflow, ruleset, and policy templates live under `assets/github/`

Full repository tree is in [AGENTS.md](AGENTS.md).

## 🔎 More Details

- To understand the Skill behavior definition: read [SKILL.md](SKILL.md).
- To understand repository maintenance rules, capability lists, script flow, and test baseline: read [AGENTS.md](AGENTS.md).
- To understand compatibility across Agent clients: read [references/agent-compatibility.md](references/agent-compatibility.md).

## 📚 References

- [WeChat Official Account “浮之静”: Deep Analysis: Harness Engineering](https://mp.weixin.qq.com/s/-mgf8K7XZrTKoD0pMOIn3w): reference for project governance and AI collaboration concepts.
- [OpenAI: Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/): philosophical source for this Skill.
- [deusyu/harness-engineering](https://github.com/deusyu/harness-engineering): reference for README information layering, concept-first narrative, and AGENTS.md progressive disclosure practice.
- [Martin Fowler: Harness Engineering](https://martinfowler.com/articles/harness-engineering.html): reference for the Guides and Sensors cybernetic framework.
- [agentsmd/agents.md](https://github.com/agentsmd/agents.md): AGENTS.md open format specification.
- [microsoft/skills](https://github.com/microsoft/skills): skill declaration and client compatibility practice.

## 🤝 Contributing

Issues and PRs are welcome: bug reports, usage feedback, compatibility adaptations, and documentation improvements are all valuable.

> [!TIP]
>
> We hope this repository becomes a technical sharing project: preserving good practices, failure experience, check scripts, and governance constraints from AI collaboration so more projects can reuse them.
> We also welcome product feature and usage feedback to help improve Dayu Harness Skill.
>
> **Organization maintainer:** [@kinoward](https://github.com/kinoward)

[![Issue](https://img.shields.io/badge/Issue-Open-blue.svg)][github-issues-link]
[![PRs](https://img.shields.io/badge/PRs-Open-brightgreen.svg)][github-prs-link]

[github-issues-link]: https://github.com/kinoward/dayu-harness-skill/issues
[github-prs-link]: https://github.com/kinoward/dayu-harness-skill/pulls

<!-- contributors:start -->
<table>
  <tr>
    <td align="center" width="96">
      <a href="https://github.com/kinoward">
        <img src="https://avatars.githubusercontent.com/u/33886943?v=4&amp;s=96" width="64" height="64" alt="kinoward"><br>
        <sub><b>kinoward</b></sub>
      </a>
    </td>
  </tr>
</table>
<!-- contributors:end -->

## ⭐ Star History

<a href="https://www.star-history.com/?repos=kinoward%2Fdayu-harness-skill&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/image?repos=kinoward/dayu-harness-skill&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/image?repos=kinoward/dayu-harness-skill&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/image?repos=kinoward/dayu-harness-skill&type=date&legend=top-left" />
 </picture>
</a>

---

<div align="center">

<p><strong>MIT License</strong> © <a href="https://github.com/kinoward">kinoward</a></p>

<sub>Made with 🌊 for projects that want AI collaboration rules to keep flowing after the chat ends.</sub>

</div>
