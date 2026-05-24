# Getting Started: Dayu Harness CLI

Dayu Harness 现在采用混合交付形式：`/dayu-harness` Skill 负责自然语言引导和 `finalize` 收尾，`dayu-harness` CLI 负责确定性部署、诊断、融合、生成和修复。目标项目长期依赖的是被部署进去的 `AGENTS.md`、`docs/`、hooks、CI 和维护脚本，而不是当前会话。

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

4. 应用成功后立即执行 `finalize` 收尾。`finalize` 必须完成本地验证、精确提交、远端同步、Issue/PR E2E 和 release-please 真实验证中本次已启用的部分，不应把这些命令留作后续建议。

   ```bash
   npx dayu-harness finalize --target . --json
   ```

   如果当前本地构建尚未暴露 `finalize` 子命令，`/dayu-harness` Skill 必须按完成报告模板调用等价脚本和 Git/GitHub 流程完成同等收尾。

5. 查看治理地图：

   ```bash
   npx dayu-harness status --target .
   ```

6. 日后复查。以下命令可用于后续健康检查，不替代 apply 后必须执行的 `finalize`：

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
| `finalize` | apply 后的必需收尾阶段：本地验证、精确 stage/commit、远端同步、Issue/PR E2E、release-please 真实验证和测试产物清理。 |
| `status` | 按 hard / soft / infra 分组显示治理能力状态。 |
| `diagnose` | 检查已部署产物的缺失、漂移、执行位和 hook 合并状态。 |
| `validate` | 校验 manifest、config、依赖图和部署产物一致性。 |

## 安全默认值

- `init` 默认 dry-run。
- `apply` 检测到漂移时默认返回 `conflict`，不会覆盖用户修改。
- `apply` 只代表本地写入完成，不代表流程完成；运行时必须继续执行 `finalize`，不能把验证、提交、远端同步或 E2E 留给用户稍后手动处理。
- `--force` 只在显式传入时覆盖漂移文件。
- `--prune-orphans` 只删除 `.dayu-harness/managed-paths.json` 中记录过、且不再属于当前配置的托管路径。
- 每次写入前会记录 `.dayu-harness/journal.jsonl` preimage，并用 `.dayu-harness/apply.lock` 阻止并发 apply。

## 状态目录

- `.dayu-harness/managed-paths.json` 是长期托管路径状态，用于后续漂移检测、orphan 判断和精确提交，必须随治理体系提交。
- `.dayu-harness/apply.lock`、`.dayu-harness/journal.jsonl` 和 `.dayu-harness/tmp/` 只用于临时锁、失败恢复和运行缓存，必须通过 `.gitignore` 忽略。
- 面向用户的运行时输出使用自然语言能力名；manifest、`dayu.config.yaml`、CLI JSON 和维护者命令可以保留 capability key。
