# release-please 自动发布

> 触发时机：启用或维护 GitHub release-please 自动发布工作流时读取。

## 工作流

release-please 根据 Conventional Commits 自动生成 release PR、版本号和 changelog。release PR 合并后创建 tag 和 GitHub Release。

部署文件：
- `.github/workflows/release-please.yml`
- `.github/release-please-policy.json`
- `release-please-config.json`
- `.release-please-manifest.json`
- `.github/scripts/release_please_policy.py`

## 前置条件

- 启用 `git.commit-format`，让 release-please 能解析提交类型
- 普通 PR 由 `github.pr` 检查；release-please PR 在可放行名单内会跳过 PR Lint，由 release workflow 与 `release-please-policy` 负责发布安全边界
- 启用 `release.versioning`，让版本号和标签保护有明确规则
- 启用 `github.repository-settings`，用于补齐仓库端策略前置要求
- GitHub Actions workflow permissions 必须为 `default_workflow_permissions=write`，并设置 `can_approve_pull_request_reviews=true`
- release workflow 使用 `secrets.GITHUB_TOKEN`，不需要额外配置 PAT secret

使用 `GITHUB_TOKEN` 的目的，是让 release PR 不触发 Dayu 自带 PR/Issue/TDD CI，也不触发依赖 token 派生事件的后续 workflow。发布闭环由同一个 release workflow 在 release PR 合并后触发 `workflow_dispatch mode=publish` 完成。

`VERSION` 保持纯文本格式。release workflow 在自动合并 release PR 前读取 release PR 内 `.release-please-manifest.json` 的根版本，并把该版本写回 `VERSION` 后再重新执行 release 文件 allowlist 校验。不要依赖 `release-please-config.json` 的 `extra-files` 更新纯文本 `VERSION`。

release workflow 对 release PR 的 clone/push 使用 Git credential helper 注入 `GITHUB_TOKEN`，不得恢复为内联 `git -c http.extraheader=...`。合并 release PR 时必须使用 PR 标题作为 `--subject`、传入 `--body ""`，并在合并确认后显式删除 release 分支，避免认证失败、分支残留和 changelog 重复条目。

默认允许以下 actor 触发 release-please 自动合并与 PR lint 跳过：
- `github-actions[bot]`
- `release-please[bot]`

不允许通过普通 PAT owner 或额外 actor 变量扩展 release PR 放行范围。release PR 必须来自同仓库、目标默认分支、匹配 `release-please--` 分支前缀，并且只修改 `.github/release-please-policy.json` 允许的 release 文件。

`release-please` 工作流不再依赖 `autorelease` 标签作为放行条件，label gate（如 `pull_request_target` + `labeled`）不可恢复。

## Changelog 策略

`release-please-config.json` 默认保留完整 Conventional Commit 类型：
- `feat`
- `fix`
- `perf`
- `refactor`
- `revert`
- `docs`
- `style`
- `test`
- `build`
- `ci`
- `chore`

这些类型不应配置为 `hidden: true`。`release_please_policy.py` 会拒绝隐藏 changelog section，确保 changelog 和 GitHub Release notes 保留完整历史记录。

## 路径过滤策略

`release-please` 的变更过滤与路径策略由 `.github/release-please-policy.json` 维护。变更策略（包含路径白名单、排除规则、发布边界）应通过该文件调整，更新后与 `release-please-config.json` 同步应用，避免在配置中重复编码业务策略。

## Issue 关闭位置

Issue closing keyword 只放 PR body，不放单个 commit message。项目已启用 `github.pr`：PR body validator 会检查 `Closes #N` / `Fixes #N` / `Resolves #N` trailer。
对可跳过 PR lint 的 release-please PR，发布安全边界由 release workflow 与 `release-please-policy` 约束。
