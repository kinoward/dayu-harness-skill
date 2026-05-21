# PR 提交规范

> 触发时机：创建 PR 时读取

## PR 标题

PR 标题是给人和工具的可读摘要，允许使用中文、英文或项目成员的母语。确保标题是自然语言、可读且能复现变更价值。

要求：
- 长度至少 5 字符
- 建议使用自然语言描述性标题
- 如项目使用 release-please 且采用 merge commit 策略，标题不得使用 conventional commit 格式，以避免 changelog 重复条目

## PR 正文模板

三段结构 + Issue 关联 trailer：

```markdown
## 概要
<!-- dayu-harness:summary -->

可见标题可使用任意语言；machine-check 兼容旧有英文形式。

<!-- What does this PR do? 1-3 bullet points. -->

-

## 实施说明
<!-- dayu-harness:implementation-notes -->

<!-- Key decisions, trade-offs, discovered TODOs. -->

-

## 测试计划
<!-- dayu-harness:test-plan -->

<!-- Each bullet MUST start with - [ ] and contain a backtick-enclosed
     command on the same line. -->

- [ ] `command or inline check`

Closes #<issue-number>  # 或 Fixes/Resolves
```

关键规则：
- **按顺序保留 H2 section 或 marker**：`## Summary` / `<!-- dayu-harness:summary -->`，`## Implementation notes` / `<!-- dayu-harness:implementation-notes -->`，`## Test plan` / `<!-- dayu-harness:test-plan -->`
- **Machine check 兼容旧模板**：允许旧英文标题或新 marker 形式。机器校验以本顺序识别。
- **`Closes #N` / `Fixes #N` / `Resolves #N` 之一必须作为单独行**
- **Test plan 至少一条 bullet**，每条以 `- [ ]` 开头，并在同一行包含反引号包裹的可执行命令

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
    - **分支未推送** → `git push -u origin <branch>`
    - **网络/认证错误** → 重试，连续 3 次失败报告用户
3. 重新执行 `gh pr create`

## 创建后

- Test plan 执行：项目已启用 `ai.execution`，按 AI 执行规约中的 Test plan 规则逐项验证
- 合并策略：项目已启用 `github.branch-protection`，按分支保护规约中的合并策略执行

## PR 合并

使用 `gh pr merge <PR-number> --merge`（merge commit），PR 内所有子 commit 完整保留进入默认分支（`__DAYU_DEFAULT_BRANCH__`）。

合并后清理：
```bash
git checkout __DAYU_DEFAULT_BRANCH__
git pull origin __DAYU_DEFAULT_BRANCH__
```

合并失败自动重试：
1. **合并冲突** → 切换到 PR 分支，rebase `__DAYU_DEFAULT_BRANCH__` 解决冲突后重新推送
2. **CI check 未通过** → 等待或修复
3. **权限不足** → 报告用户
4. **网络错误** → 重试，连续 3 次失败报告用户
