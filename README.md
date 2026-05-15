<div align="center">

# 🌊 Dayu Harness Skill（大禹治库.skill）

### *“把一次性的 AI 协作提示，疏导成项目里长期可运行的治理体系。”*

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![One-shot Deploy](https://img.shields.io/badge/One--shot-Deploy-6C5CE7)](scripts/scaffold.sh)
[![AgentSkills](https://img.shields.io/badge/AgentSkills-Standard-green)](https://agentskills.io)
[![Stars](https://img.shields.io/github/stars/kinoward/dayu-harness-skill?style=social)](https://github.com/kinoward/dayu-harness-skill/stargazers)

[![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-blueviolet)](https://claude.ai/code)
[![Hermes](https://img.shields.io/badge/Hermes-Skill-orange)](https://github.com/kinoward/dayu-harness-skill)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-Skill-teal)](https://github.com/kinoward/dayu-harness-skill)
[![Codex](https://img.shields.io/badge/Codex-Skill-black)](https://github.com/kinoward/dayu-harness-skill)

<br>

<table>
<tr><td align="left">

🤖 &nbsp;你的项目已经开始让智能体参与开发、审查、排障和文档维护？<br>
📚 &nbsp;你的规则还散在聊天记录、PR 评论、团队口头约定和旧文档里？<br>
🧭 &nbsp;你希望 Skill 删除之后，项目仍然知道怎么协作、怎么检查、怎么沉淀经验？

</td></tr>
</table>

### ✨ 这些，大禹治库都能解决。

<br>

从 **一次性提示升级成仓库级治理体系**，不再让规则只停留在某次对话里。

聊天记录 · PR 评论 · 团队口头约定 · 旧文档 · 排障经验，都可以被整理成可审查的项目资产。

**地图、指南、检查脚本和自动化反馈**各归其位，让项目自己知道怎么协作、怎么检查、怎么沉淀。

<br>

[🧭 前言](#前言) · [🚀 快速开始](#快速开始) · [🧩 使用方式](#使用方式) · [📦 会生成什么](#会生成什么) · [🔎 更多细节](#更多细节)

[🤝 参与贡献](#-参与贡献) · [⭐ Star History](#-star-history)

</div>

---

## 前言

你的项目已经开始让智能体参与开发、审查、排障和文档维护，但规则还散在聊天记录、PR 评论、团队口头约定和旧文档里？

Dayu Harness Skill 面向 [Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/) 风格的项目治理而设计。它不是让某个 Agent 在某次对话里更听话，而是把长期规则部署进目标仓库，让 `AGENTS.md`、`docs/`、hooks、CI 和维护脚本成为项目协作的实际权威。

“大禹”取自大禹治水：不把洪流堵在一处，而是疏导、分流并建立长期秩序。本 Skill 的目标也是如此：把一次性的提示词、约束和经验，整理成可版本化、可审查、可迁移的治理资产。

## 适合场景

- 新项目希望从第一天就建立 `AGENTS.md` 根索引、文档分层和基础工程约束。
- 旧项目已有零散文档、hooks、CI 或提交规则，需要融合成可维护的治理体系。
- 团队希望 AI 协作经验能持续沉淀，而不是留在不可检索的聊天记录里。
- 项目需要在 Claude Code、Codex 和通用 Agent Skills 客户端之间保持可迁移规则。

## 快速开始

在目标项目目录安装（默认即为项目级安装，不会写入用户全局目录）：

推荐安装方式（Vercel `skills` CLI）：

```bash
cd <target-project>

# 项目目录安装（默认作用域），不带 -g
npx skills add kinoward/dayu-harness-skill --yes
```

安装完成后在项目中运行：

```text
/dayu-harness
```

移除（可选）：

```bash
npx skills remove <skill-name>
```

## 使用方式

1. 在目标项目目录安装 Skill。
2. 在该项目中运行 `/dayu-harness`。
3. 按提示选择初始化、融合已有规则、诊断项目完整性，或维护现有治理内容。
4. 根据 Skill 生成的计划确认变更；已有 hooks、CI、lint 和发布配置会先给出合并方案。

## 会生成什么

Dayu Harness Skill 会把项目协作规则整理到目标仓库中，常见产物包括：

- `AGENTS.md` 根治理入口，以及必要的子目录索引。
- `docs/harness/` 下的协作指南、维护说明和检查脚本。
- Git hooks、CI 工作流、提交规范、PR 指南和质量检查配置。
- `docs/design-docs/`、`docs/troubleshooting/`、`docs/references/` 等长期知识目录。

它不是长期运行的后台服务。初始化或升级完成后，长期生效的是目标项目内可版本化、可审查的文件。

## 更多细节

- 想了解 Skill 的行为定义：看 [SKILL.md](SKILL.md)。
- 想了解本仓库的维护规则、能力清单、脚本流程和测试基线：看 [AGENTS.md](AGENTS.md)。
- 想了解不同 Agent 客户端的兼容方式：看 [references/agent-compatibility.md](references/agent-compatibility.md)。

## 🤝 参与贡献

我们非常欢迎各种形式的贡献。如果你对贡献代码感兴趣，可以查看我们的 GitHub [Issues][github-issues-link] 和 [Projects][github-project-link]，大展身手，向我们展示你的奇思妙想。

> [!TIP]
>
> 我们希望这个仓库成为一个技术分享型项目：把 AI 协作中的好实践、失败经验、检查脚本和治理约束沉淀下来，让更多项目可以复用。
> 同时欢迎联系我们提供产品功能和使用体验反馈，帮助我们将 Dayu Harness Skill 建设得更好。
>
> **组织维护者:** [@kinoward](https://github.com/kinoward)

[![Issue](https://img.shields.io/badge/Issue-Open-blue.svg)][github-issues-link]
[![PRs](https://img.shields.io/badge/PRs-Open-brightgreen.svg)][github-prs-link]

[github-issues-link]: https://github.com/kinoward/dayu-harness-skill/issues
[github-prs-link]: https://github.com/kinoward/dayu-harness-skill/pulls
[github-project-link]: https://github.com/kinoward/dayu-harness-skill/projects

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
