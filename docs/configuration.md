# Configuration Reference

`dayu.config.yaml` 是 Skill 与 CLI 之间的接口契约，也是 CLI 的唯一部署输入。Skill 可以生成它，CLI 只消费它。

## 顶层结构

```yaml
schemaVersion: "1.0.0"
locale: zh
project:
  name: my-project
capabilities:
  - id: core
  - id: git.commit-format
  - id: ai.execution
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `schemaVersion` | string | 当前固定为 `"1.0.0"`。 |
| `locale` | `zh` / `zh-CN` / `en` / `en-US` | CLI 会归一化为 `zh` 或 `en`。 |
| `project.name` | string | 可选，目标项目名。 |
| `project.root` | string | 可选，相对 config 文件或绝对路径的目标项目根目录。 |
| `capabilities[].id` | string | 能力 ID，必须存在于 `capabilities/*.json`。 |
| `capabilities[].enabled` | boolean | 可选，默认 `true`；设为 `false` 时不参与部署。 |
| `capabilities[].options` | object | 可选，预留给后续能力参数。 |

## 能力数量口径

当前仓库包含 20 个 capability manifest。计划文件中出现过 21 个能力的早期口径，但同一计划后文和仓库事实均为 20 个 manifest，因此 Phase 2 以 20 个现有能力为准。

## 能力分类

| 类型 | 说明 | 当前数量 |
| --- | --- | --- |
| `hard` | 具备 Rule、Sensor、Enforcer 完整链路，例如 Git hooks 或 GitHub Actions。 | 9 |
| `soft` | 仅部署 Rule 文档，约束协作方式或质量习惯。 | 3 |
| `infra` | 提供目录、索引、脚本、hook 承载或知识库基础设施。 | 8 |

## 依赖

每个 manifest 同时声明：

- `deployment_deps`：部署 DAG 使用，阻塞实际写入顺序。
- `conceptual_deps`：解释和展示使用，不阻塞部署。
- `dependencies`：兼容 legacy `scaffold.sh` 的桥接字段，必须与 `deployment_deps` 保持一致；当前 CLI 主路径读取 `deployment_deps`。

`apply --only <capability>` 会部署指定能力及其 `deployment_deps` 闭包。

## 全能力配置示例

```yaml
schemaVersion: "1.0.0"
locale: zh
capabilities:
  - id: core
  - id: git.commit-format
  - id: ai.execution
  - id: ai.memory
  - id: project.gitignore
  - id: knowledge.adr
  - id: knowledge.archive
  - id: knowledge.research
  - id: knowledge.troubleshooting
  - id: project.context
  - id: github.repository-settings
  - id: github.pr
  - id: github.issue
  - id: github.branch-protection
  - id: release.versioning
  - id: github.release-please
  - id: quality.practices
  - id: quality.node-tooling
  - id: quality.tdd
```

`git.hooks` 是内部承载能力，一般不需要手动加入；当启用 hook-backed 能力时，部署 DAG 会自动加入。
