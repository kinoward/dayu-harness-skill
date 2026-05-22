# GitHub 仓库设置

> 可选能力：`github.repository-settings`

本文件说明仓库级 PR 设置如何和项目内治理资产保持一致。用户在 `/dayu-harness` 问答中选择启用后，`scaffold.sh --apply` 会直接调用 GitHub API 修改目标远端仓库设置；`--dry-run` 只预览，不修改远端。

## 部署文件

- `.github/repository/pull-request-settings.json`：仓库 PR 设置策略。

策略当前锁定：

```json
{
  "allow_merge_commit": true,
  "allow_squash_merge": false,
  "allow_rebase_merge": false,
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
```

## 远端应用行为

启用 `github.repository-settings` 后，脚手架会在 apply 阶段自动执行等价操作：

```bash
gh api -X PATCH "repos/<owner>/<repo>" \
  -F allow_merge_commit=true \
  -F allow_squash_merge=false \
  -F allow_rebase_merge=false \
  -F allow_auto_merge=true \
  -F delete_branch_on_merge=true
```

执行前必须满足：

- `gh auth status` 已登录目标 GitHub 账号。
- 当前账号具备仓库 administration 权限。
- release-please 或其他自动合并流程已经使用 GitHub auto-merge，而不是人工 label gate。
- 默认分支 ruleset 仅允许 merge commit；仓库级 squash/rebase 入口应同步关闭，避免绕过 release-please 的 changelog 去重策略。

脚手架按以下顺序识别目标仓库：

1. `DAYU_HARNESS_GITHUB_REPOSITORY=owner/repo`
2. 目标项目的 GitHub `origin` 远端
3. `gh repo view` 当前仓库识别结果

如需手动重放远端设置，可以在目标项目中执行上面的 `gh api` 命令。

## 维护规则

- 该配置只表达仓库级事实，不替代 branch protection ruleset。
- 修改 `.github/repository/pull-request-settings.json` 后，同步更新本文件。
- 必须保持 `allow_merge_commit=true`、`allow_squash_merge=false`、`allow_rebase_merge=false`，使仓库 UI/API 与默认分支 ruleset 的 merge-only 策略一致。
- 如果 release-please 依赖自动合并，必须保持 `allow_auto_merge` 为 `true`。
- 如果希望合并后自动清理 release 分支，必须保持 `delete_branch_on_merge` 为 `true`。
