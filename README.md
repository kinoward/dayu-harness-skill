<div align="center">

<img src="assets/readme/dayu-harness-banner.png" alt="Dayu Harness Skill banner" width="100%">

<br>

# Dayu Harness Skill（大禹治库.skill）

### *“把一次性的 AI 协作提示，疏导成项目里长期可运行的治理体系。”*

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![AgentSkills](https://img.shields.io/badge/AgentSkills-Standard-green)](https://agentskills.io)
[![Stars](https://img.shields.io/github/stars/kinoward/dayu-harness-skill?style=social)](https://github.com/kinoward/dayu-harness-skill/stargazers)

[![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-blueviolet)](https://claude.ai/code)
[![Hermes](https://img.shields.io/badge/Hermes-Skill-orange)](https://github.com/kinoward/dayu-harness-skill)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-Skill-teal)](https://github.com/kinoward/dayu-harness-skill)
[![Codex](https://img.shields.io/badge/Codex-Skill-black)](https://github.com/kinoward/dayu-harness-skill)

<br>

English documentation is available in [README.en.md](README.en.md).

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

[🧭 前言](#-前言) · [🚀 快速开始与使用](#-快速开始与使用) · [📦 会生成什么](#-会生成什么) · [🌐 双语部署](#-双语部署)

[📁 项目结构](#-项目结构) · [🔎 更多细节](#-更多细节) · [📚 参考引用](#-参考引用) · [🤝 参与贡献](#-参与贡献) · [⭐ Star History](#-star-history)

</div>

---

## 🧭 前言

你的项目已经开始让智能体参与开发、审查、排障和文档维护，但规则还散在聊天记录、PR 评论、团队口头约定和旧文档里？

Dayu Harness Skill 面向 [Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/) 风格的项目治理而设计。它不是让某个 Agent 在某次对话里更听话，而是把长期规则部署进目标仓库，让 `AGENTS.md`、`docs/`、hooks、CI 和维护脚本成为项目协作的实际权威。

“大禹”取自大禹治水：不把洪流堵在一处，而是疏导、分流并建立长期秩序。本 Skill 的目标也是如此：把一次性的提示词、约束和经验，整理成可版本化、可审查、可迁移的治理资产。

## 🎯 适合场景

- 新项目希望从第一天就建立 `AGENTS.md` 根索引、文档分层和基础工程约束。
- 旧项目已有零散文档、hooks、CI 或提交规则，需要融合成可维护的治理体系。
- 团队希望 AI 协作经验能持续沉淀，而不是留在不可检索的聊天记录里。
- 项目需要在 Claude Code、Codex 和通用 Agent Skills 客户端之间保持可迁移规则。

## 🚀 快速开始与使用

推荐只安装到需要治理的目标项目里，不做全局安装，也不建议把 Skill 安装目录提交进项目。Dayu Harness Skill 是一次性部署、融合、诊断和维护入口；使用完成后可以删除，长期生效的是目标项目内写入的 `AGENTS.md`、`docs/`、hooks、CI 和检查脚本。

### ⚡ 推荐：Vercel skills CLI

```bash
cd <target-project>
npx skills add kinoward/dayu-harness-skill
```

如果希望明确指定客户端：

```bash
# Claude Code -> .claude/skills/
npx skills add kinoward/dayu-harness-skill -a claude-code

# Codex -> .agents/skills/
npx skills add kinoward/dayu-harness-skill -a codex
```

安装完成后，在目标项目中打开你的 Agent 客户端，并输入：

```text
/dayu-harness
```

然后按提示选择初始化、融合已有规则、诊断项目完整性，或维护现有治理内容。Skill 会先分析项目现状，再给出变更计划；已有 hooks、CI、lint 和发布配置会先提供合并方案，不会直接覆盖。

使用完成后可删除：

```bash
npx skills remove dayu-harness
```

<details>
<summary>手动安装到 Claude Code 或 Codex</summary>

手动安装时建议复制文件并移除内层 `.git`，避免在目标项目中留下嵌套 Git 仓库。

Claude Code：

```bash
cd <target-project>
tmp_dir="$(mktemp -d)"
git clone --depth 1 https://github.com/kinoward/dayu-harness-skill.git "$tmp_dir/dayu-harness-skill"
mkdir -p .claude/skills
cp -R "$tmp_dir/dayu-harness-skill" .claude/skills/dayu-harness
rm -rf .claude/skills/dayu-harness/.git "$tmp_dir"
```

Codex：

```bash
cd <target-project>
tmp_dir="$(mktemp -d)"
git clone --depth 1 https://github.com/kinoward/dayu-harness-skill.git "$tmp_dir/dayu-harness-skill"
mkdir -p .agents/skills
cp -R "$tmp_dir/dayu-harness-skill" .agents/skills/dayu-harness
rm -rf .agents/skills/dayu-harness/.git "$tmp_dir"
```

移除：

```bash
rm -rf .claude/skills/dayu-harness
rm -rf .agents/skills/dayu-harness
```

</details>

## 📦 会生成什么

Dayu Harness Skill 会把项目协作规则整理到目标仓库中，常见产物包括：

- `AGENTS.md` 根治理入口，以及必要的子目录索引。
- `docs/harness/` 下的协作指南、维护说明和检查脚本。
- Git hooks、CI 工作流、提交规范、PR 指南和质量检查配置。
- `docs/design-docs/`、`docs/troubleshooting/`、`docs/references/` 等长期知识目录。
- 仓库设置策略说明、Issue 依赖治理说明、可配置的 TDD 门禁策略文件，以及用户确认后才执行的 GitHub 远端设置同步。
- `docs/product-specs/project-status.md` 及项目背景状态短快照入口。

这些文件会留在目标项目中，成为后续协作的权威入口。

## 🌐 双语部署

Dayu Harness Skill 以中文为源语言，并推荐默认中文部署；英文内容来自中文语义镜像，服务英文用户理解，不反向改写中文意图。

运行 `/dayu-harness` 时，交互式问题和选项会中英双语展示，避免英文用户因为看不懂中文而无法选择。部署目标项目时只写入一种语言，默认中文；如果明确选择英文，则写入英文部署产物。

`templates/` 是中文源模板，`templates.en/` 是英文镜像模板，两个目录保持同构；维护者可以用漂移检查脚本确认 README 镜像、模板树、能力映射和双语问答保持一致。

问答流程按阻塞节点分块输出，含版本冲突、远端仓库创建、`.husky`/workflow 合并、已跟踪 `.claude`、受保护分支等场景，均使用固定中英双语选项，不要求用户手工输入命令。

## 📁 项目结构

README 只展示高层结构，完整目录树与职责边界维护在 AGENTS.md 中，作为仓库治理的长期事实来源。

- 入口与索引：`README.md`、`README.en.md`、`AGENTS.md`（含子目录索引）
- 能力与部署引擎：`capabilities/`、`templates/`、`templates.en/`、`assets/`、`scripts/`
- 输出与维护资料：`docs/`、`marketing/`、`tests/`
- 发布与仓库自动化：`.github/workflows/update-contributors.yml` 负责 README 动态区块；GitHub 能力相关 workflow、ruleset 与策略模板位于 `assets/github/`

完整仓库目录树见 [AGENTS.md](AGENTS.md)。

## 🔎 更多细节

- 想了解 Skill 的行为定义：看 [SKILL.md](SKILL.md)。
- 想了解本仓库的维护规则、能力清单、脚本流程和测试基线：看 [AGENTS.md](AGENTS.md)。
- 想了解不同 Agent 客户端的兼容方式：看 [references/agent-compatibility.md](references/agent-compatibility.md)。

## 📚 参考引用

- [微信公众号「浮之静」：《深度解析：Harness Engineering》](https://mp.weixin.qq.com/s/-mgf8K7XZrTKoD0pMOIn3w)：项目治理与 AI 协作理念参考。
- [OpenAI: Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/)：本 Skill 的设计哲学来源。
- [deusyu/harness-engineering](https://github.com/deusyu/harness-engineering)：README 信息层次、概念先行叙事和 AGENTS.md 渐进式披露实践参考。
- [Martin Fowler: Harness Engineering](https://martinfowler.com/articles/harness-engineering.html)：Guides 与 Sensors 控制论框架参考。
- [agentsmd/agents.md](https://github.com/agentsmd/agents.md)：AGENTS.md 开放格式规范。
- [microsoft/skills](https://github.com/microsoft/skills)：技能声明与客户端兼容实践。

## 🤝 参与贡献

欢迎提交 Issue 或 PR：问题反馈、使用体验、兼容适配和文档改进都很有价值。

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
