# Git 与远程仓库语言规约

> 触发时机：创建或修改 commit、PR、issue、release notes、branch 时必读

## 硬性规则

Git 与远程仓库（GitHub）相关内容默认使用英文；`docs/**` 文档继续使用中文。

## 适用对象

必须使用英文：

- Commit message（subject、body、footer）
- Branch 名
- PR 标题（含 release-please 自动 PR）
- PR 描述（正文全部内容，含章节名与列表项）
- PR / Issue 评论
- Issue 标题与正文
- GitHub Release notes / tag annotation

不适用本规约：

- `docs/**` 内文档
- 源代码注释与 docstring
- 非 GitHub 交付文档（例如部分 `README.md`）

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

检测基于 Unicode 范围匹配，覆盖以下常见 CJK 区间：

| 字符类型 | Unicode 范围 | 说明 |
|---------|-------------|------|
| 中文汉字 | `\x{4e00}-\x{9fff}` | CJK Unified Ideographs |
| 日文平假名 | `\x{3040}-\x{309f}` | Hiragana |
| 日文片假名 | `\x{30a0}-\x{30ff}` | Katakana |
| 韩文 | `\x{ac00}-\x{d7af}` | Hangul Syllables |
| 中文标点 | `\x{3000}-\x{303f}` | CJK Symbols and Punctuation |
| 全角字符 | `\x{ff00}-\x{ffef}` | Halfwidth and Fullwidth Forms |

本地 hook 与可选 GitHub CI 均使用同一字符区间，确保一致性。

## 强制手段

基础校验由本地 hook 实时拦截；如启用 `github.language`，再追加 GitHub CI 门禁：

### 层一：本地 hook

`.husky/commit-msg` 在 commit 时检测 CJK 字符，拦截含中文的 commit message。CJK 检测由 `repo.language` 能力安装，不依赖 Conventional Commits 校验。

### 层二：CI 远程校验（启用 `github.language` 时）

| CI 检查 | 文件 | 作用 |
|--------|------|------|
| PR 标题/body | `.github/workflows/repo-language-pr-lint.yml` | 检测 CJK 字符，含中文则 fail check |
| Issue 标题/body | `.github/workflows/repo-language-issue-lint.yml` | 检测 CJK 字符，含中文则 fail check |

### 未启用 GitHub CI 时

- 本地 `.husky/commit-msg` hook 拦截含中文的 commit message
- PR/Issue 内容依赖人工检查和 AI 自觉遵循

## 例外处理

以下场景允许临时绕过 CJK 检测（仅用于当前条目）：

- 在 commit message、PR body、Issue body 中添加 `<!-- skip-cjk-check -->` 注释标记
- 标记仅跳过该条目的检查；不会影响其他内容
- 滥用此标记应在 code review 中被识别和讨论

## 自动重试

AI 执行 `git commit` / `gh pr create` 失败时，若错误指向「含中文字符」：

1. 读取错误输出定位违规位置（hook 输出中会标注具体行号和违规字符）
2. 将该内容翻译为英文，保留语义与技术术语
3. 不改变 commit 类型（feat/fix/docs 等）和 scope
4. 重试命令

同一 commit 重试 2 次后仍失败 → 报告用户并展示无法自动翻译的内容。
