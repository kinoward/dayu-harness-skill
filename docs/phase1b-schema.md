# Phase 1b Schema 契约

本文记录 Phase 1b 的 schema 与配置契约。它服务 Skill 维护者，不属于部署到目标项目的治理产物。

Phase 1b 的目标不是替换 `scripts/scaffold.sh`，而是先把能力清单、配置文件、i18n 文案和路径安全规则固化为可测试的 TypeScript/Zod 契约，给 Phase 1c/1d/1e 的 CLI 实现提供稳定输入。

## 范围

Phase 1b 覆盖 4 类 schema：

| 契约 | 源码 | 作用 |
| --- | --- | --- |
| manifest v2 | `src/schemas/manifest-v2.schema.ts` | 校验试点能力的部署依赖、能力类型、RSE 链路、i18n key 和文件路径。 |
| `dayu.config.yaml` | `src/schemas/dayu-config.schema.ts` | 定义 Skill 前端到 CLI 的 handoff 格式，包括项目根目录、语言和启用能力。 |
| locale catalog | `src/schemas/locales.schema.ts` | 校验 key-based i18n 文案 catalog 的语言和占位符规则。 |
| shared path safety | `src/schemas/shared.ts` | 禁止绝对路径、`..` 穿越、NUL 字节、Windows drive 和 UNC 路径进入部署映射。 |

## manifest v2 字段

Phase 1b 只迁移 4 个试点 manifest：

- `core`
- `git.hooks`
- `git.commit-format`
- `ai.execution`

新增字段：

| 字段 | 语义 |
| --- | --- |
| `schemaVersion` | manifest v2 标记。Phase 1b 试点能力必须存在该字段。 |
| `kind` | 能力类型：`infra`、`hard`、`soft`。用于说明、排序和 RSE 完整性判断。 |
| `deployment_deps` | 部署 DAG 依赖，供 CLI `apply` / `validate` 决定部署闭包和顺序。 |
| `conceptual_deps` | 概念依赖，只服务说明和展示，不扩大部署闭包。 |
| `i18n` | 文案 key 声明，要求 locale catalog 有对应条目。 |
| `rse` | Rule-Sensor-Enforcer 链路描述，说明能力由规则、传感器和执行器中的哪些部分组成。 |

迁移期要求：旧 `dependencies` 字段必须继续保留，并且与 `deployment_deps` 完全一致。原因是完整脚手架仍由 `scripts/scaffold.sh` 承载，而 Bash 版本继续读取 `dependencies`。

## RSE 约束

RSE 是 Rule / Sensor / Enforcer 的缩写：

- Rule：文档或配置中描述的规则。
- Sensor：能检测规则是否被满足的脚本、配置或 workflow。
- Enforcer：能拦截或自动执行规则的 hook、CI 或同类机制。

`kind: hard` 的能力必须有完整或足够明确的执行链路。例如 `git.commit-format` 既有提交规范文档，也有 `commitlint.config.cjs` 和 `commit-msg` hook。`kind: soft` 的能力可以只有 Rule，例如 `ai.execution` 主要约束协作方式，不强制机械拦截。

## `dayu.config.yaml`

`dayu.config.yaml` 是 Skill 前端和 CLI 之间的交接文件。Phase 1d/1e 的 CLI 不做交互式问答，只读取该配置并执行确定性规划。

当前默认配置包含：

- `schemaVersion`
- `locale`
- `project.name`
- `capabilities`

`project.root` 是可选字段，主要用于外部 config 指向另一个目标项目根目录；默认 `init --apply` 写入的是 `project.name`。

CLI 行为：

- `init` 缺少配置时生成默认配置计划。
- `init` 默认 dry-run，只有 `--apply` 才写入配置并委托 `apply`。
- `apply` 只部署配置中启用的能力及其 `deployment_deps` 闭包。
- `apply --only <capability>` 只能选择已启用能力，并自动带上部署依赖。

## i18n 契约

Phase 1b 引入 key-based i18n catalog，用于把能力说明、错误信息和未来 CLI 文案从模板路径中分离出来。

当前边界：

- Bash `scaffold.sh` 仍主要依赖 `templates/` 与 `templates.en/` 双模板树。
- `{{dayu:key}}` token 属于 schema/token 契约，尚未接入完整 Bash 渲染。
- Phase 1d/1e TypeScript CLI 继续保留双模板树语义，避免一次迁移过多行为。

## 路径安全

所有 manifest 映射路径都必须是仓库相对路径。禁止：

- 绝对路径。
- `..` 目录穿越。
- NUL 字节。
- Windows drive path。
- UNC path。

这条规则同时保护部署源路径和目标路径，避免能力 manifest 把文件写到目标项目之外。

## 验证

Phase 1b 入口测试位于 [tests/unit/phase1b-schema.test.ts](../tests/unit/phase1b-schema.test.ts)，覆盖：

- 试点能力 manifest v2 校验。
- 缺少 `schemaVersion` 时的可读错误路径。
- `dependencies` 与 `deployment_deps` 镜像要求。
- hard 能力 RSE 链路完整性。
- manifest/config/schema 中的路径安全拒绝。
- `dayu.config.yaml` 解析和未知能力报告。
- locale catalog key 覆盖和占位符格式。

运行：

```bash
npm run test:phase1b -- --test-reporter=spec
```

如果修改 manifest v2 字段、`dayu.config.yaml`、locale key、路径校验或试点能力列表，必须先更新本测试，再继续改 CLI 或脚手架逻辑。
