# Skill 使用效果测试结果

本文件记录 docs-governance Skill 自身的当前回归基线，不属于部署给用户项目的治理内容。

当前基线覆盖两类项目：

- `skill-empty-template/`：空项目，使用旧 capability id 输入，验证兼容展开到新原子能力。
- `skill-messy-template/`：已有 Node CLI 项目，验证已有 hook、CI、配置和松散文档可以 merge/保留，并补齐新的治理索引。

## 空项目兼容展开基线

用户意图：

- 使用 Git，并启用提交格式约束与语言约束。
- 跳过 GitHub PR、分支保护和 release 自动化交付能力。
- 启用质量实践、Node 工具、AI 执行/记忆、ADR、排障、研究、项目上下文和归档。

输入仍使用旧 id，以验证兼容层：

```bash
bash scripts/scaffold.sh <empty-nongithub> --dry-run --enable git.commit,git.language,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project
bash scripts/scaffold.sh <empty-nongithub> --apply --enable git.commit,git.language,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project --strategy merge
```

展开后的能力集合：

```text
core, git.hooks, git.commit-format, repo.language,
quality.practices, quality.node-tooling, project.gitignore,
ai.execution, ai.memory, knowledge.adr, knowledge.troubleshooting,
knowledge.research, project.context, knowledge.archive
```

关键结果：

- dry-run：`status="clean"`，`capability_count=14`。
- apply：`status="ok"`，部署后 `validate.sh --json` 通过。
- `.husky/commit-msg` 只包含提交格式与语言检查相关 snippet。
- `.husky/pre-commit` 由 `quality.node-tooling` 安装。
- `.husky/pre-push` 未安装，因为未启用 `github.branch-protection` 或 `release.versioning`。
- `repo.language` 安装 `repo-language-pr-lint.yml` 与 `repo-language-issue-lint.yml`；未安装 `github.pr` 的 `pr-lint.yml`。
- release-please workflow、config、manifest 均不存在。

## 已有松散项目基线

用户意图：

- 保留原有 Node CLI 代码、测试、README、CI、Husky hook 和格式化配置。
- 启用 Git 提交格式、语言约束、GitHub PR 规范、分支保护、版本/tag 保护、质量能力、AI 能力和知识库能力。
- 暂不启用 `github.release-please`。
- 对已有 hook 和配置使用 `merge`，入口文档断链和旧文档索引由 AI 在用户确认后融合。

输入：

```bash
bash scripts/scaffold.sh <messy-selected> --dry-run --enable git.commit,git.language,github.pr,github.branch-release,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project
bash scripts/scaffold.sh <messy-selected> --apply --enable git.commit,git.language,github.pr,github.branch-release,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project --strategy merge
```

展开后的能力集合：

```text
core, git.hooks, git.commit-format, repo.language,
github.pr, github.branch-protection, release.versioning,
quality.practices, quality.node-tooling, project.gitignore,
ai.execution, ai.memory, knowledge.adr, knowledge.troubleshooting,
knowledge.research, project.context, knowledge.archive
```

部署后 AI 按用户确认进行的语义融合：

- 将 `CLAUDE.md` 改为 `@AGENTS.md`。
- 将根 `AGENTS.md` 中过时的发布流程断链改为 `docs/harness/guides/release-versioning.md`。
- 将原有 `docs/notes/decision-log.md` 和 `docs/practices/commit-guidelines.md` 补入 `docs/AGENTS.md`，避免旧文档成为孤儿文档。

关键结果：

- 初始诊断按预期失败，能发现入口路由、断链、缺少 docs 索引和缺少维护脚本等问题。
- Husky 检查识别已有 hook，并给出 merge plan。
- apply 使用 merge 策略后保留原项目内容，并补齐治理体系。
- `repo-language-pr-lint.yml` / `repo-language-issue-lint.yml`、`pr-lint.yml`、`protect-main.json`、`protect-tags.json` 均存在。
- `github.release-please` 未启用，因此 `release-please.yml`、`release-please-config.json`、`.release-please-manifest.json` 均不存在。
- `.husky/commit-msg` 拦截 CJK commit message；`.husky/pre-push` 分别拦截 `main` 直推/删除和删除 `v*` release tag。
- `validate.sh --json`、`audit.sh --json`、`check-consistency.sh --json` 均通过。

## CI 稳定层 E2E

上述基线固化在 [test-skill-interaction-e2e.bats](../unit/test-skill-interaction-e2e.bats)。

覆盖范围：

- 从 fixture 模板复制临时实例，不直接修改模板。
- 回放 AI 问答后的能力选择，并验证旧 id 兼容展开。
- 验证 dry-run、apply、merge、部署后检查和语义融合后的结果。
- 验证原子能力边界：未启用的 hook、workflow、ruleset 或 release-please 文件不会被误部署。

运行方式：

```bash
bats tests/unit/test-skill-interaction-e2e.bats
bats tests/unit
```

CI 依赖：

- `bats`
- `jq`
- 常见 shell 工具：`bash`、`awk`、`perl`、`find`

临时运行实例只写入 `tests/unit/.tmp/`，该目录只保留 `.gitignore`。
