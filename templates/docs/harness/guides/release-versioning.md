# 版本与标签规约

> 触发时机：制定版本号、创建 release tag、发布版本或调整标签保护时读取。

## 版本号规范

遵循 Semantic Versioning 2.0.0：

```text
v<MAJOR>.<MINOR>.<PATCH>
```

| 变更类型 | 版本号 | 说明 |
|---------|--------|------|
| BREAKING CHANGE | 主版本 +1 | 不兼容的 API 修改 |
| feat | 次版本 +1 | 向后兼容的功能新增 |
| fix | 修订号 +1 | 向后兼容的问题修复 |

pre-release 和 build metadata 按 SemVer 规范附加。

## 手动发布流程

无自动发布工作流时：

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

发布说明应聚焦用户可见变更；纯 docs、ci、chore 类内部变更不应污染面向用户的 changelog。

## 标签保护

发布标签：
- 使用 `v*` 命名
- 禁止删除
- 禁止覆盖已有标签

实施方式：
- 本地：`.husky/pre-push` 中的 release versioning snippet
- 远程：GitHub ruleset `.github/rulesets/protect-tags.json`

### 规则集应用方式

```bash
gh auth login
gh api -X POST "repos/$OWNER/$REPO/rulesets" --input .github/rulesets/protect-tags.json
```

Web UI：Settings → Rules → Rulesets → New ruleset → Import a ruleset → 上传 `protect-tags.json`。

如规则更新，重新导入新的 JSON 即可替换版本；建议保留文件提交到仓库用于团队复用。
