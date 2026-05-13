# AGENTS.md

本文件是项目级路由入口。先按任务读取这里，再进入 [docs/AGENTS.md](docs/AGENTS.md) 或已启用能力模块的文档。
> **阶段**: ACTIVE
> **聚焦**: Git / GitHub / 文档治理
> **规则**: 以本文件与 `docs/` 规则为准

## 使用顺序

- 项目总入口：本文件
- docs 结构入口：[docs/AGENTS.md](docs/AGENTS.md)
- practices 模块索引：[docs/practices/AGENTS.md](docs/practices/AGENTS.md)
- 文档维护规范：[docs/doc-maintenance.md](docs/doc-maintenance.md)

## 当你准备提交代码

> 触发：每次 git commit 前或 hook 拒绝时
- 若启用 `git.commit`，读取 `docs/practices/commit-guidelines.md`
- 若启用 `git.language`，读取 `docs/practices/git-language-policy.md`
- 若启用 `ai.collaboration`，读取 `docs/practices/ai-collaboration.md`

## 当你准备创建或修改 PR

> 触发：创建 PR、修正文案、CI 反馈失败
- 若启用 `github.pr`，读取 `docs/practices/pr-guidelines.md`
- 若启用 `github.pr`，按 `Summary / Implementation notes / Test plan` 写 PR body
- 关闭 issue 使用 GitHub closing keyword trailer，例如 `Closes #123`

## 当你发布版本、审阅 PR、排查环境

> 触发：分支发布、审阅变更、进程/端口问题
- 若启用 `github.branch-release`，读取 `docs/practices/branch-and-release.md`
- 若启用 `github.pr`，读取 `docs/practices/code-review-checklist.md`
- 若启用 `quality.tooling`，读取 `docs/practices/dev-hygiene.md`

## 当你开始 AI 主导任务

> 触发：AI 接手实现或执行
- 若启用 `ai.collaboration`，读取 `docs/practices/ai-collaboration.md`
- 若启用 `quality.tooling`，读取 `docs/practices/testing-strategy.md`

## 当你查阅知识库与项目上下文

> 触发：理解背景、排障、技术选型、项目文案
- 启用对应知识库模块后，进入 `docs/decisions/`、`docs/troubleshooting/`、`docs/research/`
- 启用项目文档模块后，进入 `docs/project/` 或 `docs/archive/`

## 当你维护文档与约束

> 触发：新增、修改、删除文档
- 先读 [docs/doc-maintenance.md](docs/doc-maintenance.md)
