# Phase 1c 架构契约

本文把 CEO Plan 中的 Phase 1c 落成可执行契约，供 Phase 1d/1e TypeScript CLI 垂直切片直接引用。Phase 1c 不实现完整 CLI 写入流程；它先固定命令树、依赖图和三层边界，避免执行层重新解释架构。Phase 1e 按最终关卡决议将公开命令收敛为 4 个。

## 目标

- 固化 Phase 1 公开 CLI 命令的职责边界：`init`、`apply`、`diagnose`、`validate`。
- 将依赖拆成部署 DAG 和概念依赖图，明确二者的消费者和错误语义。
- 明确 Frontend / Tool / Product 三层分离，禁止跨层耦合。
- 用 TypeScript 纯函数契约覆盖 Phase 1d 需要复用的静态行为。

## 非目标

- 不提供 `npx dayu-harness` 的最终可执行入口。
- 不重写 `scripts/scaffold.sh`。
- 不批量迁移全部 legacy manifest 到 v2。
- 不改变现有脚手架的 `dependencies` 兼容语义。
- 不实现 `--force` 覆盖、孤儿文件清理、事务回滚或 `repair`。

## CLI 命令树

CLI 属于 Tool 层。Skill 负责自然语言引导和问题选择，CLI 不做交互式问答；所有命令都必须支持 `--json` 机器输出，默认输出人类可读摘要。

| 命令 | 作用 | 对应旧模式 | Phase 1 语义 |
| --- | --- | --- | --- |
| `init` | 若缺少 `dayu.config.yaml`，生成默认配置，然后委托 `apply` | scaffold 入口 | 默认 dry-run；`--apply` 才写入 |
| `apply` | 读取 config，解析部署 DAG，渲染文件，运行 installer，输出漂移或冲突 | scaffold 执行阶段 | 支持 `--dry-run` 与 `--only <capability>` |
| `diagnose` | 检查已部署治理体系健康状态，并承接 maintain 的不一致检测 | diagnose + maintain 检测 | 只读 |
| `validate` | 校验 manifest、config、依赖和部署产物一致性 | 新命令 | 只读 |

对应 TypeScript 契约位于 [src/architecture/cli-command-tree.ts](../src/architecture/cli-command-tree.ts)。

`merge` 和 `generate` 的完整公开命令推迟到 Phase 2；Phase 1 不在 CLI help、命令树或公开测试入口暴露它们。

## 依赖模型

Phase 1c 明确两类依赖：

| 图 | 字段 | 用途 | 消费者 | 是否阻塞部署 |
| --- | --- | --- | --- | --- |
| 部署 DAG | `deployment_deps` | 确定安装顺序和部署闭包 | CLI `apply` / `validate` | 是 |
| 概念依赖图 | `conceptual_deps` | 帮助用户理解规则引用和交互顺序 | Skill / CLI `status` 类摘要 | 否 |

规则：

- 部署 DAG 必须拓扑排序，依赖先于被依赖者部署。
- 缺失部署依赖和环依赖是 fatal error。
- 当多个能力的依赖都已满足时，排序按 `infra`、`hard`、`soft` 的能力类型优先级执行，同类型再按能力 ID 字典序排序，保证 dry-run/apply 输出不依赖文件系统读取顺序。
- 概念依赖可以影响展示顺序，但不得扩大部署闭包。
- Phase 1 迁移期内，v2 试点 manifest 的旧 `dependencies` 必须继续镜像 `deployment_deps`，因为现有 `scaffold.sh` 仍读取 `dependencies`。

Phase 1d 选定能力的部署 DAG：

```text
core
└── git.hooks
    └── git.commit-format

core
└── ai.execution
```

当 config 请求 `git.commit-format` 和 `ai.execution` 时，部署顺序应为：

```text
core -> git.hooks -> git.commit-format -> ai.execution
```

当前 4 个 v2 试点能力的 `conceptual_deps` 为空。后续如果 `ai.execution` 概念上引用 `git.commit-format`，它只能影响说明排序，不能让只启用 `ai.execution` 的部署自动安装 commit hook。

对应 TypeScript 契约位于 [src/architecture/dependency-graph.ts](../src/architecture/dependency-graph.ts)。

## 三层分离

| 层 | 内容 | 职责 | 允许依赖 |
| --- | --- | --- | --- |
| Frontend | `SKILL.md`、问答流程、`dayu.config.yaml` 生成 | 引导用户形成配置，然后调用 CLI | Tool |
| Tool | `src/`、`capabilities/`、`locales/`、`templates/`、`assets/`、CLI | 校验、规划、渲染、部署 Product 层产物 | Product |
| Product | 目标项目中的 `AGENTS.md`、`docs/`、hooks、CI、配置文件 | Skill 删除后独立运行治理体系 | 无 |

边界约束：

- Frontend 不直接读取模板或写入 Product 文件，只生成/修改 `dayu.config.yaml` 并调用 CLI。
- Tool 不依赖 Skill 会话状态；CLI 必须能在没有 Agent 客户端的环境中运行。
- Product 不 import Skill 的 `src/`，不读取 `capabilities/`，不依赖 `templates/` 或 `assets/`。
- Tool 可以生成 Product，但 Product 的长期权威是目标项目内的 `AGENTS.md` 与 `docs/`。

对应 TypeScript 契约位于 [src/architecture/layers.ts](../src/architecture/layers.ts)。

## Phase 1d/1e 入口标准

进入 Phase 1d 前应满足：

- `phase1b-schema.test.ts` 继续通过，保证 manifest/config schema 契约未回退。
- `phase1c-architecture.test.ts` 通过，保证命令树、依赖图和层级边界可被代码引用。
- `scaffold.sh` spike 已记录现有 Bash 逻辑，TypeScript port 不重新猜测旧行为。
- Phase 1d 只面向 4 个 v2 试点能力读取 `ManifestV2Schema`；legacy manifest 全量迁移留到 Phase 2。
- Phase 1e 公开 CLI 只暴露 4 个命令；`init` 默认 dry-run，`apply --only` 可部署单能力闭包。
