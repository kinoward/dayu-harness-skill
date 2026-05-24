# Phase 1e CLI 公开范围收口

本文记录 Phase 1e 对 Phase 1 CLI 的最终公开契约。CEO Plan 早期条目曾把 `merge` 和 `generate` 放入 Phase 1，但最终关卡决议将 Phase 1 收敛为 4 个公开命令，并把完整融合和独立生成能力推迟到 Phase 2。

Phase 2 后，当前 CLI 已扩展为 8 个公开命令，并迁移当前仓库全部 20 个 manifest。本文件保留 Phase 1e 收口决议；当前产品入口见 [phase2-product.md](phase2-product.md)。

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

## Phase 2 交接项

- `merge`：Phase 1e 推迟；Phase 2 已公开能力粒度 merge apply。
- `generate`：Phase 1e 推迟；Phase 2 已公开内容生成入口。
- `--force` 覆盖、孤儿文件清理、事务恢复、npm 发布和全量 manifest v2 迁移：Phase 2 已实现当前仓库 20 个 manifest 范围内的 CLI 支撑。

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
