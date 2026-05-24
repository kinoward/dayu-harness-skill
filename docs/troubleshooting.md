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
npx dayu-harness repair <capability-id> --target .
```

维护者命令参数可以使用 capability id；向用户解释修复范围时，仍应使用自然语言能力名。

## `status` 或 `diagnose` 显示 `wrong-mode`

含义：托管脚本内容正确，但可执行位丢失。

处理：

```bash
npx dayu-harness apply --target .
```

`apply` 会对标记为 executable 的托管脚本执行 `chmod 755`。

## `apply` 提示 lock 已存在

Dayu 使用 `.dayu-harness/apply.lock` 防止并发写入。若确认没有另一个 apply 正在运行，可以检查该文件中的 PID 和时间戳后删除。

```bash
cat .dayu-harness/apply.lock
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

只会删除 `.dayu-harness/managed-paths.json` 中记录过、且当前配置不再需要的路径。

`.dayu-harness/managed-paths.json` 是长期托管路径状态，应该提交；`.dayu-harness/apply.lock`、`.dayu-harness/journal.jsonl` 和 `.dayu-harness/tmp/` 是临时/恢复用产物，应该忽略。

## `merge --apply` 没有写入

`merge` 默认只做 dry-run。写入需要同时传入 `--apply` 和策略：

```bash
npx dayu-harness merge --target . --apply --strategy replace
```

若只想处理一个能力，使用 `--only` 缩小写入范围：

```bash
npx dayu-harness merge --target . --only <capability-id> --apply --strategy replace
```

策略含义：

| 策略 | 行为 |
| --- | --- |
| `keep` | 保留现状，只报告计划。 |
| `replace` | 对漂移的托管文件使用 `--force` 覆盖。 |
| `skip` | 跳过写入，只报告计划。 |

## `apply` 成功但流程还没有完成

`apply` 只说明本地写入完成，不代表 Dayu Harness 流程已经结束。运行时必须继续执行 `finalize`，完成本地验证、精确 stage/commit、远端同步、Issue/PR E2E、release-please 真实验证和测试产物清理中本次启用的部分；不能把这些动作列成“后续建议”交给用户。

如果当前 CLI 暴露 `finalize` 子命令：

```bash
npx dayu-harness finalize --target . --json
```

如果本次启用了 GitHub 远端能力、仓库设置、rulesets 或 release-please workflow permissions，必须显式进入远端 apply：

```bash
npx dayu-harness finalize --target . --github-remote apply --json
```

不要用 `gh repo create --push`、手写 `git push origin main` 或 API 手工创建默认分支替代 `finalize --github-remote apply`。这些手工路径不会传递受控的远端动作，也容易被本地 pre-push 或远端保护规则拦截。`.github/rulesets/*.json` 只是本地 payload；没有 GitHub Rulesets API 写入和回读时，完成报告必须保持 partial，不能宣称远端 rulesets 已应用。

如果当前构建没有该子命令，`/dayu-harness` Skill 必须按完成报告模板调用等价脚本和 Git/GitHub 流程完成同等收尾。

## `validate` 失败但 `apply` 成功

`apply` 只说明写入完成；`validate` 会重新检查目标产物是否仍与 manifest/config 一致。若 `validate` 失败，优先阅读输出中的路径和状态，然后运行：

```bash
npx dayu-harness diagnose --target . --json
```

`missing` 表示文件未部署，`drift` 表示用户改过，`needs-merge` 表示 hook 需要合并片段。

## 完成报告仍显示 capability key

面向用户的运行时输出应该显示自然语言能力名，例如“项目入口索引和文档维护说明”“自动化版本发布流程”。如果报告里直接出现 `core`、`git.commit-format`、`github.release-please` 等 key，应回到完成报告模板，将 manifest/config/JSON 中的 key 映射为自然语言名称后再汇报。

## 没有询问是否删除 Skill 安装目录

完成报告后必须结构化询问是否删除一次性 Skill 安装目录，默认删除，并展示该目录的绝对路径。选择删除时只删除该 Skill 安装目录，不删除目标项目中的 `AGENTS.md`、`docs/`、hooks、CI、`.dayu-harness/managed-paths.json` 或任何治理产物。
