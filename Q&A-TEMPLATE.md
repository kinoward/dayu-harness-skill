# Q&A 参考模板

> 本模板只定义提问方式和融合策略。治理能力列表、依赖、模板文件、资产文件、验收标准以 `capabilities/*.json` 为单一事实源；新增或删除治理能力时优先更新 manifest，再按 manifest 生成或校验本模板的提问内容。

## 适配规则

- 项目已有 `commitlint.config.cjs` → 不直接问「是否启用提交校验」，而是确认「检测到已有 commitlint，是否保留/增强/跳过」
- 项目已有 `docs/` 但结构不同 → 进入融合模式，逐项确认
- 项目已有 `.husky/`、`.github/workflows/`、ESLint/Prettier/lint-staged 等配置 → 先按能力清单的联动组件逐项判断：有 manifest installer 的组件（如 husky snippet、`.gitignore`）先调用该 `--check` 获取结构化 plan；静态模板/资产文件组件（如 `commitlint.config.cjs`、ESLint/Prettier/lint-staged 配置、`.github/workflows/*.yml`、ruleset JSON）先用 `scaffold.sh --dry-run` 出对比预览；若有现有文件与目标文件对可用，再补充 `diff-helper.sh merge-plan <existing> <incoming>`；否则按 `scaffold.sh --dry-run` 输出人工审阅确认
- `replace` 只能由用户显式选择；`merge` 只表示脚本能证明安全的确定性合并，否则返回 `manual_required`

## 前置问题

### 环境前置检查

进入能力问答前，先执行：

```bash
scripts/ensure-environment.sh <project-root> --check
# 或在可选能力已确定后：
scripts/ensure-environment.sh <project-root> --check --capabilities "<resolved capability ids>"
```

- `status == "ok"`：继续问题收集与能力选配。
- `status == "needs_install"`、`status == "needs_initialization"` 或 `status == "needs_user_action"`：展示缺失依赖与 `items`，提示用户选择「安装/初始化/登录」或「终止流程」。
- 未显式传入 `--capabilities` 时，环境脚本按默认必选能力检查；可选能力确定后，必须用完整 resolved capability ids 重新检查或通过 `scaffold.sh --dry-run` 查看内嵌的 `environment` 结果。
- 默认 Git 约束缺失时提示执行 `git init`。
- 需要 Node 生态时，提示执行 `npm init -y`，并说明 `package.json` 不能通过手写模板文件替代初始化。
- 说明：Node/npm/npx、`package.json`、`devDependencies` 仅用于安装/运行治理工具链（如 husky、commitlint、lint-staged），不是目标项目必须是 Node.js 应用的前提。
- 如果用户拒绝初始化，流程必须立刻终止，不应继续执行 `scaffold` 或能力关联 installer 脚本。

默认治理能力不再作为「是否启用」问题出现。初始化时必须纳入：

- `core`
- `git.commit-format`
- `repo.language`
- `project.gitignore`
- `ai.execution`
- `ai.memory`
- `knowledge.adr`
- `knowledge.troubleshooting`
- `knowledge.research`
- `project.context`
- `knowledge.archive`

Git 相关能力默认启用；如果目标目录尚未初始化 Git，先说明 Git 约束已经纳入部署，但 hook 需要项目完成 Git/Husky 接入后才会实际触发。只有 GitHub、发布自动化、Node.js 工具等可选能力需要询问。

可选能力每项 3 选项：[1] 启用 [2] 跳过 [3] 自定义需求。

```
Q: 是否使用 GitHub 远程托管？
   选项：[1] 是 [2] 否 [3] 其他托管平台（请描述）

Q: 是否需要 Node.js 的 ESLint / Prettier / lint-staged 自动拦截？
   选项：[1] 启用 [2] 跳过 [3] 自定义工具链
```

## 必选治理能力清单

以下能力不询问是否启用，只在 dry-run 或已有配置冲突时展示影响范围与 merge plan。

以下清单应从 manifest 字段生成或校验：`id`、`description_nl`、`dependencies`、`requires`、`acceptance`、`suggested_when`。

| capability id | 提问重点（价值） | 补充说明（技术实现） | 依赖/提示 |
|---|---|---|---|
| `git.commit-format` | 每次提交必须可追溯、可自动审查，减少后续 review 与回溯成本。 | 采用 commitlint + commit-msg hook snippet；如检测到已有 hook 会走逐文件确认与 merge plan。 | Git 项目；已有 hook 逐文件确认 |
| `repo.language` | commit 等仓库协作文字必须有统一语言约束。 | 通过 commit-msg hook snippet 做 CJK 校验；GitHub PR/Issue workflow 已拆到 `github.language`。 | Git 项目；已有 hook 逐文件确认 |
| `project.gitignore` | 仓库必须有基础忽略规则，避免把构建产物、依赖目录或本地缓存纳入版本控制。 | 按 universal / Node.js / Python 模板检测并 merge。 | Git 项目；已有 `.gitignore` 走 merge plan |
| `ai.execution` | AI 执行方式、自动重试和汇报规则必须沉淀到项目文档中。 | 部署 AI 执行实践文档。 | 默认启用 |
| `ai.memory` | 项目长期记忆边界和经验沉淀规则必须写入仓库。 | 部署 AI 记忆边界文档并将 `AGENTS.md` 作为长期记忆锚点。 | 默认启用 |
| `knowledge.adr` | 必须有稳定的决策记录位点，避免关键架构讨论只留在会话里。 | 部署 ADR 目录与模板。 | 默认启用 |
| `knowledge.troubleshooting` | 故障处理经验必须可复用、可检索。 | 部署排障目录与入口说明。 | 默认启用 |
| `knowledge.research` | 研究结论必须可版本化沉淀，避免重复探索。 | 部署版本化研究目录。 | 默认启用 |
| `project.context` | 必须搭好产品规格与项目上下文文档区，避免需求与实现反复漂移。 | 部署项目文档骨架（产品规格入口）。 | 默认启用 |
| `knowledge.archive` | 必须有统一归档入口，减少当前上下文被历史信息淹没。 | 部署历史档案区与索引。 | 默认启用 |

## 可选治理能力提问清单

| capability id | 提问重点（价值） | 补充说明（技术实现） | 依赖/提示 |
|---|---|---|---|
| `github.language` | 是否希望 GitHub PR/Issue 文本也被 CI 检查语言规范？ | 部署 `repo-language-pr-lint.yml` 与 `repo-language-issue-lint.yml`。 | GitHub 项目；依赖 `repo.language` |
| `github.pr` | 是否希望 PR 在创建或更新时就具备固定结构，减少低质量变更和协作噪音？ | 通过 GitHub 工作流实现 PR body 结构、closing trailer 与 AI watermark 检查（`Summary` / `Implementation notes` / `Test plan`）。 | GitHub 项目 |
| `github.branch-protection` | 是否需要把分支保护前置为默认约束，降低误推风险？ | 通过 main/master ruleset 与本地 pre-push branch snippet 实现。 | GitHub 项目 |
| `release.versioning` | 是否需要统一版本号和 release tag 规则，降低误发风险？ | 通过版本规约、tag ruleset 与本地 pre-push tag snippet 实现。 | 有发布流程的项目 |
| `quality.practices` | 是否希望建立通用开发纪律和测试策略？ | 部署 dev hygiene 与 testing strategy 文档，不安装 Node.js 工具。 | 含代码项目 |
| `quality.node-tooling` | 是否希望在提交前自动拦截常见 Node.js 代码质量与格式问题？ | 通过 ESLint、Prettier、lint-staged 和 pre-commit hook snippet 实现。 | Node.js 项目；复杂配置默认 `manual_required` |
| `github.release-please` | 是否希望发版过程可复用、可追踪并减少手工版本与发布过程出错？ | 通过 release-please guide、workflow 与配置文件实现自动发布节奏。 | 仅在 GitHub + `git.commit-format` + `github.pr` 后建议；不自动启用 |

## 确认汇总

提问完成后，展示汇总：

```markdown
## 确认汇总

### 启用的治理能力
- 默认必选 → core、Git 提交/语言/.gitignore、AI 执行/记忆、ADR、排障、研究、项目上下文、归档
- github.pr → 用户选择启用 PR 协作检查与交付结构约束

### 需要确认策略的已有文件
- .husky/commit-msg → manual_required
- .github/workflows/pr-lint.yml → manual_required

### 跳过的治理能力
- quality.node-tooling（用户选择跳过）

[1] 确认 dry-run [2] 调整选择 [3] 取消
```

## 融合模式额外提问

检测到已有配置时，对每个已有配置询问：

```markdown
检测到你的项目已有 `.husky/commit-msg`。

Merge plan:
- status: manual_required
- recommendation: manual_required
- reason: shell hook 已存在，脚本无法证明安全合并

请选择：
[1] 保留现有配置
[2] 替换为 docs-governance 提供的治理模板
[3] 手动合并后继续
[4] 跳过此项
```

## 执行规则

1. `scripts/ensure-environment.sh <project-root> --check --capabilities "<resolved capability ids>"`：先返回依赖检查结果；若为 `needs_install`、`needs_initialization` 或 `needs_user_action`，先说明可执行的安装、初始化或登录动作并等待用户确认；用户若拒绝则终止流程。
2. `scaffold.sh --dry-run --enable <optional ids>` 先输出 JSON plan；脚本会自动包含 `default=true` 的必选能力
3. 用户确认可选治理能力和已有配置策略后，才执行 `scaffold.sh --apply --enable <optional ids>`；clean installer 会自动使用 `merge`，已有配置或冲突场景需补充 `--strategy <merge|replace|skip>`，具体可用策略以 capability manifest 为准
4. 有 installer-backed 的组件在执行前先用 `--check` 获取结构化 merge plan，不写 tracked files；无 installer 的组件改用 `scaffold.sh --dry-run` 与 diff-helper/manual review 产出对比描述
5. 复杂 YAML/JS/CJS/workflow/config 文件默认 `manual_required`
6. 应用后执行 `docs/harness/sensors/scripts/validate.sh --json`；需要结构一致性时执行 `docs/harness/sensors/scripts/check-consistency.sh --json`
7. 部署、融合或维护完成后，按 [docs/completion-report-template.md](docs/completion-report-template.md) 生成自然语言完成报告，向用户说明已启用能力、检查结果、未启用内容和剩余注意事项
