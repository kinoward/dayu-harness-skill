# docs-governance

一次性部署工具：帮助项目安装以 AGENTS.md 为根的 Harness Engineering 治理体系。

设计哲学源自 [Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/)——人类设计约束，智能体写代码。

## 功能概述

本 Skill 是一个**一次性部署与维护工具**，不是治理体系本身。它负责把 Harness Engineering 理念落地为目标项目中的 AGENTS.md、docs/ 文档、hooks、CI 与维护脚本。初始化完成后，Skill 可安全删除；真正持续生效的是已部署到项目内的治理体系。

设计边界：直接把规则只做成 Skill，可以约束某个 Agent 在当前环境中的行为；但 Harness Engineering 更强调项目拥有自己的外部约束环境。docs-governance 因此只作为安装器、问答引导器和升级入口，最终权威必须落在目标项目内，让规则和反馈回路可版本化、可审查、可迁移、可执行。

工具入口能力：
- **脚手架**：按 `core + capability modules` 在新项目中建立 AGENTS.md + docs/ 文档体系
- **融合**：与已有文档体系合并，保留现有内容，补全缺失
- **诊断**：检查现有体系的完整性和一致性
- **维护**：增删改约束、更新项目文档
- **生成**：根据项目特征智能生成适配内容
- **自动化约束资产**：按需部署 AI 署名剥离、issue 引用拦截、Conventional Commits 校验等 hooks/CI
- **发布工作流资产**：按需部署 Google release-please 自动化版本发布配置

## 目录结构

### Skill 包结构

本结构描述 `docs-governance/` Skill 自身。它是部署来源，不会整体复制到目标项目。

```
docs-governance/
├── README.md                 # 本文件，人类阅读入口
├── SKILL.md                  # Skill 行为定义，保持精简
├── AGENTS.md                 # Skill 自身渐进式披露入口
├── Q&A-TEMPLATE.md           # Q&A 参考模板
├── agents/                   # Codex UI 与触发策略元数据
├── references/               # Claude / Codex / 通用 Agent Skills 兼容说明
├── capabilities/             # 治理能力 manifest，部署清单单一事实源
├── docs/                     # Skill 自身设计、优化记录与执行完成报告模板
├── templates/                # 部署到目标项目的文档模板来源
├── assets/                   # 按能力部署的 hook、CI、配置资产来源
├── scripts/                  # Skill 内部初始化和安装脚本
└── tests/                    # Skill 自身 bats 测试、fixture 模板与执行测试基线
```

维护 Skill 自身目录、模板或能力清单时，必须同步更新本结构图和根 [AGENTS.md](AGENTS.md) 中对应的 `## 目录索引`（以及 `README.md` 的 `## 目录结构`）区块。

### 部署到目标项目后的结构

目标项目只接收 `capabilities/*.json` 选中的模板和资产。`core` 始终部署；其它目录和文件按 capability 启用。

```
<target-project>/
├── CLAUDE.md                         # core：仅 @AGENTS.md
├── AGENTS.md                         # core：项目级任务路由入口
├── docs/
│   ├── AGENTS.md                     # core：docs 目录索引
│   ├── harness/                      # core：规则、反馈检查和维护流程
│   │   ├── AGENTS.md
│   │   ├── maintenance.md            # core：文档体系维护规范
│   │   ├── guides/                   # 行动前规则卡片
│   │   │   ├── AGENTS.md
│   │   │   ├── commit-guidelines.md      # git.commit
│   │   │   ├── git-language-policy.md    # git.language
│   │   │   ├── pr-guidelines.md          # github.pr
│   │   │   ├── branch-and-release.md     # github.branch-release
│   │   │   ├── dev-hygiene.md            # quality.tooling
│   │   │   ├── testing-strategy.md       # quality.tooling
│   │   │   └── ai-collaboration.md       # ai.collaboration
│   │   └── sensors/                  # 行动后检查与反馈
│   │       ├── AGENTS.md
│   │       ├── scripts/              # core：维护脚本
│   │       │   ├── AGENTS.md
│   │       │   ├── audit.sh
│   │       │   ├── check-consistency.sh
│   │       │   ├── diff-helper.sh
│   │       │   └── validate.sh
│   │       └── reviews/
│   │           ├── AGENTS.md
│   │           └── code-review-checklist.md  # github.pr
│   ├── design-docs/                  # knowledge.adr
│   ├── exec-plans/                   # core：执行计划
│   │   ├── AGENTS.md
│   │   ├── active/AGENTS.md
│   │   └── completed/AGENTS.md
│   ├── generated/                    # core：自动生成资料索引
│   │   └── AGENTS.md
│   ├── product-specs/                # project.docs
│   ├── references/                   # knowledge.research
│   │   └── research/
│   ├── troubleshooting/              # knowledge.troubleshooting
│   └── archive/                      # archive.project
├── .husky/                           # git.commit 通过安装脚本合并部署
├── .github/                          # github.pr / github.branch-release / github.release-please
├── commitlint.config.cjs             # git.commit
├── eslint.config.js                  # quality.tooling
├── .prettierrc                       # quality.tooling
├── .lintstagedrc.json                # quality.tooling
├── .gitignore                        # quality.tooling
├── release-please-config.json        # github.release-please
└── .release-please-manifest.json     # github.release-please
```

能力清单、部署模板或目标项目治理骨架变化时，必须同步更新本结构图和 `templates/` 下对应 `AGENTS.md` 的 `## 目录索引`（以及 `README.md` 的 `## 目录结构`）区块。

## 依赖与测试（维护者）

- 本 Skill 在目标项目中的运行与安装**不依赖** `bats`。
- `tests/README.md` 是 Skill 自身执行测试基线入口，记录 fixture 模板、对话回放式 E2E 和运行方式。
- `tests/unit/` 是维护者专用测试套件，依赖 `bats`；该依赖为可选维护依赖，仅用于本仓库验证，不是 Skill 运行时依赖。
- 部署到目标项目时不会安装或携带 `bats`，也不会携带测试目录。

## 安装与删除

### 安装

优先在**项目级别**安装此 Skill。若某个客户端只支持用户级 Skill 目录，完成目标项目部署后可删除该 Skill 目录。

Claude Code：

```
# 将整个 docs-governance/ 目录放到目标项目的 .claude/skills/ 下
cp -r docs-governance/ <target-project>/.claude/skills/
```

Codex：

```
# 使用 Codex 当前支持的 skills 目录；agents/openai.yaml 提供 Codex 适配元数据
cp -r docs-governance/ <codex-skills-dir>/
```

通用 Agent Skills 客户端：

```
# 将整个目录作为一个 Skill 包安装，入口文件为 SKILL.md
cp -r docs-governance/ <agent-skills-dir>/
```

兼容细节见 [references/agent-compatibility.md](references/agent-compatibility.md)。

### 删除

初始化完成后，此 Skill 可**安全删除**：

```
rm -rf <installed-skills-dir>/docs-governance/
```

项目的治理体系（AGENTS.md + docs/ + 已安装的脚本资产）独立存在，不受 Skill 删除影响。`docs/harness/maintenance.md` 包含所有维护所需的知识，AI 仅凭项目文档即可执行后续维护操作。

Skill 的后续版本更新对已完成初始化的项目没有影响。如需新增初始化时跳过的约束，重新安装最新版 Skill 执行即可。

## 使用方式

Skill 存在时，通过 `/docs-governance` 显式命令激活。Skill 不在日常 AI 协作中自动介入。

Skill 删除后，AI 读取项目中的 `docs/harness/maintenance.md` 自行处理所有维护意图。

## 非技术说明

- `harness/guides` 是 AI 做事前看的规则卡片，例如提交代码、写 PR、测试。
- `harness/sensors` 是检查设备，例如脚本、hook、CI、review checklist，会在 AI 做完后发现问题。
- `design-docs`、`exec-plans`、`product-specs`、`references` 是项目记忆，帮助 AI 下次接手时知道背景和进度。
- `archive` 存放过时内容，避免 AI 误用旧规则。
- 人负责定义方向和约束，AI 按路径读取、执行、接受检查、修正结果。

## 与 Agent 记忆系统的关系

本项目把仓库文档作为项目级长期记忆的单一事实源。应沉淀的是经过归纳的可复用结论，而不是完整聊天记录、临时假设或未确认方案。

LangChain、LangGraph、向量库或 AI 产品内置 memory 可以用于运行时检索、跨会话偏好、会话恢复和上下文召回，但不能替代仓库内的 `AGENTS.md` 与 `docs/`。外部记忆系统中的有价值内容，应整理成 ADR、排障记录、研究记录或规则文档后回写项目，并通过 AGENTS.md 索引暴露给后续 Agent。

## 参考引用

- [OpenAI — Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/) — 本 Skill 的设计哲学来源
- [Martin Fowler — Harness Engineering](https://martinfowler.com/articles/harness-engineering.html) — Guides × Sensors 控制论框架
- [agentsmd/agents.md](https://github.com/agentsmd/agents.md) — AGENTS.md 开放格式规范，本项目的文档体系根节点遵循此标准
- [microsoft/skills](https://github.com/microsoft/skills) — 微软官方的 Skills、MCP servers、Agents.md 集合
- [agent-sh/agnix](https://github.com/agent-sh/agnix) — AGENTS.md / CLAUDE.md / SKILL.md 的 linter 和 LSP，与诊断功能互补
