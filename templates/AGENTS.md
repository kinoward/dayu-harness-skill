# AGENTS.md

本文件是项目级路由入口。先按任务读取这里，再进入 [docs/AGENTS.md](docs/AGENTS.md) 或已启用能力模块的文档。
> **阶段**: ACTIVE
> **聚焦**: Git / GitHub / 文档治理
> **规则**: 以本文件与 `docs/` 规则为准

## 目录索引

- [AGENTS.md](AGENTS.md) - 当前索引
- [CLAUDE.md](CLAUDE.md) - 任务路由入口
- [docs/AGENTS.md](docs/AGENTS.md) - core docs 目录索引
- [docs/harness/AGENTS.md](docs/harness/AGENTS.md) - core：规则、反馈检查、维护流程
- [docs/design-docs/AGENTS.md](docs/design-docs/AGENTS.md) - 默认：ADR 与设计决策
- [docs/exec-plans/AGENTS.md](docs/exec-plans/AGENTS.md) - core：执行计划
- [docs/generated/AGENTS.md](docs/generated/AGENTS.md) - core：自动生成资料索引
- [docs/product-specs/AGENTS.md](docs/product-specs/AGENTS.md) - 默认：产品规格和项目上下文
- [docs/references/AGENTS.md](docs/references/AGENTS.md) - 默认：外部资料和研究索引
- [docs/troubleshooting/AGENTS.md](docs/troubleshooting/AGENTS.md) - 默认：排障知识库
- [docs/archive/AGENTS.md](docs/archive/AGENTS.md) - 默认：历史归档
- `.husky/` - 默认：本地 Git hooks
- `.github/` - 可选：GitHub workflows、rulesets、辅助脚本
- `*` - 默认：commitlint、.gitignore；可选：ESLint、Prettier、release-please 等配置（仅示例）

目录索引变化（含目录、文件或能力部署清单变化）时，必须同步更新本区块。

## 使用顺序

- 项目总入口：本文件
- docs 结构入口：[docs/AGENTS.md](docs/AGENTS.md)
- harness 治理入口：[docs/harness/AGENTS.md](docs/harness/AGENTS.md)
- guides 规则索引：[docs/harness/guides/AGENTS.md](docs/harness/guides/AGENTS.md)
- sensors 检查索引：[docs/harness/sensors/AGENTS.md](docs/harness/sensors/AGENTS.md)
- 文档维护规范：[docs/harness/maintenance.md](docs/harness/maintenance.md)

## 当你准备提交代码

> 触发：每次 git commit 前或 hook 拒绝时
- 读取 `docs/harness/guides/commit-guidelines.md`
- 读取 `docs/harness/guides/git-language-policy.md`
- 读取 `docs/harness/guides/ai-execution.md`

## 当你准备创建或修改 PR

> 触发：创建 PR、修正文案、CI 反馈失败
- 若启用 `github.pr`，读取 `docs/harness/guides/pr-guidelines.md`
- 若启用 `github.pr`，按 `Summary / Implementation notes / Test plan` 写 PR body
- 关闭 issue 使用 GitHub closing keyword trailer，例如 `Closes #123`

## 当你发布版本、审阅 PR、排查环境

> 触发：分支发布、审阅变更、进程/端口问题
- 若启用 `github.branch-protection`，读取 `docs/harness/guides/branch-protection.md`
- 若启用 `release.versioning`，读取 `docs/harness/guides/release-versioning.md`
- 若启用 `github.release-please`，读取 `docs/harness/guides/release-please.md`
- 若启用 `github.pr`，读取 `docs/harness/sensors/reviews/code-review-checklist.md`
- 若启用 `quality.practices`，读取 `docs/harness/guides/dev-hygiene.md`

## 当你开始 AI 主导任务

> 触发：AI 接手实现或执行
- 读取 `docs/harness/guides/ai-execution.md`
- 读取 `docs/harness/guides/ai-memory.md`
- 若启用 `quality.practices`，读取 `docs/harness/guides/testing-strategy.md`

## 当你查阅知识库与项目上下文

> 触发：理解背景、排障、技术选型、项目文案
- 进入 `docs/design-docs/`、`docs/troubleshooting/`、`docs/references/research/`
- 进入 `docs/product-specs/` 或 `docs/archive/`
- 自动生成资料进入 `docs/generated/`，确认后再沉淀到长期目录

## 当你维护文档与约束

> 触发：新增、修改、删除文档
- 先读 [docs/harness/maintenance.md](docs/harness/maintenance.md)
