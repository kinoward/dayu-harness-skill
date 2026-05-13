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

| capability id | 提问重点 | 依赖/提示 |
|---|---|---|
| `git.commit` | 是否在 commit 时校验 Conventional Commits，并安装 husky/commitlint | Git 项目；已有 hook 逐文件确认 |
| `git.language` | 是否要求 commit/PR/issue/release notes/branch 名使用英文 | 依赖 `git.commit` 的本地 hook 载体 |
| `github.pr` | 是否启用 GitHub-native PR 规范、PR/issue lint、PR body 结构检查 | GitHub 项目；PR body 使用 `Summary / Implementation notes / Test plan` |
| `github.branch-release` | 是否启用分支/标签保护规则与本地 pre-push 保护 | GitHub 项目；依赖 `git.commit` |
| `quality.tooling` | 是否启用 ESLint、Prettier、lint-staged、`.gitignore` | 含代码项目；复杂配置默认 `manual_required` |
| `ai.collaboration` | 是否部署 AI 协作实践文档 | 推荐 AI 经常参与实现的项目启用 |
| `knowledge.adr` | 是否建立 ADR 决策记录目录 | 通用 |
| `knowledge.troubleshooting` | 是否建立排障知识库 | 通用 |
| `knowledge.research` | 是否建立版本化研究目录 | 有持续调研需求时启用 |
| `project.docs` | 是否建立产品规格与项目上下文文档区 | 有项目说明、草稿、设计背景时启用 |
| `archive.project` | 是否建立项目归档区 | 有废弃/历史内容时启用 |
| `github.release-please` | 是否启用 release-please 自动发版 | 仅在 GitHub + `git.commit` + `github.pr` 后建议；不自动启用 |

## 确认汇总

提问完成后，展示汇总：

```markdown
## 确认汇总

### 启用的治理能力
- git.commit → 安装 husky + commitlint，部署 commit-guidelines.md
- github.pr → 部署 PR/issue lint 与 PR 规范文档

### 需要确认策略的已有文件
- .husky/commit-msg → manual_required
- .github/workflows/pr-lint.yml → manual_required

### 跳过的治理能力
- quality.tooling（用户选择跳过）

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
2. 用户确认启用治理能力和策略后，才执行 `scaffold.sh --apply --enable <ids> --strategy <merge|skip>`
3. `install-*.sh --check` 只输出 merge plan，不写 tracked files
4. 复杂 YAML/JS/CJS/workflow/config 文件默认 `manual_required`
5. 应用后执行 `docs/harness/sensors/scripts/validate.sh --json`；需要结构一致性时执行 `docs/harness/sensors/scripts/check-consistency.sh --json`
