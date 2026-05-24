# Phase 1d TypeScript CLI 垂直切片

本文记录 Phase 1d 的本地 TypeScript CLI 实现边界。它把 Phase 1b schema 与 Phase 1c 架构契约接成可运行的最小执行层，用于验证 Skill -> `dayu.config.yaml` -> CLI apply 的 handoff 契约。Phase 1e 后，公开 CLI 范围收敛为 `init`、`apply`、`diagnose`、`validate`；`merge` 和 `generate` 仅保留为 Phase 2 源码原型。

Phase 2 后，当前 CLI 已公开 `merge`、`generate`、`repair`、`status`，并支持当前仓库全部 20 个 manifest。本文件保留 Phase 1d 垂直切片的历史边界；当前产品入口见 [phase2-product.md](phase2-product.md)。

## 目标

- 公开提供 `init`、`apply`、`diagnose`、`validate` 四个非交互命令。
- Phase 1d 当时只加载 4 个 v2 试点 manifest：`core`、`git.hooks`、`git.commit-format`、`ai.execution`。
- 用 `deployment_deps` 解析部署顺序，输出稳定顺序：`core -> git.hooks -> git.commit-format -> ai.execution`。
- 支持 `--dry-run` 与 `--json`，让 Skill 和测试可以消费结构化结果。
- `init` 默认 dry-run；`--apply` 才创建配置并部署。
- `apply --only <capability>` 只部署一个已启用能力及其部署依赖闭包。
- 对已有不同内容的目标文件报告 conflict，不覆盖；对已部署且内容一致的文件报告 no-op。
- 复用 `scripts/install-husky.sh` 为 `git.commit-format` 安装 `commit-msg` hook 片段。

## 命令语义

| 命令 | Phase 1d 行为 |
| --- | --- |
| `init` | 目标项目缺少 `dayu.config.yaml` 时生成默认配置计划；默认 dry-run，`--apply` 时写入并调用 apply。 |
| `apply` | 读取 config，校验 4 个试点 manifest，解析部署 DAG，渲染模板/资产，安装 commit hook。 |
| `diagnose` | 基于同一 apply plan 检查已部署文件、漂移文件和 hook snippet 状态。 |
| `validate` | 校验 manifest/config/DAG，并检查目标项目部署产物是否与 plan 一致。 |

Phase 1e 决议：`merge` 和 `generate` 不作为 Phase 1 公开 CLI 命令；完整能力粒度融合和独立内容生成推迟到 Phase 2。Phase 2 已公开这些命令。

本地运行：

```bash
npm run dayu -- apply --config <target>/dayu.config.yaml --target <target> --dry-run --json
npm run dayu -- init --target <target> --locale zh --json
npm run dayu -- init --target <target> --locale zh --apply --json
npm run dayu -- diagnose --config <target>/dayu.config.yaml --target <target> --json
```

## 非目标

- Phase 1d 不迁移全量 capability；Phase 2 当前仓库的 20 个 manifest 已迁移到 v2 字段。
- Phase 1d 不发布 npm 包，不保证全局 `npx dayu-harness` 分发体验；Phase 2 已补齐 npm 发布配置。
- Phase 1d 不实现 `--force` 覆盖、孤儿文件清理、完整事务回滚、remote 操作或 Git finalization。
- 不替换现有 `scripts/scaffold.sh`；旧脚手架继续服务完整 Skill 流程。

## 验证

Phase 1d 入口测试位于 [tests/unit/phase1d-cli.test.ts](../tests/unit/phase1d-cli.test.ts)，覆盖：

- CLI `apply --dry-run --json` 确定性输出。
- 真实 apply 写入 3 个用户可见默认能力，并带上内部 `git.hooks` 依赖。
- 第二次 apply no-op。
- 冲突文件不覆盖。
- `init` 生成 config 后 apply 可消费。
- `diagnose` / `validate` 健康状态。
- 部分已存在 managed file 的可重试恢复。
- executable managed file 缺失执行位时，`diagnose` / `validate` 报告不健康，`apply` 修复执行位。

运行：

```bash
npm run test:phase1d -- --test-reporter=spec
```
