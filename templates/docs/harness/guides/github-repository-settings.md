# GitHub 仓库设置

> 可选能力：`github.repository-settings`

本文件说明仓库级 PR 设置如何和项目内治理资产保持一致。Skill 只部署配置文件和操作说明，不会自动修改 GitHub 远端仓库。

## 部署文件

- `.github/repository/pull-request-settings.json`：仓库 PR 设置策略。

策略当前锁定：

```json
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
```

## 应用到远端

确认仓库 owner/name 后，由维护者在目标项目中执行：

```bash
gh api -X PATCH "repos/<owner>/<repo>" \
  -F allow_auto_merge=true \
  -F delete_branch_on_merge=true
```

执行前确认：

- `gh auth status` 已登录目标 GitHub 账号。
- 当前账号具备仓库 administration 权限。
- release-please 或其他自动合并流程已经使用 GitHub auto-merge，而不是人工 label gate。

## 维护规则

- 该配置只表达仓库级事实，不替代 branch protection ruleset。
- 修改 `.github/repository/pull-request-settings.json` 后，同步更新本文件。
- 如果 release-please 依赖自动合并，必须保持 `allow_auto_merge` 为 `true`。
- 如果希望合并后自动清理 release 分支，必须保持 `delete_branch_on_merge` 为 `true`。
