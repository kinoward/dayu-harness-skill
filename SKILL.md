---
name: docs-governance
description: 帮助项目低成本接入 Harness Engineering 理念的一次性引导工具。建立以 AGENTS.md 为根的渐进式披露约束体系——仓库即记录系统、地图而非手册、机械化执行、智能体可读性、熵管理、人类掌舵。仅通过 /docs-governance 显式命令激活。
disable-model-invocation: true
---

# docs-governance

## 定位

本 Skill 是管理和维护项目治理体系的**一次性引导工具**。以 AGENTS.md 为根的渐进式披露文档体系是最终权威。Skill 帮助创建和维护这套体系，但不替代或凌驾于它。初始化完成后，Skill 可安全删除——项目的治理体系已独立运行。

设计哲学源自 [Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/)：工程师不再手写每行代码，而是设计约束环境、明确意图边界、构建反馈回路，让 AI 智能体可靠工作。部署的文档体系对应 HE 六大概念——AGENTS.md 是「地图而非手册」、docs/ 目录是「仓库即记录系统」、hooks + CI 是「机械化执行」、CLAUDE.md 渐进式路由是「智能体可读性」、archive/ + doc-maintenance.md 是「熵管理」、ai-collaboration.md 是「人类掌舵，智能体执行」。

## 激活条件

Skill 仅通过显式命令激活：用户输入 `/docs-governance`。

Skill 不在日常 AI 协作中自动介入。Skill 删除后，治理体系的维护由 AI 读取项目中的 `doc-maintenance.md` 自行处理。

## 边界规则

- Skill 仅在用户显式调用 `/docs-governance` 时工作
- 项目无 AGENTS.md → 进入脚手架模式
- 项目已有文档体系但不完整 → 进入融合模式
- 项目已有完整体系，用户要求增删改约束 → 进入维护模式
- 项目已有完整体系，用户要求检查完整性 → 进入诊断模式
- 所有操作前先分析项目现状，基于 [Q&A-TEMPLATE.md](Q&A-TEMPLATE.md) 适配提问
- 任何涉及已有配置的操作，使用脚本获取结构化 merge plan，用户确认后执行
- **不覆盖已有配置**，必须经用户确认

## 5 个模式

### 1. 脚手架

触发：项目无 AGENTS.md

1. 分析项目现状（读取文件结构、已有配置）
2. 按 [Q&A-TEMPLATE.md](Q&A-TEMPLATE.md) 连续提问（基于现状适配，不机械照搬）
3. 展示确认汇总
4. 用户确认后：调用 `scaffold.sh --dry-run` 预览变更 → 确认 → `scaffold.sh --apply` 复制启用的模板文档 + 安装联动的脚本资产 + 始终部署 `docs/scripts/` 维护脚本
5. 执行 `validate.sh` smoke test

### 2. 诊断

触发：已有项目，检查完整性

1. 优先执行 `audit.sh --json` 获取结构化诊断报告
2. 将报告中的 `description_nl` 和 `results` 以自然语言呈现给用户
3. 若 audit.sh 不可用，按 `doc-maintenance.md` 诊断清单手动逐项检查
4. 报告缺失/冲突，给出修复建议

### 3. 融合

触发：已有文档体系，需要合并

1. 诊断现有状态（调用 `audit.sh --json`）
2. 对每个已有配置，调用 `install-*.sh --check` 获取结构化 merge plan
3. 将 merge plan 中的 `description_nl` 以自然语言呈现给用户
4. 逐项询问：[1] 保留现有 [2] 替换 [3] 合并 [4] 跳过
5. 用户逐项确认后，调用 `install-*.sh --apply <merge|replace|skip>` 执行
6. `validate.sh` 验证

### 4. 维护

触发：用户要求增删改约束或更新文档

子功能：
- **删除约束**：调用相关 `install-*.sh --check` 获取影响范围 → 展示 → 确认 → 移除 → 更新 AGENTS.md 索引
- **修改约束**：调用 `diff-helper.sh --json` 获取变更描述 → 展示 → 确认 → 更新
- **完整性检查**：同诊断模式
- **更新项目文档**：按 `doc-maintenance.md` 流程 → 更新内容 → 同步索引

### 5. 生成

触发：需要特定文档或配置

根据项目特征和 `doc-maintenance.md` 中的 Q&A 决策参考，智能生成适配内容。

## 经验沉淀行为

每次 AI 协作会话中，如产生可复用的经验，主动建议沉淀到对应位置：

| 经验类型 | 沉淀位置 |
|---------|---------|
| 架构/技术决策 | `docs/decisions/` |
| 问题排障 | `docs/troubleshooting/` |
| 研究发现 | `docs/research/` |
| 约束变更 | `docs/practices/` + AGENTS.md |

经验沉淀行为同时写入 `ai-collaboration.md` 模板，确保 Skill 删除后 AI 仍能自主沉淀。

## 部署策略

- 仅部署用户选择启用的文档和资产
- 未启用的资产不复制到项目
- `docs/scripts/`（audit.sh、validate.sh、diff-helper.sh、check-consistency.sh）始终部署
- 后续需要新增约束时，重新安装 Skill 执行

## 结构化输出约定

本 Skill 所有脚本遵循统一的分工协议——脚本负责确定性分析，LLM 负责语义增强和用户交互：

| 脚本层职责 | LLM 层职责 |
|-----------|-----------|
| 检测已有配置状态 | 读取结构化报告 |
| 生成 diff 和行数统计 | 将 `description_nl` 以自然语言呈现给用户 |
| 输出结构化 JSON（含 `description_nl`） | 确认用户选择 |
| 执行写入操作（--apply 模式） | 调用脚本执行 |
| smoke test 验证 | 呈现验证结果 |

关键约定：
- 所有脚本 `--json` 模式输出纯 JSON 到 stdout，诊断日志到 stderr
- 每个 JSON 响应必须包含 `description_nl` 字段（自然语言描述，LLM 可直接使用）
- 退出码：0=成功/无变更，1=检测到冲突/失败，2=脚本自身错误
- LLM 不应自行解析原始 diff 或文件内容来替代脚本的结构化输出

## 辅助文件

Skill 目录中的其他文件按需加载：

- **[AGENTS.md](AGENTS.md)**：Skill 自身渐进式披露入口，路由到各模块。
- **[Q&A-TEMPLATE.md](Q&A-TEMPLATE.md)**：Q&A 参考模板，包含 16 项治理约束描述（含 release-please 可选资产）、联动规则、融合模式提问和兼容化处理流程。脚手架和融合模式时读取。
- **[templates/](templates/)**：文档模板（CLAUDE.md、AGENTS.md、docs/ 完整层级结构），部署到目标项目的 `docs/` 目录。
- **[assets/](assets/)**：脚本和配置资产（husky hooks、commitlint、GitHub workflows、ESLint、Prettier、lint-staged、gitignore），按用户选择部署到项目对应位置。
- **[scripts/](scripts/)**：Skill 内部初始化脚本（scaffold.sh + 7 个 install-*.sh），由各模式按需调用。
- **[tests/](tests/)**：Skill 自身测试（bats 单元测试 + fixture 项目）。
- **[docs/plan.md](docs/plan.md)**：Skill 设计计划和架构文档，仅供 Skill 维护者参考。
