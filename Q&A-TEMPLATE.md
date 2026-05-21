# Q&A 参考模板

> 本模板只定义提问方式和融合策略。治理能力列表、依赖、模板文件、资产文件、验收标准以 `capabilities/*.json` 为单一事实源；新增或删除治理能力时优先更新 manifest，再按 manifest 生成或校验本模板的提问内容。

## 适配规则

- 项目已有 `commitlint.config.cjs` → 不直接问「是否启用提交校验」，而是确认「检测到已有 commitlint，是否保留/增强/跳过」
- 项目已有 `docs/` 但结构不同 → 进入融合模式，逐项确认
- 项目已有 `.husky/`、`.github/workflows/`、ESLint/Prettier/lint-staged 等配置 → 先按能力清单的联动组件逐项判断：有 manifest installer 的组件（如 husky snippet、`.gitignore`）先调用该 `--check` 获取结构化 plan；静态模板/资产文件组件（如 `commitlint.config.cjs`、ESLint/Prettier/lint-staged 配置、`.github/workflows/*.yml`、ruleset JSON）先用 `scaffold.sh --dry-run` 出对比预览；若有现有文件与目标文件对可用，再补充 `diff-helper.sh merge-plan <existing> <incoming>`；否则按 `scaffold.sh --dry-run` 输出人工审阅确认
- `replace` 只能由用户显式选择；`merge` 只表示脚本能证明安全的确定性合并，否则返回 `manual_required`

## 双语提问总规则

- 使用 Skill 进行初始化、融合、维护或诊断时，所有面向用户的提问、确认语、选项、继续/取消/跳过等选择项都必须中英双语展示。
- 中文是源语言，英文是辅助翻译；展示顺序固定为中文在前、英文在后，避免中文用户丢失作者原意，也避免英文用户看不懂选项。
- 选项格式固定为 `[1] 中文选项 / English option`；默认项必须写明 `（默认，推荐）/ (default, recommended)`。
- 问题正文使用两行或同段双语均可，但不能只显示中文，也不能只显示英文。
- `description_nl`、dry-run、merge plan 或检查报告中的关键结论如要转成问题，也必须补充英文说明后再让用户选择。
- 本节只约束 Skill 运行时问答，不属于部署到目标项目的治理内容。
- 问答必须优先使用当前宿主已经暴露且可调用的原生交互能力（选择器、确认对话、计划审批控件或等价交互机制），不能默认把连续问题写成普通说明文本。
- 如果宿主客户端没有暴露可调用的结构化交互能力，采用兼容降级：一次只提出一个阻塞问题，随后立即结束当前回复并等待用户输入；不得在同一轮继续执行命令、不得把语言选择、环境初始化、能力选择或 merge 策略合并成一个长问题，也不得声称已经打开原生交互控件。
- 若用户已经在当前请求中明确给出完整预设（例如部署语言、初始化许可、可选能力启用/跳过策略），可跳过对应问题，但必须在确认汇总中列明这些预设来源。
- This section governs only Skill runtime Q&A, not deployed target-project governance content. Use native host interaction only when it is explicitly exposed and callable; otherwise ask exactly one blocking question per turn, stop immediately, and wait for the user's answer before running more commands.

## 前置问题

### 部署语言

进入能力问答前，先询问部署到目标项目的文档语言。除非用户已经明确给出部署语言，否则本问题是第一个阻塞交互点；提出后必须等待回答，不得同时执行环境检查。

```markdown
请选择部署到目标项目的文档语言。推荐使用中文，因为中文是本 Skill 的源语言，更贴近作者意图。
Please choose the documentation language to deploy to the target project. Chinese is recommended because it is the source language of this Skill and is closest to the author's intent.

[1] 中文（默认，推荐）/ Chinese (default, recommended)
[2] 英文 / English
```

用户选择中文或未明确选择时，后续 `scaffold.sh` 使用默认 `--locale zh-CN`；用户明确选择英文时，执行 `scaffold.sh --locale en`。无论选择哪种语言，写入目标项目的路径保持不变，只改变部署内容语言。

### 本地初始化与项目基线

部署语言确认后，先完成本地初始化与项目基线检查：
After confirming the documentation language, complete local initialization and baseline checks first:

```bash
scripts/ensure-environment.sh <project-root> --check
# 或在可选能力已确定后：
scripts/ensure-environment.sh <project-root> --check --capabilities "<resolved capability ids>"
```

- `status == "ok"`：继续问题收集与能力选配。
- `status == "needs_install"`、`status == "needs_initialization"` 或 `status == "needs_user_action"`：展示缺失依赖与 `items`，提示用户选择「安装/初始化/登录」或「终止流程」；提出该选择后必须停止并等待用户回答。
- 未显式传入 `--capabilities` 时，环境脚本按默认必选能力检查；可选能力确定后，必须用完整 resolved capability ids 重新检查或通过 `scaffold.sh --dry-run` 查看内嵌的 `environment` 结果。
- 全新 Git 仓库必须使用 `git init -b main`；老 Git 版本 fallback 为 `git init && git branch -M main`。已有仓库保留当前默认分支，并把该分支作为后续 GitHub workflow、ruleset 和文档命令的默认分支。
- New Git repositories must use `git init -b main`; older Git falls back to `git init && git branch -M main`. Existing repositories keep their current default branch, and that branch becomes the default for later GitHub workflows, rulesets, and documented commands.
- 初始化时若缺少 `README.md`、`VERSION` 或 `CHANGELOG.md`，apply 阶段会补齐。空项目初始版本为 `0.1.0`；已有 `package.json.version` 时以现有版本为准创建 `VERSION` 和起始 CHANGELOG。
- During initialization, missing `README.md`, `VERSION`, or `CHANGELOG.md` will be created during apply. Empty projects start at `0.1.0`; if `package.json.version` already exists, that version is used for `VERSION` and the initial CHANGELOG entry.
- 需要 Node 生态时，提示执行 `npm init -y`，并说明 `package.json` 不能通过手写模板文件替代初始化；若 Skill 新建 package 或 package 缺 version，则写入 `0.1.0`。
- 说明：Node/npm/npx、`package.json`、`devDependencies` 仅用于安装/运行治理工具链（如 husky、commitlint、lint-staged），不是目标项目必须是 Node.js 应用的前提。
- 如果用户拒绝初始化，流程必须立刻终止，不应继续执行 `scaffold` 或能力关联 installer 脚本。

需要用户确认环境处理时，选项必须双语：

```markdown
检测到目标项目需要先完成环境准备。
The target project needs environment preparation first.

[1] 执行建议的安装/初始化/登录步骤 / Run the suggested install, initialization, or login steps
[2] 暂停流程 / Pause this flow
[3] 取消本次部署 / Cancel this deployment
```

### GitHub remote / push

本地初始化确认后，再询问是否开启 GitHub 远端托管。用户选择不开启时，GitHub 能力保持未启用，仅继续本地治理能力。
After local initialization is confirmed, ask whether to enable GitHub remote hosting. If the user declines, keep GitHub capabilities disabled and continue with local governance only.

```markdown
是否现在开启 GitHub 远端托管并推送当前仓库？
Do you want to enable GitHub remote hosting and push the current repository now?

[1] 开启 / Enable
[2] 跳过 / Skip
[3] 稍后手动 / Configure later manually
```

用户选择开启后，流程固定为：
After the user chooses Enable, the flow is fixed:

1. 执行 `gh auth status`；若未登录，提示用户执行 `gh auth login`，并允许用户中断，此时结束 GitHub 能力开启流程。
2. 询问仓库可见性：

```markdown
请选择 GitHub 仓库可见性。
Please choose the GitHub repository visibility.

[1] 私有仓库（默认，推荐）/ Private repository (default, recommended)
[2] 公开仓库 / Public repository
```

3. 运行 `scripts/github-remote.sh <project-root> --check` 解析可连接账户、origin 与 `owner/repo`。
4. 用户确认仓库名与可见性后，运行 `scripts/github-remote.sh <project-root> --apply` 创建或绑定远端，并执行 `git push -u origin <default-branch>`。
5. 推送成功后，再询问 GitHub/Git 相关能力。启用后，`scaffold.sh --apply --github-remote apply` 会应用 repo settings、rulesets，并用 `scripts/github-remote.sh <project-root> --verify` 回读远端状态。

默认治理能力不再作为「是否启用」问题出现。初始化时必须纳入：

- `core`
- `git.commit-format`
- `project.gitignore`
- `ai.execution`
- `ai.memory`
- `knowledge.adr`
- `knowledge.troubleshooting`
- `knowledge.research`
- `project.context`
- `knowledge.archive`

Git 相关能力默认启用；如果目标目录尚未初始化 Git，先说明 Git 约束已经纳入部署，但 hook 需要项目完成 Git/Husky 接入后才会实际触发。GitHub remote/push 完成后，再询问 GitHub/GitHub Rulesets、release、quality/TDD 等可选能力。

可选能力每项固定使用 3 个双语选项：[1] 启用 / Enable [2] 跳过 / Skip [3] 稍后手动 / Configure later manually。某些能力仍可附带 `自定义需求 / Custom request` 分支，但不作为默认选项。

```markdown
Q: 是否使用 GitHub 远程托管？
Q: Do you use GitHub as the remote hosting platform?
   选项 / Options: [1] 是 / Yes [2] 否 / No [3] 其他托管平台（请描述）/ Other hosting platform (please describe)

Q: 是否需要 Node.js 的 ESLint / Prettier / lint-staged 自动拦截？
Q: Do you need automatic Node.js ESLint / Prettier / lint-staged checks?
   选项 / Options: [1] 启用 / Enable [2] 跳过 / Skip [3] 自定义工具链 / Custom toolchain
```

## 专项能力提问示例（覆盖 /dayu-harness 关键能力）

- `github.repository-settings`：仓库设置能力在用户选择启用后，只会在用户明确进入 GitHub remote apply 流程时同步远端 GitHub 仓库设置。请明确说明这一步需要 GitHub CLI 登录和仓库 administration 权限。

```markdown
是否立即启用 GitHub 仓库 PR 设置（PR 自动合并、合并后删除分支）？
Do you want to enable GitHub repository PR settings now (auto-merge and delete branch on merge)?

选择启用后，只有在用户明确选择 `--github-remote apply` 时，`scaffold.sh --apply` 才会委托 `scripts/github-remote.sh` 调用 GitHub API 设置 `allow_auto_merge=true` 与 `delete_branch_on_merge=true`；`auto`、`check`、`verify`、`skip` 不会隐式写入远端。
After you choose Enable, `scaffold.sh --apply` delegates the GitHub API write to `scripts/github-remote.sh` only when the user explicitly chooses `--github-remote apply`; `auto`, `check`, `verify`, and `skip` do not write remote settings implicitly.

执行前必须已通过 `gh auth status`，且当前账号具备目标仓库 administration 权限。
Before applying, `gh auth status` must pass and the current account must have administration permission on the target repository.

选项 / Options:
[1] 启用 / Enable
[2] 跳过 / Skip
[3] 稍后手动 / Configure later manually
```

- `github.pr`：PR 质量治理只关注结构、签名、Troubleshooting 索引与 issue closing 位置；不做语言约束。

```markdown
是否启用 PR 协作治理（结构化 PR body、提交签名、review 检查与 issue closing 位置）？
Do you want PR collaboration governance (structured PR body, commit/trailer checks, review checks, and issue-closing location)?

说明：该能力不限制语言，只检查模板结构、签名、troubleshooting 索引、Issue 关闭位置。不会做 PR 全文语言校验。
Note: This capability does not enforce language. It checks structure, signatures, troubleshooting index linkage, and issue-closing position only.

选项 / Options:
[1] 启用 / Enable
[2] 跳过 / Skip
[3] 稍后手动 / Configure later manually
```

- `github.issue`：Issues 工作流按 `Depends on: #N` 维护前后置序；不打标签、不评论、不过滤语言。

```markdown
是否启用 Issue workflow（包含依赖关系校验）？
Do you want to enable Issue workflow validation (including dependency ordering)?

`Depends on: #N` 只用于人工与自动化判断 Issue 处理顺序，不作为 issue 描述语言规范。
`Depends on: #N` is only used for humans and automation to determine issue dependency order, not as a language rule.

该能力不自动打标签，不自动发布评论，且不做正文语言检查。
This capability does not add labels, does not post comments, and does not enforce body language constraints.

选项 / Options:
[1] 启用 / Enable
[2] 跳过 / Skip
[3] 稍后手动 / Configure later manually
```

- `quality.tdd`：TDD gate 使用策略文件定义路径；未配置路径不应阻断。

```markdown
是否启用 PR TDD Gate（按策略文件判定测试路径）？
Do you want to enable PR TDD gate checks driven by a policy file?

TDD 策略只会在配置了检查路径时执行；未配置路径则不拦截。
TDD checks only run on configured paths; if no paths are configured, no blocking is enforced.

选项 / Options:
[1] 启用 / Enable
[2] 跳过 / Skip
[3] 稍后手动 / Configure later manually
```

## 必选治理能力清单

以下能力不询问是否启用，只在 dry-run 或已有配置冲突时展示影响范围与 merge plan。

以下清单应从 manifest 字段生成或校验：`id`、`description_nl`、`dependencies`、`requires`、`acceptance`、`suggested_when`。

| capability id | 提问重点（价值） | 补充说明（技术实现） | 依赖/提示 |
|---|---|---|---|
| `git.commit-format` | 每次提交必须可追溯、可自动审查，减少后续 review 与回溯成本。 | 采用 commitlint + commit-msg hook snippet；如检测到已有 hook 会走逐文件确认与 merge plan。 | Git 项目；已有 hook 逐文件确认 |
| `project.gitignore` | 仓库必须有基础忽略规则，避免把构建产物、依赖目录或本地缓存纳入版本控制。 | 按 universal / Node.js / Python 模板检测并 merge。 | Git 项目；已有 `.gitignore` 走 merge plan |
| `ai.execution` | AI 执行方式、自动重试和汇报规则必须沉淀到项目文档中。 | 部署 AI 执行实践文档。 | 默认启用 |
| `ai.memory` | 项目长期知识/经验的边界和沉淀规则必须写入仓库。 | 部署 AI 记忆边界文档，并将 `AGENTS.md` 与 `docs/` 作为长期知识/经验锚点。 | 默认启用 |
| `knowledge.adr` | 必须有稳定的项目技术决策记录位点，避免关键架构讨论只留在会话里。 | 部署 ADR 目录与模板，作为项目知识/经验的一部分。 | 默认启用 |
| `knowledge.troubleshooting` | 排障经验必须可复用、可检索。 | 部署排障目录与入口说明，作为项目知识/经验的一部分。 | 默认启用 |
| `knowledge.research` | 研究结论必须可版本化沉淀，避免重复探索。 | 部署版本化研究目录，作为项目知识/经验的一部分。 | 默认启用 |
| `project.context` | 必须搭好产品规格与项目上下文文档区，避免需求与实现反复漂移。 | 部署项目内容骨架（产品规格入口）和 `project-status.md` 状态快照。 | 默认启用 |
| `knowledge.archive` | 必须有统一归档入口，减少当前上下文被历史信息淹没。 | 部署历史档案区与索引，存放过时的项目知识、项目内容或治理资料。 | 默认启用 |

## 可选治理能力提问清单

| capability id | 提问重点（价值） | 补充说明（技术实现） | 依赖/提示 |
|---|---|---|---|
| `github.repository-settings` | 是否立即启用 GitHub 仓库 PR 设置（自动合并、合并后删除分支）？<br>Do you want to enable GitHub repository PR settings now (auto-merge and delete branch on merge)? | 部署仓库设置策略模板；只有 `--github-remote apply` 会委托 `scripts/github-remote.sh` 写入 `allow_auto_merge=true` 与 `delete_branch_on_merge=true`，dry-run 和 skip 只预览/跳过。 | GitHub 项目；需要 `gh auth status` 通过和仓库 administration 权限 |
| `github.pr` | 是否希望 PR 在创建或更新时就具备固定结构，减少低质量变更和协作噪音？<br>Do you want PRs to have a fixed structure when created or updated, reducing low-quality changes and collaboration noise? | 通过 GitHub 工作流实现 PR body 结构、signature、troubleshooting index 与 issue closing 位置校验；不限制提交/正文语言。 | GitHub 项目 |
| `github.issue` | 是否需要 issue 依赖检查，支持 `Depends on: #N` 的顺序组织？<br>Do you need issue dependency checking with `Depends on: #N` ordering support? | 部署 issue lint workflow 与脚本。仅校验依赖顺序标记，不打标签、不评论、不做语言检查。 | GitHub 项目 |
| `github.branch-protection` | 是否需要把分支保护前置为默认约束，降低误推风险？<br>Do you want branch protection to become a default constraint to reduce accidental pushes? | 通过实际默认分支 ruleset 与本地 pre-push branch snippet 实现；新仓库默认 `main`，已有仓库保留当前默认分支。 | GitHub 项目 |
| `release.versioning` | 是否需要统一版本号和 release tag 规则，降低误发风险？<br>Do you need unified version and release tag rules to reduce release mistakes? | 通过版本规约、tag ruleset 与本地 pre-push tag snippet 实现。 | 有发布流程的项目 |
| `quality.practices` | 是否希望建立通用开发纪律和测试策略？<br>Do you want general development discipline and testing strategy? | 部署 dev hygiene 与 testing strategy 文档，不安装 Node.js 工具。 | 含代码项目 |
| `quality.node-tooling` | 是否希望在提交前自动拦截常见 Node.js 代码质量与格式问题？<br>Do you want common Node.js quality and formatting issues blocked before commit? | 通过 ESLint、Prettier、lint-staged 和 pre-commit hook snippet 实现。 | Node.js 项目；复杂配置默认 `manual_required` |
| `quality.tdd` | 是否启用可配置的 PR TDD 门禁策略（基于路径/触发事件）？<br>Do you want configurable PR TDD gate policy (path/event based)? | 部署 TDD 策略检查脚本。未配置检查路径时不阻断。 | 启用时需在仓库确认策略文件 |
| `github.release-please` | 是否希望发版过程可复用、可追踪并减少手工版本与发布过程出错？<br>Do you want reusable and traceable releases with fewer manual versioning and publishing mistakes? | 通过 `release-please` guide、workflow、策略文件和校验器联动：`docs/harness/guides/release-please.md`、`.github/workflows/release-please.yml`、`release-please-config.json`、`.release-please-manifest.json`、`.github/release-please-policy.json`、`.github/scripts/release_please_policy.py`。<br>Deploy `github.release-please` via linked deliverables: guide + workflow + config + manifest + policy + checker script; release filter policy is managed in the policy file. | 仅在 GitHub + `git.commit-format` + `github.pr` + `github.repository-settings` + `release.versioning` 后建议；不自动启用 |

项目状态快照（`docs/product-specs/project-status.md`）为 `project.context` 默认能力的一部分，不另外提问；在每次部署完成后可由用户/AI 补充。
Project status snapshot (`docs/product-specs/project-status.md`) is part of default `project.context` and does not require a separate question; it can be filled by users or AI after completion.

## 确认汇总

提问完成后，展示汇总：

```markdown
## 确认汇总 / Confirmation Summary

### 启用的治理能力 / Enabled Governance Capabilities
- 默认必选 / Required defaults → core、Git 提交/.gitignore、AI 执行/记忆、ADR、排障、研究、项目上下文、归档
- github.pr → 用户选择启用 PR 协作检查与交付结构约束 / The user chose to enable PR collaboration checks and delivery structure constraints

### 需要确认策略的已有文件 / Existing Files Requiring Strategy Confirmation
- .husky/commit-msg → manual_required
- .github/workflows/pr-lint.yml → manual_required

### 跳过的治理能力 / Skipped Governance Capabilities
- quality.node-tooling（用户选择跳过 / user chose to skip）

[1] 确认 dry-run / Confirm dry-run
[2] 调整选择 / Adjust choices
[3] 取消 / Cancel
```

## 融合模式额外提问

检测到已有配置时，对每个已有配置询问：

```markdown
检测到你的项目已有 `.husky/commit-msg`。
Existing `.husky/commit-msg` was detected in your project.

Merge plan:
- status: manual_required
- recommendation: manual_required
- reason: shell hook 已存在，脚本无法证明安全合并
- reason: the shell hook already exists, and the script cannot prove a safe merge

请选择 / Please choose:
[1] 保留现有配置 / Keep the existing configuration
[2] 替换为大禹治库 Skill 提供的治理模板 / Replace with the governance template provided by Dayu Harness Skill
[3] 手动合并后继续 / Continue after manual merge
[4] 跳过此项 / Skip this item
```

## 执行规则

1. `scripts/ensure-environment.sh <project-root> --check --capabilities "<local/default capability ids>"`：先处理本地工具、Git 初始化、Node 初始化和 README/VERSION/CHANGELOG 基线；若为 `needs_install`、`needs_initialization` 或 `needs_user_action`，先说明可执行动作并等待用户确认；用户若拒绝则终止流程。
2. 用户选择 GitHub remote/push 后，先运行 `gh auth status`；未登录则辅助用户执行 `gh auth login`，用户可中断并跳过 GitHub 能力。
3. 登录可用后询问 `私有仓库 / Private` 或 `公开仓库 / Public`，再运行 `scripts/github-remote.sh <project-root> --check` 和 `--apply` 创建/绑定远端并 `git push -u origin <default-branch>`。
4. 远端推送完成后，再询问 GitHub/GitHub Rulesets、release、quality/TDD 等可选能力；`scaffold.sh --dry-run --enable <optional ids>` 先输出 JSON plan，脚本会自动包含 `default=true` 的必选能力，并展示 `default_branch`、`project_baseline`、`github_remote`、`remote_validation` 与 `remote_actions`。
5. 用户确认可选治理能力和已有配置策略后，才执行 `scaffold.sh --apply --enable <optional ids> --github-remote apply`；clean installer 会自动使用 `merge`，已有配置或冲突场景需补充 `--strategy <merge|replace|skip>`，具体可用策略以 capability manifest 为准。
6. 有 installer-backed 的组件在执行前先用 `--check` 获取结构化 merge plan，不写 tracked files；无 installer 的组件改用 `scaffold.sh --dry-run` 与 diff-helper/manual review 产出对比描述。
7. 复杂 YAML/JS/CJS/workflow/config 文件默认 `manual_required`。
8. 应用后执行 `docs/harness/sensors/scripts/validate.sh --json`；需要结构一致性时执行 `docs/harness/sensors/scripts/check-consistency.sh --json`；GitHub 能力启用时再执行 `scripts/github-remote.sh <project-root> --verify`。
9. 部署后测试按 profile 选择：`local-fast` 只跑本地生成/校验，`remote-smoke` 使用 disposable GitHub repo 测 Issue -> PR，`remote-release` 只在显式开启时验证 release-please；不得用 `workflow_dispatch` 作为远端成功标准。
10. 部署、融合或维护完成后，按 [docs/completion-report-template.md](docs/completion-report-template.md) 生成自然语言完成报告，向用户说明已启用能力、检查结果、未启用内容和剩余注意事项。
