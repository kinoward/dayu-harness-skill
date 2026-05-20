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
- 仓库配置 `secrets.RELEASE_TOKEN`
- `.github/release-please-policy.json` 中设置 `workflow.allowed_actors_variable`（默认：`RELEASE_PLEASE_ALLOWED_ACTORS`）

建议使用 PAT (`secrets.RELEASE_TOKEN`) 而不是默认 `GITHUB_TOKEN`，因为 release-please 创建的 PR 通常需要触发后续 CI checks。

默认允许以下 actor 触发 release-please 自动合并与 PR lint 跳过：
- `github-actions[bot]`
- `release-please[bot]`
- 仅可通过 `RELEASE_PLEASE_ALLOWED_ACTORS` 增补其他允许的 PAT/人类账号（用逗号分隔）或明确的 bot 账号名。

如果 release PR 的作者是普通 PAT owner（不是 bot），必须在仓库变量 `RELEASE_PLEASE_ALLOWED_ACTORS` 配置对应用户名（`,` 分隔），否则不会触发 release-please 自动合并和 PR lint 跳过。

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

Issue closing keyword 只放 PR body，不放单个 commit message。若启用 `github.pr`，PR body validator 会检查 `Closes #N` / `Fixes #N` / `Resolves #N` trailer。
对可跳过 PR lint 的 release-please PR，发布安全边界由 release workflow 与 `release-please-policy` 约束。
