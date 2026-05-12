# Git 与远程仓库语言规约

> 触发时机：创建或修改 commit、PR、issue、release notes、branch 时必读

## 硬性规则

git 与远程仓库（GitHub）相关的所有内容一律使用英文。

## 适用对象

必须使用英文：

| 对象 | 范围 |
|------|------|
| Commit message | subject + body + footer（含 `BREAKING CHANGE:` 等） |
| Branch 名 | 本地分支与远程分支 |
| PR 标题 | 含 release-please 自动 PR |
| PR 描述 | 正文全部内容，含章节名与列表项 |
| PR 评论 | 所有人工评论 |
| Issue 标题与描述 | 正文全部内容 |
| GitHub Release notes | 由 CHANGELOG 派生 |
| CHANGELOG.md | 由 release-please 从 commit 派生 |
| Tag annotation | `git tag -a` 的 message |

不适用本规约：

| 对象 | 语言 |
|------|------|
| `docs/**` 内所有文档 | 中文 |
| 源代码注释 / docstring | 不纳入本规约 |
| `README.md` 等根目录说明性文件 | 不纳入本规约 |

## 示例

```
# OK
feat(server): add startup model download
docs: update API usage instructions

# NG
feat(server): 启动期自动下载模型
docs: 更新使用说明
```

## CJK 检测原理

检测基于 Unicode 范围匹配，覆盖以下字符区间：

| 字符类型 | Unicode 范围 | 说明 |
|---------|-------------|------|
| 中文汉字 | `\x{4e00}-\x{9fff}` | CJK Unified Ideographs |
| 日文平假名 | `\x{3040}-\x{309f}` | Hiragana |
| 日文片假名 | `\x{30a0}-\x{30ff}` | Katakana |
| 韩文 | `\x{ac00}-\x{d7af}` | Hangul Syllables |
| 中文标点 | `\x{3000}-\x{303f}` | CJK Symbols and Punctuation |
| 全角字符 | `\x{ff00}-\x{ffef}` | Halfwidth and Fullwidth Forms |

hook 中使用 `grep -P`（PCRE）进行匹配；CI 环境使用等效的 Python/JS 正则。

## 强制手段

双重校验——本地 hook 实时拦截 + 远程 CI 合并门禁：

### 层一：本地 hook

`.husky/commit-msg` 在 commit 时检测 CJK 字符，拦截含中文的 commit message。CJK 检测与 Conventional Commits 校验共享同一个 hook 文件。

### 层二：CI 远程校验（GitHub Actions 可用时）

| CI 检查 | 文件 | 作用 |
|--------|------|------|
| PR 标题/body | `.github/workflows/pr-lint.yml` | 检测 CJK 字符，含中文则 fail check |
| Issue 标题/body | `.github/workflows/issue-lint.yml` | 检测 CJK 字符，含中文则自动标记 `needs-english` 并评论引导 |

### 无 CI 环境

- 本地 `.husky/commit-msg` hook 拦截含中文的 commit message
- PR/Issue 内容依赖人工检查和 AI 自觉遵循

## 例外处理

以下场景允许临时绕过 CJK 检测：

- 在 commit message 或 PR body 中添加 `<!-- skip-cjk-check -->` 注释标记（仅当引用中文专有名词或中文文档链接时使用）
- 该标记仅跳过当前项（commit 或 PR），不影响其他检查
- 滥用此标记应在 code review 中被识别和讨论

## 自动重试

AI 执行 `git commit` / `gh pr create` 失败时，若错误指向「含中文字符」：

1. 读取错误输出定位违规位置（hook 输出中会标注具体行号和违规字符）
2. 将该内容翻译为英文，保留语义与技术术语
3. 不改变 commit 类型（feat/fix/docs 等）和 scope
4. 重试命令

同一 commit 重试 2 次后仍失败 → 报告用户并展示无法自动翻译的内容。
