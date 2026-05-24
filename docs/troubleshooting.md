# Troubleshooting

本页记录 Dayu Harness CLI 的常见问题和排查方式。

以下 `npx dayu-harness ...` 命令假设 npm 包已经发布。发布前在本仓库本地验证时，可先运行 `npm run build`，再将命令中的 `npx dayu-harness` 替换为 `node dist/cli/main.js`。

## `npm install` 因用户级 cache 权限失败

现象：

```text
npm error Your cache folder contains root-owned files
```

处理：

```bash
npm install --cache .npm-cache
```

这会把 cache 放到仓库内，避免修改用户全局 npm cache。

## `apply` 返回 `conflict`

含义：目标项目中某个托管路径已有文件，且内容与当前渲染结果不同。Dayu 默认不覆盖。

处理方式：

```bash
npx dayu-harness diagnose --target .
npx dayu-harness apply --target . --force
```

如果只想修复一个能力：

```bash
npx dayu-harness repair core --target .
```

## `status` 或 `diagnose` 显示 `wrong-mode`

含义：托管脚本内容正确，但可执行位丢失。

处理：

```bash
npx dayu-harness apply --target .
```

`apply` 会对标记为 executable 的托管脚本执行 `chmod 755`。

## `apply` 提示 lock 已存在

Dayu 使用 `.dayu/apply.lock` 防止并发写入。若确认没有另一个 apply 正在运行，可以检查该文件中的 PID 和时间戳后删除。

```bash
cat .dayu/apply.lock
```

不要在另一个 Dayu 进程仍运行时删除 lock。

## 删除已移除能力留下的文件

默认行为只报告 orphan，不删除：

```bash
npx dayu-harness apply --target . --dry-run
```

确认后显式清理：

```bash
npx dayu-harness apply --target . --prune-orphans
```

只会删除 `.dayu/managed-paths.json` 中记录过、且当前配置不再需要的路径。

## `merge --apply` 没有写入

`merge` 默认只做 dry-run。写入需要同时传入 `--apply` 和策略：

```bash
npx dayu-harness merge --target . --apply --strategy replace
```

若只想处理一个能力，使用 `--only` 缩小写入范围：

```bash
npx dayu-harness merge --target . --only project.gitignore --apply --strategy replace
```

策略含义：

| 策略 | 行为 |
| --- | --- |
| `keep` | 保留现状，只报告计划。 |
| `replace` | 对漂移的托管文件使用 `--force` 覆盖。 |
| `skip` | 跳过写入，只报告计划。 |

## `validate` 失败但 `apply` 成功

`apply` 只说明写入完成；`validate` 会重新检查目标产物是否仍与 manifest/config 一致。若 `validate` 失败，优先阅读输出中的路径和状态，然后运行：

```bash
npx dayu-harness diagnose --target . --json
```

`missing` 表示文件未部署，`drift` 表示用户改过，`needs-merge` 表示 hook 需要合并片段。
