# AGENTS.md

本文件是项目级权威入口。外部工具和模板（包括 docs-governance skill）仅作为创建和维护本体系的辅助参考。如发生冲突，以本文件及 docs/ 下的项目文档为准。

本文件是纯路由索引，根据当前任务类型跳转到 `docs/` 中的对应文档。

<!-- ═══════════════════════════════════════════════════════════════════════ -->
<!-- STATUS BANNER — AI 先读这里了解项目阶段                                 -->
<!-- ══ -->
<!-- 阶段: [INIT / ACTIVE / MAINTENANCE / ARCHIVED]                         -->
<!-- 活跃关注: [当前 1-3 个核心事项]                                          -->
<!-- ═══════════════════════════════════════════════════════════════════════ -->

> **阶段**: 初始构建 (INIT)
> **活跃关注**: 建立基础约束体系, 核心功能开发

## 当你准备提交代码 (git commit)

> 触发时机：每次 git commit 前，或提交信息被 hook 拒绝需要修复时

- Git 提交规范：[docs/practices/commit-guidelines.md](docs/practices/commit-guidelines.md)
- Git 语言规范：[docs/practices/git-language-policy.md](docs/practices/git-language-policy.md)
- AI 协作风格：[docs/practices/ai-collaboration.md](docs/practices/ai-collaboration.md)（仅阅读「Auto-Retry 通用约定」章节）

## 当你准备创建或修改 PR

> 触发时机：创建 PR、修改 PR 标题/正文、推送新 commit 后 CI 反馈失败

- PR 工作流规范：[docs/practices/pr-guidelines.md](docs/practices/pr-guidelines.md)
- AI 协作风格：[docs/practices/ai-collaboration.md](docs/practices/ai-collaboration.md)（仅阅读「Test plan 执行与汇报」和「结构化输出消费模式」章节）

## 当你在做代码 Review

> 触发时机：审查 PR 变更、完成一段实现后自查

- 代码 Review 自检清单：[docs/practices/code-review-checklist.md](docs/practices/code-review-checklist.md)

## 当你准备发布版本

> 触发时机：管理分支、合并 PR、发布版本、创建 tag

- 分支与发布管理：[docs/practices/branch-and-release.md](docs/practices/branch-and-release.md)

## 当你开始或排查开发环境问题

> 触发时机：启动/结束开发、排查端口占用、进程残留、磁盘冗余

- 开发与测试纪律：[docs/practices/dev-hygiene.md](docs/practices/dev-hygiene.md)

## 当你开始 AI 主导的实施任务

> 触发时机：AI 接手实现任务，需要了解分工、自主执行边界、经验沉淀规则

- AI 协作风格：[docs/practices/ai-collaboration.md](docs/practices/ai-collaboration.md)
- 测试策略：[docs/practices/testing-strategy.md](docs/practices/testing-strategy.md)

## 当需要查阅历史决策、排障知识、研究成果

> 触发时机：需要理解设计背景、排查非表面问题、参考技术选型结论

- 架构决策记录：[docs/decisions/AGENTS.md](docs/decisions/AGENTS.md)
- 排障知识库：[docs/troubleshooting/AGENTS.md](docs/troubleshooting/AGENTS.md)
- 版本化研究院：[docs/research/AGENTS.md](docs/research/AGENTS.md)

## 当需要了解项目专属内容

> 触发时机：需要了解项目特定的业务背景、设计风格、写作草稿

- 项目专属文档：[docs/project/AGENTS.md](docs/project/AGENTS.md)

## 当需要查阅已废弃的历史内容

> 触发时机：考古追溯，查看过往已废弃的决策、实现或设计

- 归档索引：[docs/archive/AGENTS.md](docs/archive/AGENTS.md)

## 当需要新增或修改文档

> 触发时机：新增、修改、删除文档或工程约束

- 文档维护规范：[docs/doc-maintenance.md](docs/doc-maintenance.md)

## 项目概述

> 项目的基本信息、目标、技术栈等。由 Skill 初始化时根据用户回答填充，或由用户后续自行维护。

<!-- PROJECT_OVERVIEW_START -->
<!-- PROJECT_OVERVIEW_END -->

## 优先级

当不同来源的指令冲突时：

1. 用户在当前对话中的最新明确要求
2. 本文件及 docs/ 下的项目文档
3. 外部工具和模板（包括 docs-governance skill）
4. 现有代码实现和项目惯例

## 常用信息

<!-- PROJECT_INFO_START -->
<!-- PROJECT_INFO_END -->
