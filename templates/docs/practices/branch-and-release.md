# 分支与发布管理

> 触发时机：管理分支、合并 PR、发布版本时读取

## 语言

分支名、PR 标题/body、release notes、tag message 一律使用英文。详见 [git-language-policy.md](git-language-policy.md)。

## 分支策略

- 禁止直接提交到 main 分支
- 从 main 创建功能分支，使用 `feat/`、`fix/`、`docs/`、`chore/` 等前缀
- 分支名必须全英文
- 所有变更通过 PR 合并到 main

### 分支策略选择

| 策略 | 特点 | 适用场景 |
|------|------|---------|
| **GitHub Flow** | 单一 main 分支 + 短命 feature 分支 | 持续部署、频繁发布的小团队项目 |
| **Git Flow** | main + develop + feature + release 分支 | 有固定发布周期的多人协作项目 |
| **Trunk-based** | 极短分支（<1天），频繁合并 main | CI/CD 高度自动化的大型团队 |

默认推荐 GitHub Flow：从 main 创建分支 → PR → 合并 → 删除分支。

## 合并策略

| 策略 | 命令 | 适用场景 |
|------|------|---------|
| **merge commit** | `gh pr merge --merge` | 多人协作，保留完整 commit 历史 |
| **squash** | `gh pr merge --squash` | 小功能，压缩为单 commit |
| **rebase** | `gh pr merge --rebase` | 个人项目，线性历史 |

### 选择指南

- 使用 **merge commit** 作为默认策略，PR 内所有子 commit 完整保留进入 main
- 如果项目使用 release-please 且采用 merge commit 策略：子 commit 严格遵循 Conventional Commits，changelog 由子 commit 生成；PR 标题使用自然语言（非 conventional commit 格式）以避免重复 changelog 条目
- PR 合并后 GitHub 自动删除远程源分支

### 合并后清理

```bash
git checkout main
git pull origin main
```

### 合并失败自动重试

1. **合并冲突** → 切换到 PR 分支，rebase main 解决冲突后重新推送，再重试合并
2. **CI check 未通过** → 等待 check 完成或检查失败原因，修复后重试
3. **权限不足** → 报告用户，由人工处理
4. **网络错误** → 直接重试，连续 3 次失败报告用户

## 版本号规范

遵循 [Semantic Versioning 2.0.0](https://semver.org/)：

```
v<MAJOR>.<MINOR>.<PATCH>
```

| 变更类型 | 版本号 | 说明 |
|---------|--------|------|
| BREAKING CHANGE | 主版本 +1 | 不兼容的 API 修改 |
| feat | 次版本 +1 | 向后兼容的功能新增 |
| fix / docs / chore | 修订号 +1 | 向后兼容的问题修复 |

pre-release 和 build metadata 按 SemVer 规范附加。

## 发布流程

### 场景 A：无 CI（手动版本管理）

- 手动维护 `CHANGELOG.md`
- 手动创建 git tag：`git tag -a v1.0.0 -m "Release v1.0.0"`
- 手动推送 tag：`git push origin v1.0.0`

### 场景 B：GitHub Actions + release-please

- release-please-action 自动检测 conventional commit，生成版本号和 CHANGELOG
- 自动创建 release PR，required status check 通过后 GitHub 平台自动合并
- 合并后自动创建 tag 和 Release notes

前置设置：
- 仓库需开启 `allow_auto_merge: true`
- release-please 使用 PAT（`RELEASE_TOKEN`）而非 GITHUB_TOKEN
- 配置路径过滤以避免纯 docs/CI/scripts 变更触发不必要的发版

### 场景 C：语义发布（semantic-release）

- 适用于 Node.js 项目，自动分析 commit 确定版本号
- 与 release-please 功能重叠，选其一即可

## 保护规则

**main 分支**：
- 禁止删除（pre-push hook + GitHub ruleset 双重保护）
- 禁止 non-fast-forward push（force push）
- 必须通过 PR 合并

**发布标签**：
- 禁止删除（pre-push hook 拦截）
- 禁止覆盖已有标签

**实施**：
- 本地：`.husky/pre-push` hook 实时拦截
- 远程：GitHub rulesets 配置（`protect-main.json` + `protect-tags.json`）作为服务端保障
