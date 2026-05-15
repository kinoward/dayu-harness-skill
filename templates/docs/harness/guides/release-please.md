# release-please 自动发布

> 触发时机：启用或维护 GitHub release-please 自动发布工作流时读取。

## 工作流

release-please 根据 Conventional Commits 自动生成 release PR、版本号和 changelog。release PR 合并后创建 tag 和 GitHub Release。

部署文件：
- `.github/workflows/release-please.yml`
- `release-please-config.json`
- `.release-please-manifest.json`

## 前置条件

- 启用 `git.commit-format`，让 release-please 能解析提交类型
- 启用 `github.pr`，让 release PR 也遵循 PR 结构和检查
- 启用 `release.versioning`，让版本号和标签保护有明确规则
- 仓库配置 `secrets.RELEASE_TOKEN`

建议使用 PAT (`secrets.RELEASE_TOKEN`) 而不是默认 `GITHUB_TOKEN`，因为 release-please 创建的 PR 通常需要触发后续 CI checks。

## Changelog 策略

`release-please-config.json` 默认只展示用户可见类型：
- `feat`
- `fix`
- `perf`

`docs`、`style`、`refactor`、`test`、`build`、`ci`、`chore` 默认隐藏，避免 changelog 被内部维护变更污染。

## Issue 关闭位置

Issue closing keyword 只放 PR body，不放单个 commit message。若启用 `github.pr`，PR body validator 会检查 `Closes #N` / `Fixes #N` / `Resolves #N` trailer。
