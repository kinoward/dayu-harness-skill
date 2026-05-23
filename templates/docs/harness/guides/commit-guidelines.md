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

## 固定格式生成

Commit message 属于固定格式内容。AI 不应只凭自由文本拼写最终提交信息；应优先使用确定性工具生成或校验：

```bash
docs/harness/sensors/scripts/dayu-format.mjs commit-message \
  --type test \
  --scope harness \
  --subject "verify deployment smoke checks"
```

也可以使用成熟 CLI，例如 Commitizen/cz-git 交互式生成 Conventional Commits，再由 commitlint 校验。模型负责判断 type/scope/subject 的语义是否合适，不负责绕过格式工具。

## 提交原则

- 按逻辑变更拆分 commit，每个 commit 仅含单一职责
- 禁止直接向默认分支（`__DAYU_DEFAULT_BRANCH__`）提交
- 所有变更通过功能分支 + PR 合并到默认分支（`__DAYU_DEFAULT_BRANCH__`）

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
