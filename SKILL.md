---
name: docs-governance
description: 帮助项目低成本接入 Harness Engineering 理念的一次性部署工具。将以 AGENTS.md 为根的渐进式披露治理体系部署到目标项目。仅通过 /docs-governance 显式命令激活。
metadata:
  invocation_policy: "explicit-command-only"
  command: "/docs-governance"
  compatible_agents: "agent-skills-common, claude-code, codex"
---

# docs-governance

## 定位

本 Skill 是管理和维护项目治理体系的**一次性部署工具**，不是治理体系本身。Skill 目录中的模板、脚本和资产只是部署来源；被部署到目标项目中的 AGENTS.md、docs/ 文档、hooks、CI 与维护脚本，才是 Harness Engineering 治理体系的实际载体。以 AGENTS.md 为根的渐进式披露文档体系是最终权威。初始化完成后，Skill 可安全删除——项目的治理体系已独立运行。

被部署到目标项目的治理体系，其设计哲学源自 [Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/)：工程师不再手写每行代码，而是设计约束环境、明确意图边界、构建反馈回路，让 AI 智能体可靠工作。目标项目内的文档和资产对应 HE 六大概念——AGENTS.md 是「地图而非手册」、docs/ 目录是「仓库即记录系统」、hooks + CI 是「机械化执行」、CLAUDE.md 渐进式路由是「智能体可读性」、archive/ + `docs/harness/maintenance.md` 是「熵管理」、ai-execution.md + ai-memory.md 是「人类掌舵，智能体执行，并把经验沉淀回项目」。

直接把治理规则只做成 Skill，只能让某个 Agent 在当前环境中按规则工作，属于 Agent-centric 约束。docs-governance 的目标是 Project-centric：把长期规则、项目记忆和机械化反馈部署进目标仓库，使它们可版本化、可 review、可迁移，并且不依赖某个 Skill、会话或工具长期存在。

## 激活条件

Skill 仅通过显式命令激活：用户输入 `/docs-governance`。

Skill 不在日常 AI 协作中自动介入。Skill 删除后，治理体系的维护由 AI 读取项目中的 `docs/harness/maintenance.md` 自行处理。

为兼容 Claude、Codex 和通用 Agent Skills 客户端，canonical `SKILL.md` 不使用工具专属 frontmatter。具体适配策略见 [references/agent-compatibility.md](references/agent-compatibility.md)。

## 边界规则

- Skill 仅在用户显式调用 `/docs-governance` 时工作
- 项目无 AGENTS.md → 进入脚手架模式
- 项目已有文档体系但不完整 → 进入融合模式
- 项目已有完整体系，用户要求增删改约束 → 进入维护模式
- 项目已有完整体系，用户要求检查完整性 → 进入诊断模式
- 所有操作前先分析项目现状，基于 [Q&A-TEMPLATE.md](Q&A-TEMPLATE.md) 适配提问
- 任何涉及已有配置的操作，使用脚本获取结构化 merge plan，用户确认后执行
- **不覆盖已有配置**，必须经用户确认
- 部署、融合、维护或生成操作完成后，必须执行收尾验证，并按 [docs/completion-report-template.md](docs/completion-report-template.md) 用自然语言向用户汇报结果

## 5 个模式

### 1. 脚手架

触发：项目无 AGENTS.md

1. 分析项目现状（读取文件结构、已有配置）
2. 按 [Q&A-TEMPLATE.md](Q&A-TEMPLATE.md) 连续提问（基于现状适配，不机械照搬）
3. 展示确认汇总
4. 用户确认后：调用 `scaffold.sh --dry-run --enable <capability ids>` 预览变更 → 确认策略 → `scaffold.sh --apply --enable <capability ids>` 复制启用的模板文档 + 安装联动的脚本资产 + 始终部署核心维护脚本
5. 按「执行收尾验证」流程检查部署结果，并使用完成报告模板向用户汇报

### 2. 诊断

触发：已有项目，检查完整性

1. 优先执行 `audit.sh --json` 获取结构化诊断报告
2. 将报告中的 `description_nl` 和 `results` 以自然语言呈现给用户
3. 若 audit.sh 不可用，按 `docs/harness/maintenance.md` 诊断清单手动逐项检查
4. 报告缺失/冲突，给出修复建议

### 3. 融合

触发：已有文档体系，需要合并

1. 诊断现有状态（调用 `audit.sh --json`）
2. 对每个已有配置，调用 `install-*.sh --check` 获取结构化 merge plan
3. 将 merge plan 中的 `description_nl` 以自然语言呈现给用户
4. 逐项询问：[1] 保留现有 [2] 替换 [3] 合并 [4] 跳过
5. 用户逐项确认后，调用 `install-*.sh --apply <merge|replace|skip>` 执行
6. 按「执行收尾验证」流程检查融合结果，并使用完成报告模板向用户汇报

### 4. 维护

触发：用户要求增删改约束或更新文档

子功能：
- **删除约束**：调用相关 `install-*.sh --check` 获取影响范围 → 展示 → 确认 → 移除 → 更新 AGENTS.md 索引
- **修改约束**：调用 `diff-helper.sh --json` 获取变更描述 → 展示 → 确认 → 更新
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

## 部署后的经验沉淀约定

该约定会写入目标项目的 `ai-memory.md`。每次 AI 协作会话中，如产生可复用的经验，主动建议沉淀到对应位置：

| 经验类型 | 沉淀位置 |
|---------|---------|
| 架构/技术决策 | `docs/design-docs/` |
| 问题排障 | `docs/troubleshooting/` |
| 研究发现 | `docs/references/research/` |
| 约束变更 | `docs/harness/guides/` + AGENTS.md |

写入目标项目后，该约定确保 Skill 删除后 AI 仍能自主沉淀经验。

沉淀边界：
- 只沉淀经过归纳的可复用结论，不把完整对话记录、临时假设、未确认方案或敏感信息写入长期目录。
- 目标项目中的 `AGENTS.md` 与 `docs/` 是项目级长期记忆的单一事实源；外部 Agent memory、LangChain/LangGraph store、向量库或产品内置记忆只能作为检索缓存或运行时辅助，不作为权威规则来源。
- 外部记忆系统产生的有价值经验，必须整理成决策、排障、研究或约束文档后回写项目，并同步对应 `AGENTS.md` 索引。

## 部署策略

- 仅部署用户选择启用的文档和资产
- 未启用的资产不复制到项目
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
- 退出码：0=成功/无变更，1=检测到冲突/失败，2=脚本自身错误
- LLM 不应自行解析原始 diff 或文件内容来替代脚本的结构化输出

## 能力清单约定

- `capabilities/*.json` 是治理能力的单一事实源，定义 `id`、依赖、模板文件、资产文件、installer、安全策略和 acceptance criteria。
- `core` 始终部署短根 `AGENTS.md`、`CLAUDE.md`、`docs/harness/maintenance.md`、harness 索引、exec-plans 索引、generated 索引与维护脚本；guide 文档、Git hooks、GitHub CI、release-please、知识库目录按 capability 启用。
- Q&A、dry-run plan、安装清单和测试断言应从 manifest 字段生成或校验，避免手工维护重复计数。

## 辅助文件

Skill 目录中的其他文件按需加载：

- **[AGENTS.md](AGENTS.md)**：Skill 自身渐进式披露入口，路由到各模块。
- **[Q&A-TEMPLATE.md](Q&A-TEMPLATE.md)**：Q&A 参考模板，提问内容以 `capabilities/*.json` 为准，包含融合模式提问和兼容化处理流程。脚手架和融合模式时读取。
- **[docs/completion-report-template.md](docs/completion-report-template.md)**：Skill 执行完成后的验证流程和自然语言收尾模板。部署、融合、维护或生成操作完成后读取。
- **[references/agent-compatibility.md](references/agent-compatibility.md)**：Claude、Codex 和通用 Agent Skills 客户端的兼容说明。需要安装、分发或调整触发策略时读取。
- **[capabilities/](capabilities/)**：治理能力 manifest，作为脚手架、Q&A、部署清单、依赖关系和验收标准的单一事实源。
- **[templates/](templates/)**：文档模板（CLAUDE.md、AGENTS.md、docs/ 完整层级结构），部署到目标项目的 `docs/` 目录。
- **[assets/](assets/)**：脚本和配置资产（husky hooks、commitlint、GitHub workflows、ESLint、Prettier、lint-staged、gitignore），按用户选择部署到项目对应位置。
- **[scripts/](scripts/)**：Skill 内部初始化脚本（scaffold.sh + install-*.sh），由各模式按需调用。
- **[tests/](tests/)**：Skill 自身测试（维护者可选 bats 单元测试 + fixture 项目）；非运行时依赖，不会部署到目标项目。
- **[docs/plan.md](docs/plan.md)**：Skill 设计计划和架构文档，仅供 Skill 维护者参考。
