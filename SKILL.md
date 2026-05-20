---
name: dayu-harness
description: 大禹治库 Skill（Dayu Harness Skill）是帮助项目低成本接入 Harness Engineering 理念的一次性部署工具。将以 AGENTS.md 为根的渐进式披露治理体系部署到目标项目。仅通过 /dayu-harness 显式命令激活。
metadata:
  invocation_policy: "explicit-command-only"
  command: "/dayu-harness"
  compatible_agents: "agent-skills-common, claude-code, codex"
---

# Dayu Harness Skill

## 定位

大禹治库 Skill 是管理和维护项目治理体系的**一次性部署工具**，不是治理体系本身。Skill 目录中的模板、脚本和资产只是部署来源；被部署到目标项目中的 AGENTS.md、docs/ 文档、hooks、CI 与维护脚本，才是 Harness Engineering 治理体系的实际载体。以 AGENTS.md 为根的渐进式披露文档体系是最终权威。初始化完成后，Skill 可安全删除——项目的治理体系已独立运行。

“大禹”取自大禹治水：不把洪流堵在一处，而是疏导、分流并建立长期秩序。被部署到目标项目的治理体系，其设计哲学源自 [Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/)：工程师不再手写每行代码，而是设计约束环境、明确意图边界、构建反馈回路，让 AI 智能体可靠工作。目标项目内的文档和资产对应 HE 六大概念——AGENTS.md 是「地图而非手册」、docs/ 目录是「仓库即记录系统」、hooks + CI 是「机械化执行」、CLAUDE.md 渐进式路由是「智能体可读性」、archive/ + `docs/harness/maintenance.md` 是「熵管理」、ai-execution.md + ai-memory.md 是「人类掌舵，智能体执行，并把经验沉淀回项目」。

直接把治理规则只做成 Skill，只能让某个 Agent 在当前环境中按规则工作，属于 Agent-centric 约束。大禹治库 Skill 的目标是 Project-centric：把长期规则、项目知识/经验和机械化反馈部署进目标仓库，使它们可版本化、可审查、可迁移，并且不依赖某个 Skill、会话或工具长期存在。

## 激活条件

Skill 仅通过显式命令激活：用户输入 `/dayu-harness`。

Skill 不在日常 AI 协作中自动介入。Skill 删除后，治理体系的维护由 AI 读取项目中的 `docs/harness/maintenance.md` 自行处理。

为兼容 Claude、Codex 和通用 Agent Skills 客户端，canonical `SKILL.md` 不使用工具专属 frontmatter。具体适配策略见 [references/agent-compatibility.md](references/agent-compatibility.md)。

## 边界规则

- Skill 仅在用户显式调用 `/dayu-harness` 时工作
- 项目无 AGENTS.md → 进入脚手架模式
- 项目已有文档体系但不完整 → 进入融合模式
- 项目已有完整体系，用户要求增删改约束 → 进入维护模式
- 项目已有完整体系，用户要求检查完整性 → 进入诊断模式
- 所有操作前先分析项目现状，基于 [Q&A-TEMPLATE.md](Q&A-TEMPLATE.md) 适配提问；默认治理与 Git 能力不作为是否启用的问题，只在已有配置需要合并策略时确认
- 所有面向用户的提问和选项必须中英双语展示，格式为中文在前、英文在后；选项使用 `[1] 中文 / English`，默认项写明 `（默认，推荐）/ (default, recommended)`
- 可选的 GitHub 仓库设置/Issue/PR/TDD/发布能力默认只输出配置、策略文件和执行说明，不直接调用 GitHub API 修改仓库远端设置；是否应用远端变更由用户在目标仓库确认。
- 部署/融合前统一执行 `scripts/ensure-environment.sh <project-root> --check --capabilities "<resolved capability ids>"`；尚未确定可选能力时不传 `--capabilities`，脚本按默认必选能力检查。若返回 `needs_install`、`needs_initialization` 或 `needs_user_action`，先向用户展示安装/初始化建议并确认；若用户拒绝，当前流程终止
- 任何涉及已有配置的操作，按能力清单中的可管理项/联动组件逐项处理：installer-backed 组件（如 husky hook 片段、`.gitignore`）先走 manifest installer 的 `--check`；静态模板/资产文件组件（如 `commitlint.config.cjs`、ESLint/Prettier/lint-staged 配置文件、`.github/workflows`、ruleset JSON）改用 `scaffold.sh --dry-run` 输出变更预览；若可提供现有文件与目标文件对，优先调用 `diff-helper.sh merge-plan <existing> <incoming>`；否则继续基于 `scaffold.sh --dry-run` 做人工确认
- **不覆盖已有配置**，必须经用户确认
- 部署、融合、维护或生成操作完成后，必须执行收尾验证，并按 [docs/completion-report-template.md](docs/completion-report-template.md) 用自然语言向用户汇报结果

## 5 个模式

### 1. 脚手架

触发：项目无 AGENTS.md

1. 前置执行 `scripts/ensure-environment.sh <project-root> --check --capabilities "<resolved capability ids>"`，处理并确认 Git/Node 初始化需求（见 Q&A 前置问题；尚未确定可选能力时使用默认必选能力检查）
2. 分析项目现状（读取文件结构、已有配置）
3. 按 [Q&A-TEMPLATE.md](Q&A-TEMPLATE.md) 询问 GitHub、发布、代码工具等可选能力（默认治理与 Git 能力直接纳入部署）
4. 展示确认汇总
5. 用户确认后：调用 `scaffold.sh --dry-run --enable <optional capability ids>` 预览变更 → 对已有配置确认策略 → `scaffold.sh --apply --enable <optional capability ids>`（如有冲突再加 `--strategy`）复制默认与可选模板文档 + 安装联动的脚本资产 + 始终部署核心维护脚本
6. 按「执行收尾验证」流程检查部署结果，并使用完成报告模板向用户汇报

### 2. 诊断

触发：已有项目，检查完整性

1. 优先执行 `audit.sh --json` 获取结构化诊断报告
2. 将报告中的 `description_nl` 和 `results` 以自然语言呈现给用户
3. 若 audit.sh 不可用，按 `docs/harness/maintenance.md` 诊断清单手动逐项检查
4. 报告缺失/冲突，给出修复建议

### 3. 融合

触发：已有文档体系，需要合并

1. 诊断现有状态（调用 `audit.sh --json`）
2. 对每个已有组件按能力 manifest 中的联动项区分：
   - 有 manifest installer 的组件：调用对应 installer 脚本 `--check` 获取结构化 merge plan
   - 无 installer 的组件（静态模板/资产文件）：先用 `scaffold.sh --dry-run` 获取差异说明；若有源文件和目标文件对可用，再补充 `diff-helper.sh merge-plan <existing> <incoming>` 的结构化说明，再展示给用户
3. 将 merge plan 或差异说明中的 `description_nl` 以自然语言呈现给用户
4. 逐项双语询问：[1] 保留现有 / Keep existing [2] 替换 / Replace [3] 合并 / Merge [4] 跳过 / Skip
5. 用户逐项确认后，按组件类型执行：
   - installer-backed 组件：调用对应 installer `--apply <merge|replace|skip>`
   - 无 installer 组件：按用户确认方案，用 `scaffold.sh --apply` 或手工更新
6. 按「执行收尾验证」流程检查融合结果，并使用完成报告模板向用户汇报

### 4. 维护

触发：用户要求增删改约束或更新文档

子功能：
- **删除约束**：按联动组件逐项处理：installer-backed 组件先调用相关 installer 的 `--check` 获取影响范围；无 installer 组件先用 `scaffold.sh --dry-run` 标注待删差异并确认（如有源文件与目标文件对可用，再调用 `diff-helper.sh merge-plan <existing> <incoming>`） → 展示 → 确认 → 移除 → 更新 AGENTS.md 索引
- **修改约束**：有现有/目标文件对时调用 `diff-helper.sh merge-plan <existing> <incoming>` 获取变更描述；无可用对时回退到 `scaffold.sh --dry-run` 的人工审核输出 → 展示 → 确认 → 更新
- **完整性检查**：同诊断模式
- **更新项目文档**：按 `docs/harness/maintenance.md` 流程 → 更新内容 → 同步索引

### 5. 生成

触发：需要特定文档或配置

根据项目特征和 `docs/harness/maintenance.md` 中的 Q&A 决策参考，智能生成适配内容。

## 执行收尾验证

Skill 完成任何写入类操作后，不能只告诉用户“已完成”。必须先验证目标项目中的治理体系是否能正常使用，再用自然语言收尾。

收尾验证优先使用目标项目内已部署的脚本：

1. `docs/harness/sensors/scripts/validate.sh --json <project-root>`：检查已启用的 hooks、配置和 workflow 是否可用。
2. `docs/harness/sensors/scripts/audit.sh --json <project-root>`：检查 `AGENTS.md`、`CLAUDE.md`、docs 索引和维护脚本是否完整。
3. `docs/harness/sensors/scripts/check-consistency.sh --json <project-root>`：检查文档链接、索引和孤儿文档。

如果脚本不存在或暂时不可执行，按目标项目中的 `docs/harness/maintenance.md` 手动检查关键路径。

验证后处理规则：

- 检查通过：按 [docs/completion-report-template.md](docs/completion-report-template.md) 汇报已启用能力、已确认事项和未启用事项。
- 检查发现可确定修复的问题：先修复，再重新运行检查。
- 检查发现需要用户取舍的问题：说明影响，用自然语言询问用户选择，不输出大段原始日志。
- 未启用的能力出现 skip 或可选缺失时，不作为失败汇报，只说明这次没有安装相关内容。

## 部署后的项目知识/经验沉淀约定

该约定会写入目标项目的 `ai-memory.md`。每次 AI 协作会话中，如产生可复用的项目知识、经验或上下文，主动建议沉淀到对应位置：

| 类型 | 沉淀位置 |
|---------|---------|
| 架构/技术决策 | `docs/design-docs/` |
| 问题排障 | `docs/troubleshooting/` |
| 研究发现 | `docs/references/research/` |
| 约束变更 | `docs/harness/guides/` + AGENTS.md |
| 项目背景和产品上下文 | `docs/product-specs/` |

写入目标项目后，该约定确保 Skill 删除后 AI 仍能自主沉淀项目知识/经验。

沉淀边界：
- 只沉淀经过归纳的可复用结论，不把完整对话记录、临时假设、未确认方案或敏感信息写入长期目录。
- 目标项目中的 `AGENTS.md` 与 `docs/` 是项目级长期记忆的单一事实源；外部 Agent memory、LangChain/LangGraph store、向量库或产品内置记忆只能作为检索缓存或运行时辅助，不作为权威规则来源。
- 外部记忆系统产生的有价值内容，必须整理成决策、排障、研究、项目上下文或约束文档后回写项目，并同步对应 `AGENTS.md` 索引。

## 部署策略

- 必选默认能力始终部署：`core`、Git 提交/.gitignore 约束、AI 执行/记忆规则、ADR、排障、研究、项目上下文和归档入口
- `--enable` 只表示在必选默认集上追加可选能力；GitHub、发布自动化、Node.js 工具等能力未选择时不复制到项目
- 未启用的可选资产不复制到项目
- `docs/harness/sensors/scripts/`（audit.sh、validate.sh、diff-helper.sh、check-consistency.sh）始终部署
- 后续需要新增约束时，重新安装 Skill 执行

## 结构化输出约定

本 Skill 所有脚本遵循统一的分工协议——脚本负责确定性分析，LLM 负责语义增强和用户交互：

| 脚本层职责 | LLM 层职责 |
|-----------|-----------|
| 检测已有配置状态 | 读取结构化报告 |
| 生成 diff 和行数统计 | 将 `description_nl` 以自然语言呈现给用户 |
| 输出结构化 JSON（含 `description_nl`） | 确认用户选择 |
| 执行写入操作（--apply 模式） | 调用脚本执行 |
| smoke test / audit / consistency 验证 | 按完成报告模板呈现自然语言结果 |

关键约定：
- 所有脚本 `--json` 模式输出纯 JSON 到 stdout，诊断日志到 stderr
- 每个 JSON 响应必须包含 `description_nl` 字段（自然语言描述，LLM 可直接使用）
- 环境前置脚本 `ensure-environment.sh --check [--capabilities "<resolved ids>"]` 必须输出统一字段：`status`、`items`、`summary`、`description_nl`；其中 `status` 至少支持 `ok/needs_install/needs_initialization/needs_user_action/error`
- 退出码：0=成功/无变更，1=检测到冲突/失败，2=脚本自身错误
- LLM 不应自行解析原始 diff 或文件内容来替代脚本的结构化输出

## 能力清单约定

- `capabilities/*.json` 是治理能力的单一事实源，定义 `id`、依赖、模板文件、资产文件、installer、安全策略和 acceptance criteria。
- `default=true` 的 manifest 是无须用户选择的必选部署集：`core`、Git 提交/.gitignore 约束、AI 执行/记忆规则和知识库/项目上下文目录。通用质量实践、GitHub CI、release-please、Node.js 工具和发布/分支保护类能力仍按 capability 显式启用。
- Q&A、dry-run plan、安装清单和测试断言应从 manifest 字段生成或校验，避免手工维护重复计数。

## 辅助文件

Skill 目录中的其他文件按需加载：

- **[AGENTS.md](AGENTS.md)**：Skill 自身渐进式披露入口，路由到各模块。
- **[Q&A-TEMPLATE.md](Q&A-TEMPLATE.md)**：Q&A 参考模板，提问内容以 `capabilities/*.json` 为准，包含融合模式提问和兼容化处理流程。脚手架和融合模式时读取。
- **[docs/completion-report-template.md](docs/completion-report-template.md)**：Skill 执行完成后的验证流程和自然语言收尾模板。部署、融合、维护或生成操作完成后读取。
- **[references/agent-compatibility.md](references/agent-compatibility.md)**：Claude、Codex 和通用 Agent Skills 客户端的兼容说明。需要安装、分发或调整触发策略时读取。
- **[capabilities/](capabilities/)**：治理能力 manifest，作为脚手架、Q&A、部署清单、依赖关系和验收标准的单一事实源。
- **[templates/](templates/)**：文档模板（CLAUDE.md、AGENTS.md、docs/ 完整层级结构），部署到目标项目的 `docs/` 目录。
- **[assets/](assets/)**：脚本和配置资产（husky hooks、commitlint、GitHub workflows、ESLint、Prettier、lint-staged、gitignore），默认 Git 资产和用户选择的可选资产会部署到项目对应位置。
- **[scripts/](scripts/)**：Skill 内部初始化脚本（`scaffold.sh`、`install-husky.sh`、`install-gitignore.sh`；其余能力按 manifest 指定 `installer.script` 调用），由各模式按需调用。`ensure-environment.sh` 负责环境依赖完整性与初始化确认。
- **[tests/](tests/)**：Skill 自身测试（维护者可选 bats 单元测试 + fixture 项目）；非运行时依赖，不会部署到目标项目。
- **[docs/plan.md](docs/plan.md)**：Skill 设计计划和架构文档，仅供 Skill 维护者参考。
