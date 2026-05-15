# 分支保护规约

> 触发时机：创建分支、推送分支、合并 PR 或调整仓库分支保护时读取。

## 分支策略

- 禁止直接提交到 `main` / `master`
- 从主分支创建功能分支，使用 `feat/`、`fix/`、`docs/`、`chore/` 等前缀
- 所有变更通过 PR 合并到主分支
- 如启用 `repo.language`，分支名使用英文

默认推荐 GitHub Flow：从主分支创建短命 feature branch → PR → 合并 → 删除分支。

## 合并策略

| 策略 | 命令 | 适用场景 |
|------|------|---------|
| merge commit | `gh pr merge --merge` | 多人协作，保留完整 commit 历史 |
| squash | `gh pr merge --squash` | 小功能，压缩为单 commit |
| rebase | `gh pr merge --rebase` | 个人项目，线性历史 |

默认使用 merge commit。若启用 release-please，子 commit 遵循 Conventional Commits，PR 标题使用自然语言，避免重复 changelog 条目。

## 合并后清理

```bash
git checkout main
git pull origin main
```

## 保护规则

主分支保护：
- 禁止删除
- 禁止任何本地直推，包括 fast-forward push 和 non-fast-forward push
- 必须通过 PR 合并

实施方式：
- 本地：`.husky/pre-push` 中的 branch protection snippet 拦截 `main` / `master` 直推
- 远程：GitHub ruleset `protect-main.json`
