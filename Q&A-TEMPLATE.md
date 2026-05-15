# Q&A 参考模板

> 本模板只定义提问方式和融合策略。治理能力列表、依赖、模板文件、资产文件、验收标准以 `capabilities/*.json` 为单一事实源；新增或删除治理能力时优先更新 manifest，再按 manifest 生成或校验本模板的提问内容。

## 适配规则

- 项目已有 `commitlint.config.cjs` → 不直接问「是否启用提交校验」，而是确认「检测到已有 commitlint，是否保留/增强/跳过」
- 项目已有 `docs/` 但结构不同 → 进入融合模式，逐项确认
- 项目已有 `.husky/`、`.github/workflows/`、ESLint/Prettier/lint-staged 等配置 → 先调用对应 `install-*.sh --check` 获取 JSON merge plan
- `replace` 只能由用户显式选择；`merge` 只表示脚本能证明安全的确定性合并，否则返回 `manual_required`

## 前置问题

每项 3 选项：[1] 启用 [2] 跳过 [3] 自定义需求。

```
Q: 项目是否使用 Git 版本控制？
   选项：[1] 是 [2] 否 [3] 其他版本控制系统（请描述）

Q: 是否使用 GitHub 远程托管？
   （仅 Git 项目继续询问）
   选项：[1] 是 [2] 否 [3] 其他托管平台（请描述）
```

## 治理能力提问清单

以下清单应从 manifest 字段生成或校验：`id`、`description_nl`、`dependencies`、`requires`、`acceptance`、`suggested_when`。

| capability id | 提问重点（价值） | 补充说明（技术实现） | 依赖/提示 |
|---|---|---|---|
| `git.commit-format` | 是否希望把每次提交约束为可追溯、可自动审查的标准格式，从而减少后续 review 与回溯成本？ | 采用 commitlint + commit-msg hook snippet；如检测到已有 hook 会走逐文件确认与 merge plan。 | Git 项目；已有 hook 逐文件确认 |
| `repo.language` | 是否需要对 commit/PR/issue/release notes/分支名称等协作文字保持统一语言约束？ | 通过 commit-msg hook snippet 与 GitHub language workflows 做 CJK 校验。 | Git 或 GitHub 项目 |
| `github.pr` | 是否希望 PR 在创建或更新时就具备固定结构，减少低质量变更和协作噪音？ | 通过 GitHub 工作流实现 PR body 结构、closing trailer 与 AI watermark 检查（`Summary` / `Implementation notes` / `Test plan`）。 | GitHub 项目 |
| `github.branch-protection` | 是否需要把分支保护前置为默认约束，降低误推风险？ | 通过 main/master ruleset 与本地 pre-push branch snippet 实现。 | GitHub 项目 |
| `release.versioning` | 是否需要统一版本号和 release tag 规则，降低误发风险？ | 通过版本规约、tag ruleset 与本地 pre-push tag snippet 实现。 | 有发布流程的项目 |
| `quality.practices` | 是否希望建立通用开发纪律和测试策略？ | 部署 dev hygiene 与 testing strategy 文档，不安装 Node.js 工具。 | 含代码项目 |
| `quality.node-tooling` | 是否希望在提交前自动拦截常见 Node.js 代码质量与格式问题？ | 通过 ESLint、Prettier、lint-staged 和 pre-commit hook snippet 实现。 | Node.js 项目；复杂配置默认 `manual_required` |
| `project.gitignore` | 是否希望规范化 `.gitignore`？ | 按 universal / Node.js / Python 模板检测并 merge。 | Git 项目 |
| `ai.execution` | 是否希望把 AI 执行方式、自动重试和汇报规则沉淀到项目文档中？ | 部署 AI 执行实践文档。 | 推荐 AI 经常参与实现的项目启用 |
| `ai.memory` | 是否希望把项目长期记忆边界和经验沉淀规则写入仓库？ | 部署 AI 记忆边界文档并将 `AGENTS.md` 作为长期记忆锚点。 | 有长期 AI 协作或知识沉淀需求时启用 |
| `knowledge.adr` | 是否需要有稳定的决策记录位点，避免关键架构讨论只留在会话里？ | 部署 ADR 目录与模板。 | 通用 |
| `knowledge.troubleshooting` | 是否需要将故障处理经验沉淀为可复用、可检索的知识？ | 部署排障目录与入口说明。 | 通用 |
| `knowledge.research` | 是否需要持续沉淀研究结论，避免反复重复同类探索？ | 部署版本化研究目录。 | 有持续调研需求时启用 |
| `project.context` | 是否要先搭好产品规格与项目上下文文档区，避免需求与实现反复漂移？ | 部署项目文档骨架（产品规格入口）。 | 有项目说明、草稿、设计背景时启用 |
| `knowledge.archive` | 是否需要统一归档旧内容，减少当前上下文被历史信息淹没？ | 部署历史档案区与索引。 | 有废弃/历史内容时启用 |
| `github.release-please` | 是否希望发版过程可复用、可追踪并减少手工版本与发布过程出错？ | 通过 release-please guide、workflow 与配置文件实现自动发布节奏。 | 仅在 GitHub + `git.commit-format` + `github.pr` 后建议；不自动启用 |

## 确认汇总

提问完成后，展示汇总：

```markdown
## 确认汇总

### 启用的治理能力
- git.commit-format → 已启用提交格式约束，提交信息和协作流程更容易审查与追溯
- github.pr → 已启用 PR 协作检查与交付结构约束

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

1. `scaffold.sh --dry-run --enable <ids>` 先输出 JSON plan
2. 用户确认启用治理能力和策略后，才执行 `scaffold.sh --apply --enable <ids> --strategy <merge|replace|skip>`；具体可用策略以 capability manifest 为准
3. `install-*.sh --check` 只输出 merge plan，不写 tracked files
4. 复杂 YAML/JS/CJS/workflow/config 文件默认 `manual_required`
5. 应用后执行 `docs/harness/sensors/scripts/validate.sh --json`；需要结构一致性时执行 `docs/harness/sensors/scripts/check-consistency.sh --json`
6. 部署、融合或维护完成后，按 [docs/completion-report-template.md](docs/completion-report-template.md) 生成自然语言完成报告，向用户说明已启用能力、检查结果、未启用内容和剩余注意事项
