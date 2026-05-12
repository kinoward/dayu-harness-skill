# GitHub Rulesets 配置指引

本目录包含可直接通过 GitHub API 应用的 ruleset JSON 文件。

## 文件

- [protect-main.json](rulesets/protect-main.json)：保护 `main`/`master` 分支——禁止删除、禁止 force push、要求 PR 合并
- [protect-tags.json](rulesets/protect-tags.json)：保护 `v*` release 标签——禁止删除、禁止覆盖

## 应用方式

### 通过 gh CLI

```bash
# 导入 main 分支保护规则
gh api -X POST "repos/$OWNER/$REPO/rulesets" --input rulesets/protect-main.json

# 导入 tag 保护规则
gh api -X POST "repos/$OWNER/$REPO/rulesets" --input rulesets/protect-tags.json
```

### 通过 GitHub Web 界面

1. 进入仓库 Settings → Rules → Rulesets
2. 选择 "New ruleset" → "Import a ruleset"
3. 上传对应的 JSON 文件

## 启用 auto-merge

```bash
gh api -X PATCH "repos/$OWNER/$REPO" -f allow_auto_merge=true
```

## 说明

- JSON 文件中的 `bypass_actors` 默认为空（仅仓库管理员可绕过）
- `_comment` 字段为人类可读注释，不影响规则生效
- 修改 JSON 文件后需重新导入以更新规则
- 建议将 rulesets JSON 文件纳入版本控制，与项目代码同步演化
