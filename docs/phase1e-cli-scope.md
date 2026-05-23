# Phase 1e CLI 公开范围收口

本文记录 Phase 1e 对 Phase 1 CLI 的最终公开契约。CEO Plan 早期条目曾把 `merge` 和 `generate` 放入 Phase 1，但最终关卡决议将 Phase 1 收敛为 4 个公开命令，并把完整融合和独立生成能力推迟到 Phase 2。

## 目标

- 公开 CLI 命令只保留 `init`、`apply`、`diagnose`、`validate`。
- `init` 默认 dry-run，只预览将生成的 `dayu.config.yaml` 和部署计划；显式传入 `--apply` 才写入配置并执行部署。
- `apply --only <capability>` 只部署一个已启用能力及其 `deployment_deps` 闭包，用于局部验证和增量 rollout。
- 文件写入使用同目录临时文件加 rename，避免普通产物留下半写入内容。
- `merge` / `generate` 源码原型可保留给 Phase 2，但不暴露在 Phase 1 public CLI、命令树和帮助输出中。

## 公开命令

| 命令 | Phase 1e 行为 |
| --- | --- |
| `init` | 默认 dry-run；`--apply` 时创建 config 并委托 apply。 |
| `apply` | 读取 config，解析部署依赖，渲染并部署试点能力；支持 `--dry-run` 与 `--only`。 |
| `diagnose` | 只读检查已部署文件、漂移、缺失执行位和 hook snippet 状态。 |
| `validate` | 校验 manifest/config/DAG 与目标项目部署产物一致性。 |

## 推迟到 Phase 2

- `merge`：完整融合已有配置，按能力粒度确认 keep/replace/skip，并执行用户选择。
- `generate`：独立内容生成和 maintain 修复内容生成。
- `--force` 覆盖、孤儿文件清理、事务回滚、npm 发布和全 21 个能力。

## 验证

Phase 1e 入口测试位于 [tests/unit/phase1e-cli-scope.test.ts](../tests/unit/phase1e-cli-scope.test.ts)，覆盖：

- `--help` 只展示 4 个公开命令。
- `init` 默认 dry-run，`init --apply` 才写入。
- `apply --only git.commit-format` 部署 `core`、`git.hooks` 和 `git.commit-format`，不部署 `ai.execution`。
- `diagnose` JSON 输出包含 capability RSE summary。
- husky installer 的原子写入保留既有 hook symlink 和文件模式。
- 原子写入失败时清理临时文件。

运行：

```bash
npm run test:phase1e -- --test-reporter=spec
```
