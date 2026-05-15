# docs/harness/guides/AGENTS.md

本目录索引 AI 行动前读取的规则卡片。默认治理与 Git 规则在部署时必须启用；GitHub、发布和代码工具类规则仍由对应 capability manifest 控制。

## 目录索引

- [AGENTS.md](AGENTS.md) - 当前索引
- [commit-guidelines.md](commit-guidelines.md) - 默认：提交格式约束
- [git-language-policy.md](git-language-policy.md) - 默认：仓库协作语言约束
- 可选：`github.pr` [pr-guidelines.md](pr-guidelines.md) - PR 工作流规范
- 可选：`github.branch-protection` [branch-protection.md](branch-protection.md) - 分支保护流程
- 可选：`release.versioning` [release-versioning.md](release-versioning.md) - 版本与标签规则
- 可选：`github.release-please` [release-please.md](release-please.md) - 自动发布工作流
- 可选：`quality.practices` [dev-hygiene.md](dev-hygiene.md) - 开发与测试纪律
- 可选：`quality.practices` [testing-strategy.md](testing-strategy.md) - 测试策略
- [ai-execution.md](ai-execution.md) - 默认：AI 执行方式
- [ai-memory.md](ai-memory.md) - 默认：AI 记忆边界

目录索引变化时，必须同步更新本区块；含目录、文件或能力部署清单变化。

## 文档与能力

- `git.commit-format`：`commit-guidelines.md`
- `repo.language`：`git-language-policy.md`
- `github.pr`：`pr-guidelines.md`，review checklist 见 `../sensors/reviews/`
- `github.branch-protection`：`branch-protection.md`
- `release.versioning`：`release-versioning.md`
- `github.release-please`：`release-please.md`
- `quality.practices`：`dev-hygiene.md`、`testing-strategy.md`
- `ai.execution`：`ai-execution.md`
- `ai.memory`：`ai-memory.md`
