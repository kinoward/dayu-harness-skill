# Dayu Harness Skill

### 大禹治库 Skill：把一次性的 AI 协作提示，疏导成项目里长期可运行的治理体系。

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

[这个 Skill 会做什么](#这个-skill-会做什么) · [治理能力](#治理能力清单) · [安装](#安装) · [使用](#使用) · [示例](#示例) · [功能](#功能) · [目录结构](#目录结构) · [验收与测试](#验收与测试)

---

“大禹”取自大禹治水：不是把洪流堵住，而是疏导、分流并建立长期秩序。Dayu Harness Skill 面向 [Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/) 风格的项目治理而设计：人类定义约束，智能体执行任务，脚本检查结果，仓库沉淀长期记录。

---

## 这个 Skill 会做什么

### 1. 从以智能体为中心的规则转向以项目为中心的治理

只把规则写进某个 Skill 或某次对话，约束会被工具、会话和上下文窗口限制。大禹治库 Skill 把长期规则部署进目标仓库，让 `AGENTS.md`、`docs/`、hooks、CI 和维护脚本成为实际权威。

### 2. 用 AGENTS.md 做地图，而不是把所有内容塞进一个手册

目标项目会获得以 `AGENTS.md` 为根的渐进式披露文档体系：根索引负责路由，子目录索引负责局部上下文，具体指南和检查脚本承担执行约束与反馈回路。

### 3. Skill 是启动器和升级器，不是运行时系统

初始化、融合或维护完成后，Skill 可从客户端技能目录中删除。目标项目内的治理资产继续生效；后续需要新增能力或调整约束时，再重新安装大禹治库 Skill 并运行 `/dayu-harness`。

---

## 治理能力清单

`capabilities/*.json` 是部署清单的单一事实源。默认能力始终安装；可选能力由用户在脚手架、融合或维护流程中选择。

| 类型 | 能力 ID | 部署内容 |
| --- | --- | --- |
| 默认 | `core` | 根 `AGENTS.md`、`docs/` 索引、`docs/harness/maintenance.md`、`exec-plans`、`generated` 和检查脚本骨架。 |
| 默认 | `git.commit-format` | 约定式提交指南、`commitlint.config.cjs` 与 commit-msg hook 片段。 |
| 默认 | `project.gitignore` | universal / Node.js / Python `.gitignore` 规则的可合并安装。 |
| 默认 | `ai.execution` | AI 执行边界、协作姿态、自动重试和汇报规则。 |
| 默认 | `ai.memory` | 项目长期记忆边界、知识沉淀位置和外部记忆回写规则。 |
| 默认 | `knowledge.adr` | ADR 目录与架构决策模板。 |
| 默认 | `knowledge.troubleshooting` | 排障知识库入口。 |
| 默认 | `knowledge.research` | 研究资料和外部经验沉淀区。 |
| 默认 | `project.context` | 产品规格和项目上下文目录。 |
| 默认 | `knowledge.archive` | 历史内容归档区，降低旧上下文干扰。 |
| 可选 | `github.pr` | PR 指南、审查清单、PR 正文结构检查工作流。 |
| 可选 | `github.branch-protection` | GitHub 规则集模板与本地 pre-push 分支保护片段。 |
| 可选 | `release.versioning` | 版本与 tag 规则、tag 保护规则集和发布指南。 |
| 可选 | `github.release-please` | release-please 工作流、配置和发布协作指南。 |
| 可选 | `quality.practices` | 通用开发纪律、测试策略与工程实践文档。 |
| 可选 | `quality.node-tooling` | ESLint、Prettier、lint-staged 与 pre-commit hook 片段。 |
| 内部 | `git.hooks` | hook 片段的内部承载能力，不作为独立业务治理入口。 |

---

## 安装

你可以让智能体自行安装这个 Skill：

```text
从当前仓库安装大禹治库 Skill，然后在目标项目中运行 /dayu-harness。
```

手动安装路径：

| 宿主 | 目标路径 |
| --- | --- |
| Claude Code | `<target-project>/.claude/skills/dayu-harness/` |
| Codex | `<codex-skills-dir>/dayu-harness/` |
| 通用 Agent Skills 客户端 | `<agent-skills-dir>/dayu-harness/` |

```bash
# Claude Code：项目级安装
mkdir -p <target-project>/.claude/skills
cp -R dayu-harness-skill <target-project>/.claude/skills/dayu-harness

# Codex 或通用 Agent Skills 客户端
cp -R dayu-harness-skill <agent-skills-dir>/dayu-harness
```

`agents/openai.yaml` 提供 Codex UI 与显式触发策略元数据。完成初始化或升级后，如不再需要 Skill，可从客户端技能目录移除它；目标项目内的治理资产仍然保留。

```bash
rm -rf <installed-skills-dir>/dayu-harness/
```

---

## 使用

在已安装 Skill 的智能体宿主中输入：

```text
/dayu-harness
```

Skill 会先读取目标项目状态，再进入对应模式。

| 模式 | 触发条件 | 行为 |
| --- | --- | --- |
| 脚手架 | 项目没有 `AGENTS.md` | 初始化治理骨架，安装默认能力，按需启用可选能力。 |
| 诊断 | 用户要求检查完整性 | 优先运行目标项目内的 audit / consistency 检查脚本，输出自然语言诊断。 |
| 融合 | 项目已有文档或配置 | 对已有 `docs/`、hooks、CI、lint 配置生成 merge plan，逐项确认后合并。 |
| 维护 | 用户要求增删改约束 | 按 manifest 找到联动文档、资产和索引，更新后重新验证。 |
| 生成 | 用户要求生成特定文档或配置 | 依据 `docs/harness/maintenance.md` 和项目上下文生成适配内容。 |

### 前置检查

部署、融合或维护前会统一执行环境检查：

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

### 命令

| 命令 | 用途 |
| --- | --- |
| `/dayu-harness` | Skill 显式入口。 |
| `scripts/scaffold.sh <project-root> --dry-run --enable <optional ids>` | 预览默认能力与可选能力的部署计划。 |
| `scripts/scaffold.sh <project-root> --apply --enable <optional ids>` | 应用用户确认后的部署计划。 |
| `docs/harness/sensors/scripts/validate.sh --json <project-root>` | 在目标项目中检查启用的 hooks、配置和工作流。 |
| `docs/harness/sensors/scripts/audit.sh --json <project-root>` | 检查入口文件、文档索引和治理结构完整性。 |
| `docs/harness/sensors/scripts/check-consistency.sh --json <project-root>` | 检查文档链接、索引同步和孤儿文档。 |
| `docs/harness/sensors/scripts/diff-helper.sh merge-plan <existing> <incoming>` | 为已有文件和即将写入文件生成结构化合并建议。 |

---

## 示例

```text
用户  ❯ /dayu-harness
Skill ❯ 检测目标项目：没有 AGENTS.md，进入脚手架模式。
Skill ❯ 默认启用 core、git.commit-format、project.gitignore、AI 执行/记忆、ADR、排障、研究、项目上下文和归档。

用户  ❯ 启用 github.pr，跳过 quality.node-tooling 和 release-please。
Skill ❯ 执行 dry-run 预览：将创建 AGENTS.md、docs/harness、检查脚本、commitlint、.gitignore 和 PR 检查资产。

用户  ❯ 确认应用。
Skill ❯ 写入文件，运行 validate / audit / check-consistency，然后按完成报告模板汇报结果。
```

另一个常见场景是融合已有项目：

```text
Skill ❯ 检测到已有 .husky/commit-msg 和 .github/workflows/pr-lint.yml。
Skill ❯ 由安装器托管的组件先走 --check；静态工作流先给 dry-run 差异。
Skill ❯ 对无法证明安全合并的文件标记 manual_required，等待用户选择保留、替换、合并或跳过。
```

---

## 功能

### 生成的治理结构

| 组成 | 内容 |
| --- | --- |
| 根路由 | `AGENTS.md` 作为项目治理入口；`CLAUDE.md` 保持 `@AGENTS.md` 路由。 |
| 规则指南 | `docs/harness/guides/` 存放 AI 执行、记忆、提交、PR、发布、测试和开发纪律。 |
| 反馈检查 | `docs/harness/sensors/scripts/` 存放 `validate.sh`、`audit.sh`、`check-consistency.sh`、`diff-helper.sh`。 |
| 知识库 | `docs/design-docs/`、`docs/troubleshooting/`、`docs/references/research/`、`docs/product-specs/`、`docs/archive/`。 |
| Git 资产 | `.husky/` 片段、`commitlint.config.cjs`、`.gitignore`。 |
| GitHub 资产 | 可选工作流、规则集、release-please 配置和 PR 审查清单。 |

### 执行模型

```text
接收请求
-> 分析项目
-> 解析默认能力与可选能力
-> 执行环境前置检查
-> 展示 dry-run / merge plan
-> 应用用户确认后的变更
-> 执行 validate / audit / check-consistency
-> 用自然语言汇报结果
```

### 演进规则

- 新增能力先改 `capabilities/*.json`，再同步模板、资产、Q&A 和测试断言。
- 目录、文件或能力清单变化时，同步根 `AGENTS.md`、相关子目录 `AGENTS.md` 和本 README 的 `## 目录结构`。
- 项目协作中产生的可复用经验，不写成长对话记录；应归纳为 ADR、排障、研究、项目上下文或治理约束并回写 `docs/`。
- 已有配置默认不覆盖。`replace` 只能由用户显式选择；复杂 YAML / JS / CJS / 工作流 / 配置文件默认进入 `manual_required`。

---

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
├── docs/                              # Skill 设计、计划与运行产物模板
└── tests/                             # Skill 自身测试与 fixture
```

部署到目标项目后的结构：

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
│   │   │   ├── pr-guidelines.md          # 可选：github.pr
│   │   │   ├── branch-protection.md      # 可选：github.branch-protection
│   │   │   ├── release-versioning.md     # 可选：release.versioning
│   │   │   ├── release-please.md         # 可选：github.release-please
│   │   │   ├── dev-hygiene.md            # 可选：quality.practices
│   │   │   └── testing-strategy.md       # 可选：quality.practices
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
│   │   ├── AGENTS.md
│   │   └── adr-template.md
│   ├── exec-plans/
│   │   ├── AGENTS.md
│   │   ├── active/
│   │   │   └── AGENTS.md
│   │   └── completed/
│   │       └── AGENTS.md
│   ├── generated/
│   │   └── AGENTS.md
│   ├── product-specs/
│   │   └── AGENTS.md
│   ├── references/
│   │   ├── AGENTS.md
│   │   └── research/
│   │       └── AGENTS.md
│   ├── troubleshooting/
│   │   └── AGENTS.md
│   └── archive/
│       ├── AGENTS.md
│       └── product-specs/
│           └── AGENTS.md
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

---

## 依赖与兼容性

- 核心依赖由 `scripts/ensure-environment.sh` 检查。
- 文档与脚本依赖 `jq`、`git`、`node`、`npm`、`npx`，以及能力相关的 GitHub/Node 工具链。
- GitHub 能力需要 `gh` 登录与认证上下文。
- 目标项目的运行与安装不依赖 `bats`；`bats` 只服务本仓库维护者测试。
- Claude、Codex 和通用 Agent Skills 客户端的兼容说明见 [references/agent-compatibility.md](references/agent-compatibility.md)。

---

## 验收与测试

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

---

## 说明

- 大禹治库 Skill 不是目标项目的长期运行时服务；它是一次性部署、融合、诊断、维护和生成入口。
- 长期真相位于目标项目内的 `AGENTS.md`、`docs/`、hooks、CI 和维护脚本。
- 运行时检索系统、向量库、上下文缓存或外部智能体记忆可以提升效率，但不能替代仓库内可审查的治理事实。
- 外部知识有价值时，应整理成决策、排障、研究、项目上下文或约束文档后回写项目，并同步对应 `AGENTS.md` 索引。

---

## 许可证

本项目使用 MIT 许可证，详见 [LICENSE](LICENSE)。

---

## 参考引用

- [OpenAI — Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/) — 本 Skill 的设计哲学来源
- [deusyu/harness-engineering](https://github.com/deusyu/harness-engineering) — 中文 Harness Engineering 学习归档，AGENTS.md 渐进式披露实践参考
- [titanwings/colleague-skill](https://github.com/titanwings/colleague-skill) — README 信息架构与展示节奏参考
- [Martin Fowler — Harness Engineering](https://martinfowler.com/articles/harness-engineering.html) — Guides × Sensors 控制论框架
- [agentsmd/agents.md](https://github.com/agentsmd/agents.md) — AGENTS.md 开放格式规范
- [microsoft/skills](https://github.com/microsoft/skills) — 技能声明与客户端兼容实践
- [agent-sh/agnix](https://github.com/agent-sh/agnix) — AGENTS.md / CLAUDE.md / SKILL.md 的 linter 与 LSP 实践
