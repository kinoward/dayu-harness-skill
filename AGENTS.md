# AGENTS.md

Skill 自身入口。本 Skill 帮助项目建立以 AGENTS.md 为根的渐进式披露文档体系。

## 目录索引

- [AGENTS.md](AGENTS.md) - 当前索引
- [SKILL.md](SKILL.md) - Skill 行为定义
- [README.md](README.md) - 使用者阅读概述与安装指南
- [README.en.md](README.en.md) - 英文镜像说明文档
- [.gitignore](.gitignore) - 本仓库临时测试产物忽略规则
- [.tmp/](.tmp/) - 仓库内测试临时目录占位与运行时缓存承载
- [package.json](package.json) - 本地 TypeScript schema 与验证工具链入口
- [package-lock.json](package-lock.json) - Node 依赖锁定文件
- [tsconfig.json](tsconfig.json) - TypeScript 编译与测试配置
- [.github/workflows/update-contributors.yml](.github/workflows/update-contributors.yml) - README 动态区块自动更新工作流
- [Q&A-TEMPLATE.md](Q&A-TEMPLATE.md) - 初始化与融合问答参考
- [LICENSE](LICENSE) - MIT 许可文件
- [src/](src/) - Phase 1 TypeScript schema、架构契约、CLI 垂直切片与本地验证源码
- [locales/](locales/) - key-based i18n 文案 catalog
- [agents/](agents/) - Codex UI 与触发策略元数据
- [references/agent-compatibility.md](references/agent-compatibility.md) - 跨 Agent 兼容说明
- [capabilities/](capabilities/) - 治理能力 manifest，部署清单单一事实源
- [templates/](templates/) - 部署到目标项目的文档模板
- [templates.en/](templates.en/) - 英文部署模板镜像树
- [assets/](assets/) - README 展示资产，以及按能力部署的 hook、CI、配置资产
- [marketing/](marketing/) - 独立对外传播物料，不参与 Skill 功能或部署产物
- [scripts/](scripts/) - Skill 内部环境前置、初始化与安装脚本
- [scripts/check-i18n-drift.sh](scripts/check-i18n-drift.sh) - README 与部署模板镜像漂移检查
- [scripts/github-remote.sh](scripts/github-remote.sh) - GitHub 远端检查、创建/绑定、推送与远端能力验证脚本
- [docs/AGENTS.md](docs/AGENTS.md) - Skill 自身文档入口
- [docs/phase1d-cli.md](docs/phase1d-cli.md) - Phase 1d TypeScript CLI 垂直切片命令语义、边界和验证方式
- [tests/](tests/) - Skill 自身测试和 fixture 项目
- [tests/README.md](tests/README.md) - Skill 自身执行测试基线
- [tests/smoke/dayu-harness-profile.sh](tests/smoke/dayu-harness-profile.sh) - local-fast / remote-smoke / remote-release 分层测试入口

目录索引变化时，必须同步更新本区块。README 面向使用者，不维护完整仓库目录树；如目录变化影响使用方式或对外说明，再同步更新 [README.md](README.md) 的简版介绍。

## Skill 定位

Dayu Harness Skill 面向 Harness Engineering 风格的项目治理：人类定义约束，智能体执行任务，脚本检查结果，仓库沉淀长期记录。

本 Skill 不是目标项目的长期运行时服务。它是一次性部署、融合、诊断、维护和生成入口；长期真相位于目标项目内的 `AGENTS.md`、`docs/`、hooks、CI 和维护脚本。

核心转变：

```text
普通 AI 协作：人类在对话里反复提醒 Agent
Dayu Harness：人类把约束写入仓库 -> Agent 读取地图 -> 脚本检查结果 -> 经验回写项目
```

## 核心观念

1. **Project-centric，而不是 Agent-centric**

   Skill 只负责部署和升级。长期生效的是目标项目中的 `AGENTS.md`、`docs/`、hooks、CI 和脚本。

2. **AGENTS.md 优先承担项目地图职责**

   根索引负责路由和维护事实，子目录索引提供局部上下文，具体指南和传感器脚本承担执行约束。

3. **能力清单是单一事实源**

   `capabilities/*.json` 定义能力 ID、依赖、模板、资产、installer、安全策略和验收标准。Phase 1b 试点能力开始补充 `schemaVersion`、`kind`、`deployment_deps`、`conceptual_deps`、`i18n` 和 `rse` 字段；迁移期间旧 `dependencies` 字段必须继续保留，并与 `deployment_deps` 保持一致，供现有 `scaffold.sh` 兼容使用。Phase 1c 将 CLI 命令树、部署 DAG、概念依赖图和三层分离约束固化在 `src/architecture/` 与 `docs/phase1c-architecture.md`。Phase 1d 在 `src/cli/` 提供 3 个能力的 TypeScript CLI 垂直切片，验证 config handoff、dry-run、apply、diagnose、merge plan、validate 和 generate。

4. **机械化检查优先于文字承诺**

   文档可以描述规则，但 `validate.sh`、`audit.sh`、`check-consistency.sh`、Git hooks 和 CI 才负责持续反馈。

5. **已有配置默认不覆盖**

   对现有 hooks、GitHub workflows、lint 配置和发布配置，先 dry-run 或生成 merge plan，再由用户确认保留、替换、合并或跳过。

6. **经验要回写项目**

   可复用的架构决策、排障经验、研究结论、产品上下文和治理约束，应沉淀到 `docs/`，并同步对应 `AGENTS.md` 索引。

## 工作模式

| 模式 | 触发条件 | 行为 |
| --- | --- | --- |
| 脚手架 | 项目没有 `AGENTS.md` | 初始化治理骨架，安装默认能力，按需启用可选能力。 |
| 诊断 | 用户要求检查完整性 | 优先运行目标项目内的 audit / consistency 检查脚本，输出自然语言诊断。 |
| 融合 | 项目已有文档或配置 | 对已有 `docs/`、hooks、CI、lint 配置生成 merge plan，逐项确认后合并。 |
| 维护 | 用户要求增删改约束 | 按 manifest 找到联动文档、资产和索引，更新后重新验证。 |
| 生成 | 用户要求生成特定文档或配置 | 依据 `docs/harness/maintenance.md` 和项目上下文生成适配内容。 |

## 能力清单

`capabilities/*.json` 是部署清单的单一事实源。默认能力始终安装；可选能力由用户在脚手架、融合或维护流程中选择。Phase 1b 试点能力开始采用 manifest v2 字段：`schemaVersion`、`kind`、`deployment_deps`、`conceptual_deps`、`i18n` 和 `rse`；其中 `kind` 区分 hard / soft / infra 能力，`rse` 描述 Rule-Sensor-Enforcer 链路或其子集。Phase 1c 明确 `deployment_deps` 只服务 CLI apply 的部署顺序，`conceptual_deps` 只服务 Skill/CLI 的说明与展示顺序，不阻塞部署。Phase 1d 只加载 `core`、`git.hooks`、`git.commit-format`、`ai.execution` 四个 v2 试点能力，完整能力迁移留到 Phase 2。未迁移能力仍按旧 manifest 字段服务现有脚手架流程。

| 分组 | 能力 ID | 部署内容 |
| --- | --- | --- |
| 核心治理 | `core` | 根 `AGENTS.md`、`docs/` 索引、`docs/harness/maintenance.md`、执行计划、生成区和检查脚本骨架。 |
| Git 基线 | `git.commit-format`、`project.gitignore` | 约定式提交指南、`commitlint.config.cjs`、commit-msg hook 片段和可合并 `.gitignore`。 |
| AI 协作 | `ai.execution`、`ai.memory` | AI 执行边界、协作姿态、自动重试、汇报规则、长期记忆边界和外部记忆回写规则。 |
| 知识沉淀 | `knowledge.adr`、`knowledge.troubleshooting`、`knowledge.research`、`project.context`、`knowledge.archive` | ADR、排障、研究资料、产品上下文和历史归档目录。 |
| GitHub 可选 | `github.repository-settings`、`github.pr`、`github.issue`、`github.branch-protection` | 仓库设置说明、PR 指南、Issue 依赖约定、审查清单、PR 正文检查工作流、分支保护规则集和 pre-push 片段。 |
| 发布可选 | `release.versioning`、`github.release-please` | 版本与 tag 规则、发布指南、release-please 工作流和配置。 |
| 质量可选 | `quality.practices`、`quality.node-tooling`、`quality.tdd` | 通用开发纪律、测试策略、ESLint、Prettier、lint-staged、pre-commit hook 片段和可配置 TDD 门禁。 |
| 内部承载 | `git.hooks` | hook 片段的内部承载能力，不作为独立业务治理入口。 |

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

常用命令：

| 命令 | 用途 |
| --- | --- |
| `/dayu-harness` | Skill 显式入口。 |
| `scripts/scaffold.sh <project-root> --dry-run --enable <optional ids>` | 预览默认能力与可选能力的部署计划。 |
| `scripts/scaffold.sh <project-root> --apply --enable <optional ids>` | 应用用户确认后的部署计划。 |
| `docs/harness/sensors/scripts/validate.sh --json <project-root>` | 在目标项目中检查启用的 hooks、配置和工作流。 |
| `docs/harness/sensors/scripts/audit.sh --json <project-root>` | 检查入口文件、文档索引和治理结构完整性。 |
| `docs/harness/sensors/scripts/check-consistency.sh --json <project-root>` | 检查文档链接、索引同步和孤儿文档。 |
| `docs/harness/sensors/scripts/dayu-format.mjs pr-body|issue-body|commit-message ...` | 确定性生成 PR、Issue、commit 等固定格式内容。 |
| `docs/harness/sensors/scripts/diff-helper.sh merge-plan <existing> <incoming>` | 为已有文件和即将写入文件生成结构化合并建议。 |

## 目标项目产物

部署后的典型目标项目结构：

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
│   │   │   ├── github-repository-settings.md # 可选：github.repository-settings
│   │   │   ├── pr-guidelines.md       # 可选：github.pr
│   │   │   ├── issue-guidelines.md    # 可选：github.issue
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
│   │       │   ├── dayu-format.mjs
│   │       │   ├── diff-helper.sh
│   │       │   └── validate.sh
│   │       └── reviews/
│   │           ├── AGENTS.md
│   │           └── code-review-checklist.md  # 可选：github.pr
│   ├── design-docs/
│   ├── exec-plans/
│   ├── generated/
│   ├── product-specs/
│   │   ├── AGENTS.md                        # 约定：项目上下文与状态文档目录
│   │   └── project-status.md                # 可选：project.context 的默认部署文件，简版项目状态快照
│   ├── references/
│   ├── troubleshooting/
│   └── archive/
├── .husky/                            # 默认：git.hooks + hook 承载的 Git 能力
├── .github/                           # 可选：GitHub 工作流、规则集、仓库设置与 release 资产
│   ├── ISSUE_TEMPLATE/                # 可选：Issue 模板目录
│   │   └── dayu-harness-issue.md     # 可选：Issue 输入模板
│   ├── pull_request_template.md        # 可选：PR 输入模板
│   ├── repository/                    # 可选：仓库设置策略模板区
│   │   └── pull-request-settings.json  # 可选：PR 设置策略模板
│   ├── dayu-harness/                  # 可选：TDD 策略文件目录
│   │   └── pr-tdd-policy.json         # 可选：PR TDD 门禁策略文件
│   ├── release-please-policy.json      # 可选：仓库策略与 release-please 过滤策略
│   ├── scripts/
│       ├── issue_depends_on.py         # 可选：Issue 依赖关系解析脚本
│       ├── pr_body_structure.py        # 可选：PR 正文结构校验脚本
│       ├── pr_tdd_check.py             # 可选：PR TDD 门禁脚本
│       └── release_please_policy.py    # 可选：release-please 策略校验脚本
│   └── workflows/
│       ├── issue-lint.yml              # 可选：Issue 依赖治理 workflow
│       ├── pr-lint.yml                 # 可选：PR 正文结构治理 workflow
│       └── release-please.yml          # 可选：release-please workflow
├── commitlint.config.cjs              # 默认：git.commit-format
├── eslint.config.cjs                  # 可选：quality.node-tooling
├── .prettierrc                        # 可选：quality.node-tooling
├── .lintstagedrc.json                 # 可选：quality.node-tooling
├── .gitignore                         # 默认：project.gitignore
├── release-please-config.json         # 可选：github.release-please
└── .release-please-manifest.json      # 可选：github.release-please
```

项目状态短快照位点：`docs/product-specs/project-status.md`

沉淀位置：

| 类型 | 沉淀位置 |
| --- | --- |
| 架构/技术决策 | `docs/design-docs/` |
| 问题排障 | `docs/troubleshooting/` |
| 研究发现 | `docs/references/research/` |
| 约束变更 | `docs/harness/guides/` + `AGENTS.md` |
| 项目背景和产品上下文 | `docs/product-specs/`（含 `project-status.md`） |
| 历史内容 | `docs/archive/` |

## 依赖兼容

- 核心依赖由 `scripts/ensure-environment.sh` 检查。
- 文档与脚本依赖 `jq`、`git`、`node`、`npm`、`npx`，以及能力相关的 GitHub/Node 工具链。
- GitHub 能力需要 `gh` 登录与认证上下文。
- 目标项目的运行与安装不依赖 `bats`；`bats` 只服务本仓库维护者测试。
- Claude、Codex 和通用 Agent Skills 客户端的兼容说明见 [references/agent-compatibility.md](references/agent-compatibility.md)。

## 运行边界

- 运行时检索系统、向量库、上下文缓存或外部智能体记忆可以提升效率，但不能替代仓库内可审查的治理事实。
- 外部知识有价值时，应整理成决策、排障、研究、项目上下文或约束文档后回写项目，并同步对应 `AGENTS.md` 索引。
- README 面向使用者，只保留安装、使用方式和基本解释；项目内部规则、能力 ID、测试流程和维护说明放在 AGENTS 体系内。
- 英文镜像文档只能翻译中文源文档的文本语义，不得重排原有 Markdown/HTML 格式结构；标题层级、列表层级、表格、引用、代码块、链接行、动态区块和目录树展示需与中文源保持同版式，并用 `scripts/check-i18n-drift.sh --json` 检查。
- Skill 运行时的提问和选项必须中英双语展示，中文在前、英文在后；默认项、确认、取消、跳过、保留、替换、合并等选择都要写成 `中文 / English`，避免英文用户无法判断选项含义。

## 理解 Skill

> 触发时机：需要理解 Skill 的定位、行为和模式时读取

- Skill 行为定义：[SKILL.md](SKILL.md)
- 使用者阅读概述：[README.md](README.md)
- 跨 Agent 兼容说明：[references/agent-compatibility.md](references/agent-compatibility.md)

## 维护 Skill

> 触发时机：修改 Skill 自身设计或实现时读取

- 设计计划：[docs/plan.md](docs/plan.md)
- Phase 1c 架构契约：[docs/phase1c-architecture.md](docs/phase1c-architecture.md)
- Phase 1d CLI 垂直切片：[docs/phase1d-cli.md](docs/phase1d-cli.md)
- scaffold.sh 内部逻辑 spike：[docs/scaffold-sh-spike.md](docs/scaffold-sh-spike.md)
- Q&A 参考模板：[Q&A-TEMPLATE.md](Q&A-TEMPLATE.md)
- 执行完成报告模板：[docs/completion-report-template.md](docs/completion-report-template.md)
- README 贡献者与 Star 数量更新脚本：[scripts/update-readme-contributors.mjs](scripts/update-readme-contributors.mjs)

## Skill 产物

> 触发时机：理解 Skill 的产出和部署目标时读取

- 中文文档模板：[templates/](templates/)
- 英文模板镜像：[templates.en/](templates.en/)
- 脚本与配置资产：[assets/](assets/)
- 内部环境前置、初始化与安装脚本：[scripts/](scripts/)
- Skill 自身文档：[docs/AGENTS.md](docs/AGENTS.md)

## 测试

> 触发时机：修改 Skill 后需要验证时读取

- 测试目录：[tests/](tests/)
- 执行测试基线：[tests/README.md](tests/README.md)

维护本 Skill 后，建议按以下顺序执行：

```bash
npm run test:phase1b -- --test-reporter=spec
npm run test:phase1c -- --test-reporter=spec
npm run test:phase1d -- --test-reporter=spec
npm run test:unit -- --test-reporter=spec
npx tsc --noEmit
bats tests/unit/test-architecture-contracts.bats
bats tests/unit/test-audit.bats
bats tests/unit/test-skill-interaction-e2e.bats
bats tests/unit
```

验证重点：

- `AGENTS.md` 目录索引完整性。
- Phase 1b schema、Phase 1c 架构契约、Phase 1d CLI 垂直切片、能力 manifest 与模板/资产映射一致性。
- 环境预检、dry-run 预览、merge plan 合并计划和收尾验证流程。
- 默认能力与可选能力的部署结果。

## 参考引用

- [微信公众号「浮之静」：《深度解析：Harness Engineering》](https://mp.weixin.qq.com/s/-mgf8K7XZrTKoD0pMOIn3w)：项目治理与 AI 协作理念参考。
- [OpenAI: Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/)：本 Skill 的设计哲学来源。
- [deusyu/harness-engineering](https://github.com/deusyu/harness-engineering)：README 信息层次、概念先行叙事和 AGENTS.md 渐进式披露实践参考。
- [Martin Fowler: Harness Engineering](https://martinfowler.com/articles/harness-engineering.html)：Guides 与 Sensors 控制论框架参考。
- [agentsmd/agents.md](https://github.com/agentsmd/agents.md)：AGENTS.md 开放格式规范。
- [microsoft/skills](https://github.com/microsoft/skills)：技能声明与客户端兼容实践。
