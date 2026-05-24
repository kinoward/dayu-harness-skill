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

大禹治库 Skill 是管理和维护项目治理体系的**一次性部署工具**，不是治理体系本身。Skill 目录中的模板、脚本和资产只是部署来源；被部署到目标项目中的 AGENTS.md、docs/ 文档、hooks、CI 与维护脚本，才是 Harness Engineering 治理体系的实际载体。以 AGENTS.md 为根的渐进式披露文档体系是最终权威。初始化完成后，Skill 可安全删除——项目的治理体系已独立运行。流程结束时，Skill 必须结构化询问是否删除本次一次性 Skill 安装目录，默认选择删除，并展示该目录的绝对路径。

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
- 面向用户的运行时输出必须使用自然语言能力名，例如“项目入口索引和文档维护说明”“自动化版本发布流程”，不得展示 `core`、`git.commit-format`、`github.release-please` 等 capability key。维护者文档、`dayu.config.yaml`、manifest、CLI `--json` 和调试日志可以保留 key，但转述给用户时必须映射为自然语言名称。
- 初始化第一个阻塞问题必须是部署内容语言（中文 / English）。不得先询问项目编程语言、技术栈或项目类型；这些信息由 Skill 根据文件自动判断，空项目默认按 Node.js 治理工具链基线处理。
- 问答交互规则只约束 Skill 运行时，不写入目标项目部署产物。若宿主客户端暴露了可调用的原生交互机制（如选择器、确认对话或计划审批控件），必须优先使用；若当前客户端没有暴露可调用的结构化交互能力，则采用兼容降级：一次只提出一个阻塞问题，立即结束当前回复并等待用户输入，不得在同一轮继续运行命令、不得合并多个阻塞问题、不得假装已经进入交互控件
- 可选的 `github.repository-settings` 在用户选择启用、部署验证通过且本次流程明确进入远端同步 apply 后，才调用 GitHub API 同步 `allow_auto_merge=true` 与 `delete_branch_on_merge=true`；CLI dry-run、本地 apply、check 和 verify 都不修改远端。Issue/PR/TDD/发布能力仍以配置、策略文件、工作流和说明为主。
- 部署/融合前统一执行 `scripts/ensure-environment.sh <project-root> --check --capabilities "<resolved capability ids>"`；尚未确定可选能力时不传 `--capabilities`，脚本按默认必选能力检查。若返回 `needs_install`、`needs_initialization` 或 `needs_user_action`，先向用户展示安装/初始化建议并确认；若用户拒绝，当前流程终止
- Phase 2 起，`/dayu-harness` 的本地主执行路径是 TypeScript CLI：Skill 负责分析现状、提问和生成/维护 `dayu.config.yaml`；CLI 负责 `init`、`apply`、`merge`、`generate`、`repair`、`status`、`diagnose`、`validate` 的确定性执行。源码检出场景先在 Skill 根目录运行 `npm run build`，再用 `node dist/cli/main.js ...`；已发布包场景可用 `npx dayu-harness ...`。`scaffold.sh` 仅作为 legacy 兼容和远端 E2E 辅助入口，不作为本地部署、融合、维护的默认路径。
- 任何涉及已有配置的操作，按能力清单中的可管理项/联动组件逐项处理：installer-backed 组件（如 husky hook 片段、`.gitignore`）先走 manifest installer 的 `--check`；静态模板/资产文件组件（如 `commitlint.config.cjs`、ESLint/Prettier/lint-staged 配置文件、`.github/workflows`、ruleset JSON）优先用 CLI `merge --json` 输出融合预览，或用 `generate --json` 输出待写内容预览；若可提供现有文件与目标文件对，优先调用 `diff-helper.sh merge-plan <existing> <incoming>`；否则基于 CLI 预览结果做人工确认。只有当前 CLI 无法覆盖的 legacy 或远端 E2E 场景，才说明原因后调用 `scaffold.sh`
- **不覆盖已有配置**，必须经用户确认
- CLI `apply`、`init --apply`、`merge --apply` 或任何手工写入完成后，必须立即进入 `finalize` 收尾阶段。`finalize` 负责本地验证、精确 stage/commit、远端创建或同步、Issue/PR E2E、release-please 真实验证、测试产物清理和一次性 Skill 安装目录清理询问；不得把这些命令留作“后续建议”。只要已启用 GitHub 远端能力、rulesets、仓库设置或 release-please workflow permissions，就必须执行 `dayu-harness finalize --github-remote apply` 或等价的 `scripts/github-remote.sh --apply`；未执行远端 apply 时，报告必须是 `partial`/`needs_user_action`，不能汇报远端成功。
- 目标项目运行状态目录统一为 `.dayu-harness/`。`.dayu-harness/managed-paths.json` 是长期托管路径状态，必须纳入本次提交；`.dayu-harness/apply.lock`、`.dayu-harness/journal.jsonl` 和 `.dayu-harness/tmp/` 只用于临时锁、恢复和运行缓存，必须被忽略，不作为长期治理资产。

### 结构化提问约束（全流程）

以下阻塞场景必须以单问题块输出，一轮只问一个问题，且不得要求用户手输命令：

- 版本冲突（`package.json`/`package-lock.json`/`VERSION`/`CHANGELOG.md`/`.release-please-manifest.json` 版本不一致）：提示冲突类型并给出 `[1]` 回到 `0.1.0`、`[2]` 采用某个现有版本源、`[3]` 暂停本次流程三类选项。
- GitHub 远端创建：仅在用户选择开启时执行 `gh auth status`、`scripts/github-remote.sh --check/--apply`；若未登录或可见性冲突，先给出 `[1]` 重试登录、`[2]` 暂不创建远端、`[3]` 跳过 GitHub 相关能力。不得使用或推荐 `gh repo create --push`、手写 `git push origin main` 或 API 手工创建 `main` ref；空远端首次默认分支只能走 `github-remote.sh --apply` 的受控路径，由脚本带 `DAYU_HARNESS_ALLOW_DEFAULT_BRANCH_CREATION=1` 通过本地 pre-push。
- hooks/workflows merge：当 `.husky`、`.github/workflows` 已存在且 `manual_required` 时，必须提供 `[1] 保留现有`、`[2]` 合并策略、`[3]` 替换、`[4]` 跳过该项的选择。
- 已跟踪 `.claude` 或 `CLAUDE.md`：若仓库已跟踪本地 Agent 路由目录/文件，必须先确认 `[1]` 保留本地配置、`[2]` 使用 Skill 模板合并后继续、`[3]` 从 Git 索引移除但保留本地文件后继续、`[4]` 跳过该能力。
- 受保护分支：启用 `github.branch-protection` 且检测到既有保护策略时，必须先确认策略继承关系与合并策略（合并/替换/仅保留现有），不允许自动默认覆盖。
- 部署、融合、维护或生成操作完成后，必须执行 `finalize` 收尾，并按 [docs/completion-report-template.md](docs/completion-report-template.md) 用自然语言向用户汇报结果

## 5 个模式

### 1. 脚手架

触发：项目无 AGENTS.md

1. 若用户未提供部署语言，先通过交互门禁确认部署语言并等待回答；这必须是第一个问题。随后执行 `scripts/ensure-environment.sh <project-root> --check --capabilities "<resolved capability ids>"`，由脚本自动判断技术栈、Git/Node 治理工具链初始化需求和 `.gitignore` 模板（见 Q&A 前置问题；尚未确定可选能力时使用默认必选能力检查）
2. 分析项目现状（读取文件结构、已有配置）
3. 按 [Q&A-TEMPLATE.md](Q&A-TEMPLATE.md) 的交互门禁询问 GitHub、发布、代码工具等可选能力（默认治理与 Git 能力直接纳入部署）
4. 展示确认汇总
5. 用户确认后：用 CLI 预览和应用本地部署。缺少配置时先执行 `dayu-harness init --target <project-root> --locale <zh|en> --json` 预览，再执行 `dayu-harness init --target <project-root> --locale <zh|en> --apply --json`；已有配置时先更新 `dayu.config.yaml` 中的能力选择，再执行 `dayu-harness apply --target <project-root> --config <config-path> --dry-run --json` 预览，确认后执行 `dayu-harness apply --target <project-root> --config <config-path> --json`。如遇漂移，必须先说明影响并取得用户确认，才可追加 `--force`；只在用户明确要求清理托管孤儿文件时追加 `--prune-orphans`。
6. CLI 写入完成后必须立即调用 `finalize` 收尾。`finalize` 先执行 `validate`、`diagnose`、`status` 以及目标项目内的 `validate/audit/check-consistency` 检查，再基于 `.dayu-harness/managed-paths.json` 精确 stage 托管路径并创建提交；如用户已选择 GitHub 远端同步或启用远端能力，继续以 `dayu-harness finalize --github-remote apply` 完成远端创建/绑定、push 或初始化 PR、远端配置回读、Issue/PR E2E 和 release-please 真实验证。验证通过后必须清理测试 Issue、测试 PR、测试分支和一次性临时产物，不得把这些命令作为后续建议留给用户。

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
   - 无 installer 的组件（静态模板/资产文件）：先用 `dayu-harness merge --target <project-root> --config <config-path> --json` 获取融合预览，或用 `dayu-harness generate --target <project-root> --config <config-path> --json` 获取待写内容预览；若有源文件和目标文件对可用，再补充 `diff-helper.sh merge-plan <existing> <incoming>` 的结构化说明，再展示给用户
3. 将 merge plan 或差异说明中的 `description_nl` 以自然语言呈现给用户
4. 逐项双语询问：[1] 保留现有 / Keep existing [2] 替换 / Replace [3] 合并 / Merge [4] 跳过 / Skip
5. 用户逐项确认后，按组件类型执行：
   - installer-backed 组件：调用对应 installer `--apply <merge|replace|skip>`
   - 无 installer 组件：按用户确认方案，用 `dayu-harness merge --apply --strategy <keep|replace|skip>`、`dayu-harness apply` 或手工更新
6. 按「执行 finalize 收尾」流程检查融合结果，并使用完成报告模板向用户汇报

### 4. 维护

触发：用户要求增删改约束或更新文档

子功能：
- **删除约束**：按联动组件逐项处理：installer-backed 组件先调用相关 installer 的 `--check` 获取影响范围；无 installer 组件先用 `dayu-harness merge --json` 标注待删差异，或用 `dayu-harness generate --json` 预览调整后的托管内容（如有源文件与目标文件对可用，再调用 `diff-helper.sh merge-plan <existing> <incoming>`） → 展示 → 确认 → 移除 → 更新 AGENTS.md 索引
- **修改约束**：有现有/目标文件对时调用 `diff-helper.sh merge-plan <existing> <incoming>` 获取变更描述；无可用对时回退到 `dayu-harness merge --json` 或 `dayu-harness generate --json` 的人工审核输出 → 展示 → 确认 → 更新
- **完整性检查**：同诊断模式
- **更新项目文档**：按 `docs/harness/maintenance.md` 流程 → 更新内容 → 同步索引

### 5. 生成

触发：需要特定文档或配置

根据项目特征和 `docs/harness/maintenance.md` 中的 Q&A 决策参考，智能生成适配内容。

## 执行 finalize 收尾

Skill 完成任何写入类操作后，不能只告诉用户“已完成”。必须立即进入 `finalize` 收尾，先验证目标项目中的治理体系是否能正常使用，完成提交、远端同步和已启用远端能力的真实 E2E，再用自然语言收尾。`finalize` 是本次流程的一部分，不是可以交给用户稍后执行的建议。

`finalize` 优先使用目标项目内已部署的脚本：

1. `docs/harness/sensors/scripts/validate.sh --json <project-root>`：检查已启用的 hooks、配置和 workflow 是否可用。
2. `docs/harness/sensors/scripts/audit.sh --json <project-root>`：检查 `AGENTS.md`、`CLAUDE.md`、docs 索引和维护脚本是否完整。
3. `docs/harness/sensors/scripts/check-consistency.sh --json <project-root>`：检查文档链接、索引和孤儿文档。
4. `dayu-harness diagnose --target <project-root> --json`、`dayu-harness validate --target <project-root> --json` 和 `dayu-harness status --target <project-root> --json`：必须覆盖本次所有已部署能力的 manifest 文件存在性、漂移、执行位、依赖图和关键行为。对 `.gitignore`、commitlint CLI、Git commit hook、pre-commit lint-staged hook、pre-push 保护、Node linter/formatter CLI、PR/Issue body validators、TDD policy 和 release-please policy 等硬能力，若 CLI 或传感器报告没有直接覆盖，必须手动抽查对应命令或脚本。不能只测试 GitHub 相关能力。
5. 基于 `.dayu-harness/managed-paths.json` 精确 stage 托管路径和长期状态文件，创建初始化或维护提交。只 stage 托管路径、`dayu.config.yaml` 及必要的长期状态，不 stage 用户本地 Agent 配置、临时日志、锁文件或未托管改动。
6. 若本次确认了 GitHub 远端同步，或本次启用了包含远端动作的能力，必须完成远端创建/绑定、push 或初始化 PR，并回读 repo settings、workflow permissions、rulesets 与默认分支状态。`.github/rulesets/*.json` 只是本地 API payload，必须由 GitHub Rulesets API 写入并回读确认；workflow 文件存在、ruleset JSON 存在或语法检查通过都不能描述为远端规则已生效。远端领先、分叉或默认分支受保护时不得 force push，必须走初始化分支和 PR。

以上本地检查属于结构/配置/关键行为验证，不能把它们表述成 GitHub Actions 已经端到端生效。启用 GitHub Issue/PR 能力并完成远端同步后，还必须运行目标仓库 Issue -> PR E2E：创建测试 Issue，再基于该 Issue 创建测试分支和测试 PR，等待 `issue-lint.yml` 与 `pr-lint.yml` 成功；验证通过后关闭测试 PR、关闭测试 Issue 并删除测试分支。需要验证合并后自动关闭 Issue 时，使用 `tests/smoke/dayu-harness-profile.sh --profile remote-smoke` 的 disposable repo 流程。

启用 release-please 自动发布流程后，`finalize` 必须做真实 release 验证：在目标仓库或 disposable `remote-release` 仓库中验证 `docs:`/`chore:` 不触发发布、`feat:` 正向触发 release PR 或等价真实 release-please 路径。不能只做 YAML/Python 语法检查、策略文件存在性检查或 `workflow_dispatch`。

负向测试只能证明门禁会拦截错误输入，不能替代合规路径通过。若只观察到失败的 PR Lint、Issue Lint 或 release-please workflow，不得汇报为远端 E2E 成功；必须同时完成合规 Issue/PR/release 正向验证。

如果脚本不存在或暂时不可执行，按目标项目中的 `docs/harness/maintenance.md` 手动检查关键路径。

验证后处理规则：

- 检查通过：按 [docs/completion-report-template.md](docs/completion-report-template.md) 汇报已启用能力、已确认事项和未启用事项。
- 检查发现可确定修复的问题：先修复，再重新运行检查。
- 检查发现需要用户取舍的问题：说明影响，按交互门禁获取用户选择，不输出大段原始日志。
- `partial`、`failed`、`needs_user_action`、`skipped` 不能被改写成成功；必须说明对应影响。未启用的能力出现 skip 或可选缺失时，不作为失败汇报，只说明这次没有安装相关内容。
- 面向用户的汇报只使用自然语言能力名；capability key 仅可出现在维护者日志、JSON、配置或需要用户复制执行的明确命令中。
- 完成报告后，必须结构化询问是否删除一次性 Skill 安装目录。默认选项为删除，并展示绝对路径；用户选择删除时，只删除该 Skill 安装目录，不删除目标项目中的治理体系。

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

- 必选默认能力始终部署：项目入口索引、文档维护说明、Git 提交/.gitignore 约束、AI 执行/记忆规则、ADR、排障、研究、项目上下文和归档入口
- `--enable` 只表示在必选默认集上追加可选能力；GitHub、发布自动化、Node.js 工具等能力未选择时不复制到项目
- 未启用的可选资产不复制到项目
- `docs/harness/sensors/scripts/`（audit.sh、validate.sh、diff-helper.sh、check-consistency.sh）始终部署
- 后续需要新增约束时，重新安装 Skill 执行
- `.dayu-harness/managed-paths.json` 是长期状态文件，用来记录托管路径和后续 orphan 判断，必须随治理体系提交；`.dayu-harness/apply.lock`、`.dayu-harness/journal.jsonl` 和 `.dayu-harness/tmp/` 是临时/恢复用运行产物，必须忽略。

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
- PR body、Issue body、commit message 等固定格式内容必须优先由 `docs/harness/sensors/scripts/dayu-format.mjs`、GitHub CLI `--body-file`、Commitizen/cz-git、commitlint、release-please、changesets 或项目内同类确定性工具生成/校验；LLM 只负责结构化输入字段和结果解释。
- 面向用户展示结构化 JSON 的结果时，必须把 capability key 映射为 `displayName` 或本地化自然语言名称；不要把 key 当作用户可见名称。

## 能力清单约定

- `capabilities/*.json` 是治理能力的单一事实源，定义 `id`、依赖、模板文件、资产文件、installer、安全策略和 acceptance criteria。Phase 2 已将当前 20 个 manifest 全部迁移到 v2 字段：`schemaVersion`、`kind`、`deployment_deps`、`conceptual_deps`、`i18n` 和 `rse`；旧 `dependencies` 字段必须继续保留，并与 `deployment_deps` 保持一致，供 legacy `scaffold.sh` 兼容使用。`deployment_deps` 阻塞 CLI 部署，`conceptual_deps` 只影响说明和交互排序。`src/cli/` 是当前本地确定性执行层，公开 `init`、`apply`、`merge`、`generate`、`repair`、`status`、`diagnose`、`validate`。
- `default=true` 的 manifest 是无须用户选择的必选部署集，对应项目入口索引、Git 提交/.gitignore 约束、AI 执行/记忆规则和知识库/项目上下文目录。通用质量实践、GitHub CI、release-please、Node.js 工具和发布/分支保护类能力仍按 capability 显式启用。
- Q&A、dry-run plan、安装清单和测试断言应从 manifest 字段生成或校验，避免手工维护重复计数。

## 辅助文件

Skill 目录中的其他文件按需加载：

- **[AGENTS.md](AGENTS.md)**：Skill 自身渐进式披露入口，路由到各模块。
- **[Q&A-TEMPLATE.md](Q&A-TEMPLATE.md)**：Q&A 参考模板，提问内容以 `capabilities/*.json` 为准，包含融合模式提问和兼容化处理流程。脚手架和融合模式时读取。
- **[docs/completion-report-template.md](docs/completion-report-template.md)**：Skill 执行完成后的验证流程和自然语言收尾模板。部署、融合、维护或生成操作完成后读取。
- **[references/agent-compatibility.md](references/agent-compatibility.md)**：Claude、Codex 和通用 Agent Skills 客户端的兼容说明。需要安装、分发或调整触发策略时读取。
- **[capabilities/](capabilities/)**：治理能力 manifest，作为脚手架、Q&A、部署清单、依赖关系和验收标准的单一事实源。
- **[src/schemas/](src/schemas/)**：TypeScript/Zod schema，定义 manifest v2、`dayu.config.yaml`、locale catalog 和路径安全校验。
- **[src/architecture/](src/architecture/)**：TypeScript 架构契约，定义 CLI 命令树、部署/概念依赖图和 Frontend/Tool/Product 三层边界。
- **[src/cli/](src/cli/)**：Phase 2 TypeScript CLI 执行层，公开提供 init/apply/merge/generate/repair/status/diagnose/validate。
- **[locales/](locales/)**：key-based i18n 文案 catalog，覆盖当前全部 manifest v2 能力的中英文本契约。
- **[templates/](templates/)**：文档模板（CLAUDE.md、AGENTS.md、docs/ 完整层级结构），部署到目标项目的 `docs/` 目录。
- **[assets/](assets/)**：脚本和配置资产（husky hooks、commitlint、GitHub workflows、ESLint、Prettier、lint-staged、gitignore），默认 Git 资产和用户选择的可选资产会部署到项目对应位置。
- **[scripts/](scripts/)**：Skill 内部辅助脚本（`ensure-environment.sh`、`github-remote.sh`、`install-husky.sh`、`install-gitignore.sh`，以及 legacy `scaffold.sh`）。`ensure-environment.sh` 负责环境依赖完整性与初始化确认；本地部署、融合、生成、修复、诊断和验证优先调用 `src/cli/`。
- **[package.json](package.json)** 与 **[tsconfig.json](tsconfig.json)**：本地 TypeScript schema 验证工具链入口。
- **[tests/](tests/)**：Skill 自身测试（维护者可选 bats 单元测试 + fixture 项目）；非运行时依赖，不会部署到目标项目。
- **[docs/phase1b-schema.md](docs/phase1b-schema.md)**：Phase 1b schema、manifest v2、`dayu.config.yaml`、locale catalog 和路径安全契约。
- **[docs/phase1c-architecture.md](docs/phase1c-architecture.md)**：Phase 1c CLI 命令树、DAG 与三层分离架构契约，仅供 Skill 维护者和 Phase 1d 实现参考。
- **[docs/phase1d-cli.md](docs/phase1d-cli.md)**：Phase 1d TypeScript CLI 垂直切片命令语义、阶段边界和验证方式。
- **[docs/phase1e-cli-scope.md](docs/phase1e-cli-scope.md)**：Phase 1e CLI 公开范围收口、默认 dry-run、`apply --only` 和原子写入契约。
- **[docs/phase1-progress.md](docs/phase1-progress.md)**：Phase 1b-1e 当前进度、维护者计划、验证基线和 QA 经验沉淀。
- **[docs/scaffold-sh-spike.md](docs/scaffold-sh-spike.md)**：`scaffold.sh` 内部逻辑 spike，记录 TypeScript port 前需要理解的历史 Bash 行为和风险。
- **[docs/plan.md](docs/plan.md)**：Skill 设计计划和架构文档，仅供 Skill 维护者参考。
