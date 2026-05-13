# AGENTS.md

本文件是项目级路由入口。先按任务读取这里，再进入 [docs/AGENTS.md](docs/AGENTS.md) 或已启用能力模块的文档。
> **阶段**: ACTIVE
> **聚焦**: Git / GitHub / 文档治理
> **规则**: 以本文件与 `docs/` 规则为准

## 目录结构

```
<project>/
├── CLAUDE.md                  # core：仅引用 @AGENTS.md
├── AGENTS.md                  # core：项目级任务路由入口
├── docs/
│   ├── AGENTS.md              # core：docs 目录索引
│   ├── doc-maintenance.md     # core：文档体系维护规范
│   ├── practices/             # core 索引 + 可选工程实践文档
│   ├── scripts/               # core：诊断、验证、差异、一致性脚本
│   ├── decisions/             # 可选：ADR 决策记录
│   ├── troubleshooting/       # 可选：排障知识库
│   ├── research/              # 可选：版本化研究
│   ├── project/               # 可选：项目专属内容
│   └── archive/               # 可选：历史归档
├── .husky/                    # 可选：本地 Git hooks
├── .github/                   # 可选：GitHub workflows、rulesets、辅助脚本
└── *                          # 可选：commitlint、ESLint、Prettier、release-please 等配置
```

目录结构变化（含目录、文件或能力部署清单变化）时，必须同步更新本区块。

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
