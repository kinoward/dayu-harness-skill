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

[English version](README.en.md)

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

[🧭 前言](#-前言) · [🚀 快速开始与使用](#-快速开始与使用) · [📦 会生成什么](#-会生成什么) · [📁 项目结构](#-项目结构) · [🔎 更多细节](#-更多细节)

[📚 参考引用](#-参考引用) · [🤝 参与贡献](#-参与贡献) · [⭐ Star History](#-star-history)

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

如需在执行前单独检查目标项目环境，可运行：

```bash
scripts/ensure-environment.sh <target-project> --check
```

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

这些文件会留在目标项目中，成为后续协作的权威入口。

## 📁 项目结构

```text
dayu-harness-skill/
├── SKILL.md                                      # Skill 行为定义，声明 /dayu-harness 显式入口
├── AGENTS.md                                     # 本仓库维护索引、能力说明和协作规则
├── README.md                                     # 面向使用者的项目介绍、安装指南和展示页
├── README.en.md                                  # 英文镜像说明文档
├── Q&A-TEMPLATE.md                               # 初始化、融合、维护时的问题模板和取舍参考
├── LICENSE                                       # MIT License
├── .gitignore                                    # 本仓库测试缓存、临时产物和本地文件忽略规则
├── .github/
│   └── workflows/
│       └── update-contributors.yml               # 每日刷新 README 贡献者动态区块
├── agents/
│   └── openai.yaml                               # Codex 展示名、触发策略和 UI 元数据
├── capabilities/                                 # 治理能力 manifest，部署清单的单一事实源
│   ├── core.json                                 # 核心治理骨架：AGENTS.md、CLAUDE.md、docs 索引和维护入口
│   ├── git.commit-format.json                    # 约定式提交、commitlint 和 commit-msg hook 能力
│   ├── project.gitignore.json                    # .gitignore 合并能力
│   ├── ai.execution.json                         # AI 执行边界、汇报、重试和协作规则
│   ├── ai.memory.json                            # 项目长期记忆和经验回写规则
│   ├── knowledge.adr.json                        # ADR 决策记录目录与模板能力
│   ├── knowledge.troubleshooting.json            # 排障知识库能力
│   ├── knowledge.research.json                   # 研究资料沉淀能力
│   ├── knowledge.archive.json                    # 历史归档能力
│   ├── project.context.json                      # 产品/项目上下文目录能力
│   ├── github.pr.json                            # PR 指南、PR lint 和审查清单能力
│   ├── github.branch-protection.json             # GitHub 分支保护规则能力
│   ├── github.release-please.json                # release-please 发布自动化能力
│   ├── release.versioning.json                   # 版本号、tag 和发布约束能力
│   ├── quality.practices.json                    # 通用质量实践与测试策略能力
│   ├── quality.node-tooling.json                 # ESLint、Prettier、lint-staged 和 pre-commit 能力
│   └── git.hooks.json                            # hook 片段内部承载能力
├── templates/                                    # 会复制到目标项目的文档模板
│   ├── AGENTS.md                                 # 目标项目根级 Agent 索引模板
│   ├── CLAUDE.md                                 # Claude Code 项目路由模板
│   └── docs/
│       ├── AGENTS.md                             # 目标项目 docs 根索引
│       ├── harness/
│       │   ├── AGENTS.md                         # 治理体系文档索引
│       │   ├── maintenance.md                    # Skill 删除后仍可维护治理体系的操作入口
│       │   ├── guides/
│       │   │   ├── AGENTS.md                     # 治理指南索引
│       │   │   ├── ai-execution.md               # AI 执行边界与协作方式
│       │   │   ├── ai-memory.md                  # 长期记忆、经验沉淀和外部记忆回写规则
│       │   │   ├── branch-protection.md          # 分支保护规则说明
│       │   │   ├── commit-guidelines.md          # 提交信息规范
│       │   │   ├── dev-hygiene.md                # 开发卫生和本地质量约束
│       │   │   ├── pr-guidelines.md              # PR 编写、审查和合并约束
│       │   │   ├── release-please.md             # release-please 工作流说明
│       │   │   ├── release-versioning.md         # 版本发布和 tag 约束
│       │   │   └── testing-strategy.md           # 测试策略和验证分层
│       │   └── sensors/
│       │       ├── AGENTS.md                     # 机械检查入口索引
│       │       ├── reviews/
│       │       │   ├── AGENTS.md                 # 审查资料索引
│       │       │   └── code-review-checklist.md  # 代码审查检查清单
│       │       └── scripts/
│       │           ├── AGENTS.md                 # 检查脚本索引
│       │           ├── audit.sh                  # 治理体系完整性检查
│       │           ├── validate.sh               # 已启用 hooks、配置和 workflow 验证
│       │           ├── check-consistency.sh      # 文档索引、链接和孤儿文档检查
│       │           └── diff-helper.sh            # 生成 merge plan 和差异描述的辅助脚本
│       ├── design-docs/
│       │   ├── AGENTS.md                         # 设计文档索引
│       │   └── adr-template.md                   # ADR 模板
│       ├── exec-plans/
│       │   ├── AGENTS.md                         # 执行计划索引
│       │   ├── active/AGENTS.md                  # 进行中计划目录
│       │   └── completed/AGENTS.md               # 已完成计划目录
│       ├── troubleshooting/AGENTS.md             # 排障记录目录
│       ├── references/
│       │   ├── AGENTS.md                         # 参考资料索引
│       │   └── research/AGENTS.md                # 研究资料目录
│       ├── product-specs/AGENTS.md               # 产品/项目上下文目录
│       ├── generated/AGENTS.md                   # 生成内容暂存目录
│       └── archive/
│           ├── AGENTS.md                         # 历史归档索引
│           └── product-specs/AGENTS.md           # 归档后的产品文档目录
├── templates.en/                                 # 英文部署模板镜像树，与 templates/ 保持同构
├── assets/                                       # README 展示资产，以及按能力部署到目标项目的脚本和配置资产
│   ├── readme/
│   │   └── dayu-harness-banner.png               # README 顶部横幅图片
│   ├── husky/snippets/
│   │   ├── commit-format.sh                      # commit-msg 提交格式校验片段
│   │   ├── quality-node-tooling.sh               # pre-commit Node 质量检查片段
│   │   ├── branch-protection.sh                  # pre-push 主分支保护片段
│   │   └── release-versioning.sh                 # pre-push 发布 tag 保护片段
│   ├── commitlint/commitlint.config.cjs          # Conventional Commits 配置
│   ├── eslint/eslint.config.cjs                  # 可选 Node 项目 ESLint 配置
│   ├── prettier/.prettierrc                      # Prettier 配置
│   ├── lint-staged/.lintstagedrc.json            # lint-staged 配置
│   ├── gitignore/
│   │   ├── universal.gitignore                   # 通用忽略规则
│   │   ├── node.gitignore                        # Node 项目忽略规则
│   │   └── python.gitignore                      # Python 项目忽略规则
│   └── github/
│       ├── workflows/
│       │   ├── pr-lint.yml                       # PR 正文结构检查 workflow
│       │   └── release-please.yml                # release-please workflow
│       ├── scripts/pr_body_structure.py          # PR 正文结构检查脚本
│       ├── rulesets/
│       │   ├── protect-main.json                 # main 分支保护规则集
│       │   └── protect-tags.json                 # release tag 保护规则集
│       ├── release-please-config.json            # release-please 配置
│       └── .release-please-manifest.json         # release-please manifest
├── marketing/                                    # 独立对外传播物料，不参与 Skill 功能或部署产物
│   ├── README.md                                 # 传播物料边界说明
│   └── wechat-moments/
│       ├── README.md                             # 朋友圈发布素材说明
│       ├── dayu-harness-moments-card.png         # 朋友圈竖版配图
│       ├── dayu-harness-moments-card.html        # 配图排版源
│       ├── dayu-harness-moments-copy.md          # 朋友圈正文文案
│       ├── dayu-harness-character.png            # Q 版人物素材
│       └── dayu-harness-qr-art.png               # GitHub 仓库二维码素材
├── scripts/                                      # Skill 自身执行脚本
│   ├── ensure-environment.sh                     # 部署前环境、工具链和初始化状态检查
│   ├── scaffold.sh                               # dry-run / apply 脚手架编排入口
│   ├── install-husky.sh                          # husky hook 片段检查、合并和安装器
│   ├── install-gitignore.sh                      # .gitignore 检查、合并和安装器
│   ├── check-i18n-drift.sh                       # README 与部署模板镜像漂移检查
│   └── update-readme-contributors.mjs            # README 贡献者动态区块刷新脚本
├── docs/                                         # Skill 自身设计和维护资料
│   ├── AGENTS.md                                 # docs 目录索引
│   ├── plan.md                                   # 历史设计计划和架构追溯
│   ├── optimization-2026-05.md                   # 2026-05 优化记录
│   └── completion-report-template.md             # 执行完成后的验证和汇报模板
├── references/
│   └── agent-compatibility.md                    # Claude Code、Codex 和通用 Agent Skills 兼容说明
└── tests/                                        # 测试、fixture 和回归基线
    ├── README.md                                 # 测试执行基线
    ├── unit/
    │   ├── test-architecture-contracts.bats      # manifest、模板和脚本结构契约测试
    │   ├── test-audit.bats                       # audit 脚本行为测试
    │   ├── test-diff-helper.bats                 # diff-helper 行为测试
    │   └── test-skill-interaction-e2e.bats       # Skill 交互和脚手架端到端测试
    └── fixtures/
        ├── empty-project/                        # 空项目初始化场景
        ├── has-husky-project/                    # 已有 husky 项目融合场景
        ├── has-github-actions-project/           # 已有 GitHub Actions 项目融合场景
        ├── has-full-config-project/              # 已有完整 lint/hook 配置项目
        ├── messy-project/                        # 文档索引不完整和孤儿文档场景
        ├── skill-empty-template/                 # 空模板输出基线
        └── skill-messy-template/                 # 复杂模板输出和合并基线
```

其中 `capabilities/` 决定“能部署什么”，`templates/` 和 `assets/` 决定“部署成什么”，`scripts/` 负责“如何安全部署、融合和检查”。

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
