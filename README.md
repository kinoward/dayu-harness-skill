# Dayu Harness Skill

> 大禹治库 Skill：把一次性的 AI 协作提示，疏导成项目里长期可运行的治理体系。

[![许可证: MIT](https://img.shields.io/badge/%E8%AE%B8%E5%8F%AF%E8%AF%81-MIT-2E8B57)](LICENSE)
![大禹治库](https://img.shields.io/badge/%E5%A4%A7%E7%A6%B9%E6%B2%BB%E5%BA%93-Skill-B8860B)
![AgentSkills](https://img.shields.io/badge/AgentSkills-Compatible-3C7D5A)
![AGENTS.md](https://img.shields.io/badge/AGENTS.md-%E6%A0%B9%E7%B4%A2%E5%BC%95-4B5D67)
![命令](https://img.shields.io/badge/%E5%91%BD%E4%BB%A4-%2Fdayu--harness-6C5CE7)
![Harness Engineering](https://img.shields.io/badge/Harness-Engineering-0E7C86)
![Claude Code](https://img.shields.io/badge/Claude%20Code-Skill-blueviolet)
![Codex](https://img.shields.io/badge/Codex-Skill-111827)
![Bats](https://img.shields.io/badge/%E6%B5%8B%E8%AF%95-Bats-1F6FEB)

**中文名：大禹治库 Skill** · **英文名：Dayu Harness Skill** · **项目目录：`dayu-harness-skill`** · **显式命令：`/dayu-harness`**

你的项目已经开始让智能体参与开发、审查、排障和文档维护？

你的规则还散在聊天记录、PR 评论、团队口头约定和旧文档里？

你希望 Skill 删除之后，项目仍然知道怎么协作、怎么检查、怎么沉淀经验？

**大禹治库 Skill 不把规则堵在一次对话里，而是把它们疏导进仓库：地图、指南、检查脚本和自动化反馈各归其位。**

项目现状 + `capabilities/*.json` + `/dayu-harness` -> `AGENTS.md` + `docs/harness` + hooks/CI + 检查脚本 + 长期知识目录

[一句话理解](#一句话理解) · [核心观念](#核心观念) · [快速开始](#快速开始) · [能力清单](#能力清单) · [工作模式](#工作模式) · [生成内容](#生成内容) · [目录结构](#目录结构) · [维护测试](#维护测试) · [参考引用](#参考引用)

---

## 前言

“大禹”取自大禹治水：不是把洪流堵住，而是疏导、分流并建立长期秩序。

Dayu Harness Skill 面向 [Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/) 风格的项目治理而设计：人类定义约束，智能体执行任务，脚本检查结果，仓库沉淀长期记录。它不是让某个 Agent 在某次对话里更听话，而是把长期规则部署进目标仓库，让 `AGENTS.md`、`docs/`、hooks、CI 和维护脚本成为项目协作的实际权威。

> 初始化完成后，Skill 可以删除；目标项目内的治理体系仍然继续运行。

## 一句话理解

```text
普通 AI 协作：人类在对话里反复提醒 Agent
Dayu Harness：人类把约束写入仓库 -> Agent 读取地图 -> 脚本检查结果 -> 经验回写项目
```

核心转变：治理规则不再依赖单次会话，而是沉淀为项目内的 `AGENTS.md`、文档索引、检查脚本、Git hooks、CI 工作流和知识目录。

## 适合场景

- 新项目希望从第一天就建立 AGENTS.md 根索引、文档分层和基础工程约束。
- 旧项目已有零散文档、hooks、CI 或提交规则，需要融合成可维护的治理体系。
- 团队希望 AI 协作经验能持续沉淀，而不是留在不可检索的聊天记录里。
- 项目需要在 Claude Code、Codex 和通用 Agent Skills 客户端之间保持可迁移规则。

## 核心观念

1. **Project-centric，而不是 Agent-centric**

   Skill 只负责部署和升级。长期生效的是目标项目中的 `AGENTS.md`、`docs/`、hooks、CI 和脚本。

2. **AGENTS.md 是地图，不是百科全书**

   根索引只做路由，子目录索引提供局部上下文，具体指南和传感器脚本承担执行约束。

3. **能力清单是单一事实源**

   `capabilities/*.json` 定义能力 ID、依赖、模板、资产、installer、安全策略和验收标准。

4. **机械化检查优先于文字承诺**

   文档可以描述规则，但 `validate.sh`、`audit.sh`、`check-consistency.sh`、Git hooks 和 CI 才负责持续反馈。

5. **已有配置默认不覆盖**

   对现有 hooks、GitHub workflows、lint 配置和发布配置，先 dry-run 或生成 merge plan，再由用户确认保留、替换、合并或跳过。

6. **经验要回写项目**

   可复用的架构决策、排障经验、研究结论、产品上下文和治理约束，应沉淀到 `docs/`，并同步对应 `AGENTS.md` 索引。

## 快速开始

在支持 Agent Skills 的宿主中安装本仓库，然后在目标项目输入：

```text
/dayu-harness
```

手动安装示例：

```bash
# Claude Code：项目级安装
mkdir -p <target-project>/.claude/skills
cp -R dayu-harness-skill <target-project>/.claude/skills/dayu-harness

# Codex 或通用 Agent Skills 客户端
cp -R dayu-harness-skill <agent-skills-dir>/dayu-harness
```

也可以让智能体自行安装：

```text
从当前仓库安装大禹治库 Skill，然后在目标项目中运行 /dayu-harness。
```

完成初始化或升级后，如不再需要 Skill，可从客户端技能目录移除：

```bash
rm -rf <installed-skills-dir>/dayu-harness/
```

## 运行流程

```text
读取目标项目
-> 解析已有 AGENTS.md、docs、hooks、CI 和配置
-> 解析默认能力与可选能力
-> 执行 scripts/ensure-environment.sh 前置检查
-> 展示 dry-run 或 merge plan
-> 按用户确认应用变更
-> 运行 validate / audit / check-consistency
-> 按完成报告模板汇报
```

前置检查命令：

```bash
scripts/ensure-environment.sh <project-root> --check
scripts/ensure-environment.sh <project-root> --check --capabilities "<resolved capability ids>"
```

常见状态：

| 状态 | 含义 |
| --- | --- |
| `ok` | 环境满足当前能力集合要求，可以继续。 |
| `needs_install` | 缺少 `jq`、GitHub CLI、Node 工具链等必需依赖。 |
| `needs_initialization` | 缺少 Git 或 Node 初始化上下文，需要用户确认 `git init` 或 `npm init -y`。 |
| `needs_user_action` | 需要登录、授权或人工处理已有配置。 |
| `error` | 脚本自身或环境状态异常。 |

## 能力清单

`capabilities/*.json` 是部署清单的单一事实源。默认能力始终安装；可选能力由用户在脚手架、融合或维护流程中选择。

| 分组 | 能力 ID | 部署内容 |
| --- | --- | --- |
| 核心治理 | `core` | 根 `AGENTS.md`、`docs/` 索引、`docs/harness/maintenance.md`、执行计划、生成区和检查脚本骨架。 |
| Git 基线 | `git.commit-format`、`project.gitignore` | 约定式提交指南、`commitlint.config.cjs`、commit-msg hook 片段和可合并 `.gitignore`。 |
| AI 协作 | `ai.execution`、`ai.memory` | AI 执行边界、协作姿态、自动重试、汇报规则、长期记忆边界和外部记忆回写规则。 |
| 知识沉淀 | `knowledge.adr`、`knowledge.troubleshooting`、`knowledge.research`、`project.context`、`knowledge.archive` | ADR、排障、研究资料、产品上下文和历史归档目录。 |
| GitHub 可选 | `github.pr`、`github.branch-protection` | PR 指南、审查清单、PR 正文检查工作流、分支保护规则集和 pre-push 片段。 |
| 发布可选 | `release.versioning`、`github.release-please` | 版本与 tag 规则、发布指南、release-please 工作流和配置。 |
| 质量可选 | `quality.practices`、`quality.node-tooling` | 通用开发纪律、测试策略、ESLint、Prettier、lint-staged 和 pre-commit hook 片段。 |
| 内部承载 | `git.hooks` | hook 片段的内部承载能力，不作为独立业务治理入口。 |

## 工作模式

| 模式 | 触发条件 | 行为 |
| --- | --- | --- |
| 脚手架 | 项目没有 `AGENTS.md` | 初始化治理骨架，安装默认能力，按需启用可选能力。 |
| 诊断 | 用户要求检查完整性 | 优先运行目标项目内的 audit / consistency 检查脚本，输出自然语言诊断。 |
| 融合 | 项目已有文档或配置 | 对已有 `docs/`、hooks、CI、lint 配置生成 merge plan，逐项确认后合并。 |
| 维护 | 用户要求增删改约束 | 按 manifest 找到联动文档、资产和索引，更新后重新验证。 |
| 生成 | 用户要求生成特定文档或配置 | 依据 `docs/harness/maintenance.md` 和项目上下文生成适配内容。 |

常用命令：

| 命令 | 用途 |
| --- | --- |
| `/dayu-harness` | Skill 显式入口。 |
| `scripts/scaffold.sh <project-root> --dry-run --enable <optional ids>` | 预览默认能力与可选能力的部署计划。 |
| `scripts/scaffold.sh <project-root> --apply --enable <optional ids>` | 应用用户确认后的部署计划。 |
| `docs/harness/sensors/scripts/validate.sh --json <project-root>` | 在目标项目中检查启用的 hooks、配置和工作流。 |
| `docs/harness/sensors/scripts/audit.sh --json <project-root>` | 检查入口文件、文档索引和治理结构完整性。 |
| `docs/harness/sensors/scripts/check-consistency.sh --json <project-root>` | 检查文档链接、索引同步和孤儿文档。 |
| `docs/harness/sensors/scripts/diff-helper.sh merge-plan <existing> <incoming>` | 为已有文件和即将写入文件生成结构化合并建议。 |

## 生成内容

### 部署后的目标项目结构

```text
<target-project>/
├── CLAUDE.md                          # Claude 路由，保持 @AGENTS.md
├── AGENTS.md                          # 根治理入口
├── docs/
│   ├── AGENTS.md
│   ├── harness/
│   │   ├── AGENTS.md
│   │   ├── maintenance.md             # 治理维护与更新手册
│   │   ├── guides/
│   │   │   ├── AGENTS.md
│   │   │   ├── ai-execution.md
│   │   │   ├── ai-memory.md
│   │   │   ├── commit-guidelines.md
│   │   │   ├── pr-guidelines.md       # 可选：github.pr
│   │   │   ├── branch-protection.md   # 可选：github.branch-protection
│   │   │   ├── release-versioning.md  # 可选：release.versioning
│   │   │   ├── release-please.md      # 可选：github.release-please
│   │   │   ├── dev-hygiene.md         # 可选：quality.practices
│   │   │   └── testing-strategy.md    # 可选：quality.practices
│   │   └── sensors/
│   │       ├── AGENTS.md
│   │       ├── scripts/
│   │       │   ├── AGENTS.md
│   │       │   ├── audit.sh
│   │       │   ├── check-consistency.sh
│   │       │   ├── diff-helper.sh
│   │       │   └── validate.sh
│   │       └── reviews/
│   │           ├── AGENTS.md
│   │           └── code-review-checklist.md  # 可选：github.pr
│   ├── design-docs/
│   ├── exec-plans/
│   ├── generated/
│   ├── product-specs/
│   ├── references/
│   ├── troubleshooting/
│   └── archive/
├── .husky/                            # 默认：git.hooks + hook 承载的 Git 能力
├── .github/                           # 可选：GitHub 工作流、规则集、release 资产
├── commitlint.config.cjs              # 默认：git.commit-format
├── eslint.config.cjs                  # 可选：quality.node-tooling
├── .prettierrc                        # 可选：quality.node-tooling
├── .lintstagedrc.json                 # 可选：quality.node-tooling
├── .gitignore                         # 默认：project.gitignore
├── release-please-config.json         # 可选：github.release-please
└── .release-please-manifest.json      # 可选：github.release-please
```

### 沉淀位置

| 类型 | 沉淀位置 |
| --- | --- |
| 架构/技术决策 | `docs/design-docs/` |
| 问题排障 | `docs/troubleshooting/` |
| 研究发现 | `docs/references/research/` |
| 约束变更 | `docs/harness/guides/` + `AGENTS.md` |
| 项目背景和产品上下文 | `docs/product-specs/` |
| 历史内容 | `docs/archive/` |

## 目录结构

本项目遵循 [AgentSkills](https://agentskills.io) 开放标准。整个仓库就是一个 Skill 目录：

```text
dayu-harness-skill/
├── README.md                          # 人类阅读入口
├── SKILL.md                           # Skill 行为与运行约束
├── AGENTS.md                          # Skill 根索引
├── LICENSE                            # MIT 许可文件
├── .gitignore                         # 本仓库临时测试产物忽略规则
├── Q&A-TEMPLATE.md                    # 初始化与融合问答参考
├── agents/                            # Codex UI 与触发策略元数据
├── references/                        # Claude / Codex / 通用 Agent Skills 兼容说明
├── capabilities/                      # 治理能力 manifest，部署清单单一事实源
├── templates/                         # 部署到目标项目的文档模板来源
├── assets/                            # 按能力部署的 hook、CI、配置资产
├── scripts/                           # 内部环境前置、初始化与安装脚本
├── docs/                              # 设计计划、优化记录与完成报告模板
└── tests/                             # Skill 自身测试与 fixture
```

目录索引变化时，同步更新根 [AGENTS.md](AGENTS.md)、相关子目录 `AGENTS.md` 和本节。

## 依赖兼容

- 核心依赖由 `scripts/ensure-environment.sh` 检查。
- 文档与脚本依赖 `jq`、`git`、`node`、`npm`、`npx`，以及能力相关的 GitHub/Node 工具链。
- GitHub 能力需要 `gh` 登录与认证上下文。
- 目标项目的运行与安装不依赖 `bats`；`bats` 只服务本仓库维护者测试。
- Claude、Codex 和通用 Agent Skills 客户端的兼容说明见 [references/agent-compatibility.md](references/agent-compatibility.md)。

## 维护测试

维护本 Skill 后，建议按以下顺序执行：

```bash
bats tests/unit/test-architecture-contracts.bats
bats tests/unit/test-audit.bats
bats tests/unit/test-skill-interaction-e2e.bats
bats tests/unit
```

验证重点：

- `AGENTS.md` 目录索引完整性。
- 能力 manifest 与模板/资产映射一致性。
- 环境预检、dry-run 预览、merge plan 合并计划和收尾验证流程。
- 默认能力与可选能力的部署结果。

## 说明

- 大禹治库 Skill 不是目标项目的长期运行时服务；它是一次性部署、融合、诊断、维护和生成入口。
- 长期真相位于目标项目内的 `AGENTS.md`、`docs/`、hooks、CI 和维护脚本。
- 运行时检索系统、向量库、上下文缓存或外部智能体记忆可以提升效率，但不能替代仓库内可审查的治理事实。
- 外部知识有价值时，应整理成决策、排障、研究、项目上下文或约束文档后回写项目，并同步对应 `AGENTS.md` 索引。

## 许可证

本项目使用 MIT 许可证，详见 [LICENSE](LICENSE)。

## 参考引用

- [OpenAI: Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/)：本 Skill 的设计哲学来源。
- [deusyu/harness-engineering](https://github.com/deusyu/harness-engineering)：README 信息层次、概念先行叙事和 AGENTS.md 渐进式披露实践参考。
- [Martin Fowler: Harness Engineering](https://martinfowler.com/articles/harness-engineering.html)：Guides 与 Sensors 控制论框架参考。
- [agentsmd/agents.md](https://github.com/agentsmd/agents.md)：AGENTS.md 开放格式规范。
- [microsoft/skills](https://github.com/microsoft/skills)：技能声明与客户端兼容实践。
