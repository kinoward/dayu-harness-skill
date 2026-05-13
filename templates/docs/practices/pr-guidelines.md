# PR 提交规范

> 触发时机：创建 PR 时读取

## 语言

PR 标题、body、评论一律使用英文。详见 [git-language-policy.md](git-language-policy.md)。

## PR 标题

PR 标题必须是自然语言描述性标题，建议使用首字母大写的 Title Case 或自然英文短句，清晰概括 PR 价值。

示例对照：

| 违规 | 合规 |
|---------|---------|
| `feat: add phase 4 auto-skip` | `Phase 4 Smart Auto-Skip and Importance Heatmap` |
| `fix: resolve encoding issue` | `Fix Subtitle Encoding for Non-UTF-8 Sources` |
| `docs: update pr guidelines` | `Rewrite PR Guidelines for Merge-Commit Workflow` |

要求：
- 长度至少 5 字符
- 建议使用自然语言描述性标题
- 如项目使用 release-please 且采用 merge commit 策略，标题不得使用 conventional commit 格式，以避免 changelog 重复条目

## PR 正文模板

三段结构 + Issue 关联 trailer：

```markdown
## Summary

<!-- What does this PR do? 1-3 bullet points. -->

-

## Implementation notes

<!-- Key decisions, trade-offs, discovered TODOs. -->

-

## Test plan

<!-- Each bullet MUST start with - [ ] AND contain an inline command or
     be followed by a fenced code block. -->

- [ ] `command or inline check`

Closes #<issue-number>  # 或 Fixes/Resolves
```

关键规则：
- **按顺序保留 H2 section**：`## Summary` / `## Implementation notes` / `## Test plan`
- **`Closes #N` / `Fixes #N` / `Resolves #N` 之一必须作为单独行**
- **Test plan 至少一条 bullet**，每条以 `- [ ]` 开头，内含可执行命令或 fenced code block

## 禁止 AI 工具签名

PR body 不得包含 AI 工具的署名水印：
- `Generated with [Claude Code]`
- `Co-Authored-By: Claude ...`
- `Generated with Cursor / Copilot / ...`

## 创建失败自动重试

当 `gh pr create` 失败时：

1. 读取错误输出
2. 根据错误类型修正：
   - **标题格式错误** → 改写为自然语言描述性标题
   - **标题过短** → 补全为至少 5 字符
   - **标题或 body 含中文字符** → 翻译为英文
   - **分支未推送** → `git push -u origin <branch>`
   - **网络/认证错误** → 重试，连续 3 次失败报告用户
3. 重新执行 `gh pr create`

## 创建后

- Test plan 执行：参见 [ai-collaboration.md](ai-collaboration.md) 中的「Test plan 执行与汇报」章节
- 合并策略：参见 [branch-and-release.md](branch-and-release.md) 中的「合并策略」章节

## PR 合并

使用 `gh pr merge <PR-number> --merge`（merge commit），PR 内所有子 commit 完整保留进入 main 分支。

合并后清理：
```bash
git checkout main
git pull origin main
```

合并失败自动重试：
1. **合并冲突** → 切换到 PR 分支，rebase main 解决冲突后重新推送
2. **CI check 未通过** → 等待或修复
3. **权限不足** → 报告用户
4. **网络错误** → 重试，连续 3 次失败报告用户
