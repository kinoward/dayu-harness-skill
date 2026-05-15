# Git 提交规范

> 触发时机：创建或修改 commit 时读取

## Commit Message 格式

遵循 Conventional Commits 格式：

```
type(scope): description
```

- **type**（必选）：`feat` | `fix` | `docs` | `style` | `refactor` | `perf` | `test` | `build` | `ci` | `chore` | `revert`
- **scope**（可选）：模块名
- **description**：简洁可读即可，不要求特定语言或大小写风格。

示例：
- `feat(transcribe): add YouTube auto-caption download`
- `fix: resolve encoding issue in subtitle output`
- `docs: update API usage instructions`
- `chore: add gitignore`

## 提交原则

- 按逻辑变更拆分 commit，每个 commit 仅含单一职责
- 禁止直接向 main 分支提交
- 所有变更通过功能分支 + PR 合并到 main

## 自动化校验

项目使用 husky + commitlint 在本地拦截不符合规范的 commit。

- husky hook：`.husky/commit-msg`
- commitlint 配置：`commitlint.config.cjs`，使用 `@commitlint/config-conventional` 预设

## 提交失败自动重试

当 `git commit` 被 commitlint 或 commit-msg hook 拒绝时：

1. 读取错误输出
2. 根据错误类型修正：
   - **格式错误**（type 不合法 / 缺 description）→ 改写符合 Conventional Commits
   - **格式错误**（subject 为空 / 标点或空行问题）→ 调整 subject 与 body，使格式可被 commitlint 校验通过
3. 重新执行 `git commit`
