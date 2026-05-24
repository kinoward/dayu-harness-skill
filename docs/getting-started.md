# Getting Started: Dayu Harness CLI

Dayu Harness 现在采用混合交付形式：`/dayu-harness` Skill 负责自然语言引导，`dayu-harness` CLI 负责确定性部署、诊断、融合、生成和修复。目标项目长期依赖的是被部署进去的 `AGENTS.md`、`docs/`、hooks、CI 和维护脚本，而不是当前会话。

## 安装

本仓库发布为 npm 包后，可以在目标项目中直接运行：

```bash
npx dayu-harness init --target <target-project>
```

本地开发时使用：

```bash
npm install --cache .npm-cache
npm run build
node dist/cli/main.js --help
```

## 基本流程

1. 在目标项目生成配置预览：

   ```bash
   npx dayu-harness init --target . --json
   ```

2. 审查 `dayu.config.yaml`。默认配置只启用 manifest 中 `default=true` 且非内部的能力；可选 GitHub、发布和质量能力需要显式加入配置。

3. 应用部署：

   ```bash
   npx dayu-harness init --target . --apply
   ```

4. 查看治理地图：

   ```bash
   npx dayu-harness status --target .
   ```

5. 诊断和验证：

   ```bash
   npx dayu-harness diagnose --target .
   npx dayu-harness validate --target .
   ```

## 常用命令

| 命令 | 用途 |
| --- | --- |
| `init` | 创建缺失的 `dayu.config.yaml`，默认 dry-run；`--apply` 才写入并部署。 |
| `apply` | 读取配置并按部署 DAG 写入产物；支持 `--only`、`--force`、`--prune-orphans`。 |
| `merge` | 对已有项目做能力级 keep/replace/skip 融合预览，`--only <capability> --apply --strategy replace` 可执行单能力替换式融合。 |
| `generate` | 只渲染内容预览，不写入目标项目。 |
| `repair` | 对一个能力或当前配置执行强制修复。 |
| `status` | 按 hard / soft / infra 分组显示治理能力状态。 |
| `diagnose` | 检查已部署产物的缺失、漂移、执行位和 hook 合并状态。 |
| `validate` | 校验 manifest、config、依赖图和部署产物一致性。 |

## 安全默认值

- `init` 默认 dry-run。
- `apply` 检测到漂移时默认返回 `conflict`，不会覆盖用户修改。
- `--force` 只在显式传入时覆盖漂移文件。
- `--prune-orphans` 只删除 `.dayu/managed-paths.json` 中记录过、且不再属于当前配置的托管路径。
- 每次写入前会记录 `.dayu/journal.jsonl` preimage，并用 `.dayu/apply.lock` 阻止并发 apply。
