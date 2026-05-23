# Skill 使用效果测试结果

本文件记录 大禹治库 Skill 自身的当前回归基线，不属于部署给用户项目的治理内容。

当前基线覆盖两类项目：

- `skill-empty-template/`：空项目，使用旧 capability id 输入，验证兼容展开到新原子能力。
- `skill-messy-template/`：已有 Node CLI 项目，验证已有 hook、CI、配置和松散文档可以 merge/保留，并补齐新的治理索引。

## 空项目兼容展开基线

用户意图：

- 使用默认 Git 提交格式约束与 .gitignore 约束。
- 跳过 GitHub PR、分支保护和 release 自动化交付能力。
- 启用质量实践、Node 工具；AI 执行/记忆、ADR、排障、研究、项目上下文和归档由默认能力强制部署。

输入仍使用旧 id，以验证兼容层：

```bash
bash scripts/scaffold.sh <empty-nongithub> --dry-run --enable git.commit,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project
bash scripts/scaffold.sh <empty-nongithub> --apply --enable git.commit,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project --strategy merge
```

展开后的能力集合：

```text
core, git.hooks, git.commit-format,
quality.practices, quality.node-tooling, project.gitignore,
ai.execution, ai.memory, knowledge.adr, knowledge.troubleshooting,
knowledge.research, project.context, knowledge.archive
```

关键结果：

- dry-run：`status="needs_initialization"`，`capability_count=13`，环境项提示 `git init` 与 `npm init -y`。
- apply：`status="ok"`，部署后 `validate.sh --json` 通过。
- `.husky/commit-msg` 包含提交格式检查相关 snippet（无自然语言策略）。
- `.husky/pre-commit` 由 `quality.node-tooling` 安装。
- `.husky/pre-push` 未安装，因为未启用 `github.branch-protection` 或 `release.versioning`。
- 旧的语言能力 `repo.language`/`github.language` 已退役；未部署与它们相关的 CI 或本地语言检查。
- 未安装 `github.pr` 的 `pr-lint.yml`。
- release-please workflow、config、manifest 均不存在。

## 环境依赖预检基线（新增）

用户意图：

- 在非 Git 仓库、无 `package.json` 的空项目上先运行依赖前置检查；
- 验证缺失依赖提示后需要用户确认，拒绝则中止；
- 用户确认后执行默认初始化并继续默认能力部署。

关键结果（预期）：

- `bash scripts/ensure-environment.sh <empty-nongithub> --check`：
  - 返回 `needs_initialization` 或 `needs_install` 状态；
  - `summary` / `description_nl` 明确给出 `git init` 与 `npm init -y` 建议（按实际场景可选）；
  - `items` 列出 `git`、`npm` 等依赖项的状态与缺失原因。
- 用户拒绝初始化时，流程停止，不执行 `scaffold.sh`。
- 用户同意后，`scaffold.sh --apply` 可继续执行并按默认能力生成项目骨架；`package.json` 通过 `npm init -y` 生成而非模板手写。

## 已有松散项目基线

该场景主要用于验证“治理状态不完整”而非文档语法问题。

用户意图：

- 保留原有 Node CLI 代码、测试、README、CI、Husky hook 和格式化配置。
- 启用默认 Git 提交格式、.gitignore、AI 能力和知识库能力，并额外启用 GitHub PR 规范、分支保护、版本/tag 保护和质量能力。
- 暂不启用 `github.release-please`。
- 对已有 hook 和配置使用 `merge`，入口文档断链和旧文档索引由 AI 在用户确认后融合。

输入：

```bash
bash scripts/scaffold.sh <messy-selected> --dry-run --enable git.commit,github.pr,github.branch-release,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project
bash scripts/scaffold.sh <messy-selected> --apply --enable git.commit,github.pr,github.branch-release,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project --strategy merge
```

展开后的能力集合：

```text
core, git.hooks, git.commit-format,
github.pr, github.branch-protection, release.versioning,
quality.practices, quality.node-tooling, project.gitignore,
ai.execution, ai.memory, knowledge.adr, knowledge.troubleshooting,
knowledge.research, project.context, knowledge.archive
```

部署后 AI 按用户确认进行的语义融合：

- 将 `CLAUDE.md` 改为 `@AGENTS.md`。
- 将根 `AGENTS.md` 中过时的发布流程断链改为 `docs/harness/guides/release-versioning.md`。
- 将原有 `docs/notes/decision-log.md` 和 `docs/practices/commit-guidelines.md` 补入 `docs/AGENTS.md`，避免旧文档成为孤儿文档。

关键结果：

- 初始诊断按预期失败，能发现入口路由、断链、缺少 docs 索引和缺少维护脚本等问题。
- Husky 检查识别已有 hook，并给出 merge plan。
- dry-run 顶层优先返回 `needs_initialization`，同时保留已有文件冲突明细。
- apply 使用 merge 策略后保留原项目内容，并补齐治理体系。
- `pr-lint.yml`、`protect-main.json`、`protect-tags.json` 均存在。
- `github.release-please` 未启用，因此 `release-please.yml`、`release-please-config.json`、`.release-please-manifest.json` 均不存在。
- `.husky/commit-msg` 校验 Conventional Commits；`.husky/pre-push` 分别拦截 `main` 直推/删除和删除 `v*` release tag。
- `validate.sh --json`、`audit.sh --json`、`check-consistency.sh --json` 均通过。

## CI 稳定层 E2E

上述基线固化在 [test-skill-interaction-e2e.bats](../unit/test-skill-interaction-e2e.bats)。

覆盖范围：

- 从 fixture 模板复制临时实例，不直接修改模板。
- 回放 AI 问答后的能力选择，并验证旧 id 兼容展开。
- 验证 dry-run、apply、merge、部署后检查和语义融合后的结果。
- 验证原子能力边界：未启用的 hook、workflow、ruleset 或 release-please 文件不会被误部署。
- 验证默认中文部署与英文部署的治理产物等价性：文件树一致、Git 约束存在、GitHub 约束不存在、部署后检查结果一致，非语言机器文件保持一致。

## GitHub 远端能力边界验证基线（2026-05-23）

该基线来自真实测试会话和后续修复，不属于目标项目部署模板。测试输入包括：

- 测试会话历史：`/Users/wangda/.claude/projects/-Users-wangda-github-kino-test-skill-tmp-9/ad6964c7-aa1a-47a5-b4b8-baf8ac395178.jsonl`
- 测试项目：`/Users/wangda/github-kino/test-skill-tmp-9`
- 标杆项目：`/Users/wangda/github-kino/youtube-translate-tools`

修复后应满足的行为：

- `scaffold.sh --apply --github-remote apply` 在无法解析 GitHub repository，或远端 preflight 需要用户处理时，必须在写入治理文件前返回 `needs_user_action`，避免本地 partial apply 后误报远端 E2E 成功。
- `capability-smoke` 覆盖正反两类路径：commit-msg hook、pre-push 默认分支保护、pre-push release tag 保护、PR body validator、Issue dependency validator、TDD policy validator、release-please policy validator。
- `remote-smoke` 在 disposable GitHub repo 中先验证错误 Issue/PR 会被 workflow 拒绝，再验证合规 Issue/PR 通过、合并后 Issue 自动关闭，并确认测试分支被清理。
- `remote-release` 在 disposable GitHub repo 中验证 `docs:`/`chore:` 不发版，再用两次 releasable commit 推进版本，确认 tag、GitHub Release、Release PR 和 `release-please--*` 分支状态符合预期。
- 远端 profile 默认必须具备 `delete_repo` scope 才能创建 disposable repo；缺少该权限时应在创建仓库前停止。若显式设置 `DAYU_KEEP_REMOTE_REPO=1`，调用者需要承担后续清理责任。

当前测试项目状态核对：

- `/Users/wangda/github-kino/test-skill-tmp-9` 本地工作区为 `main...origin/main`，无未提交变更。
- 远端 heads 只保留 `refs/heads/main`。
- GitHub open PR 列表为空，open Issue 列表为空。
- GitHub 历史中的 closed PR、closed Issue 和失败 workflow run 属于审计历史；若需要完全空白的测试仓库，只能删除并重建仓库。

已知一次性远端残留：

- `kinoward/dayu-harness-remote-smoke-1779503157`
- `kinoward/dayu-harness-remote-release-1779503157`

这两个仓库由修复前的真实远端 profile 尝试创建。最后核对时两者仍存在，但 open PR 和 open Issue 均为空；未删除的原因是当前 GitHub CLI token 缺少 `delete_repo` scope。对应本地 `mktemp` 项目目录格式为 `${TMPDIR:-/tmp}/dayu-remote-smoke.XXXXXX/project` 和 `${TMPDIR:-/tmp}/dayu-remote-release.XXXXXX/project`，最后核对时 `/var/folders` 与 `/tmp` 下未发现残留目录。

本轮修复后的本地验证命令：

```bash
git diff --check
bash -n scripts/scaffold.sh
bash -n scripts/github-remote.sh
bash -n scripts/ensure-environment.sh
bash -n tests/smoke/dayu-harness-profile.sh
python3 -m py_compile assets/github/scripts/issue_depends_on.py
bats tests/unit/test-github-helper-scripts.bats
bats tests/unit/test-skill-interaction-e2e.bats
bats tests/unit/test-audit.bats
bash scripts/check-i18n-drift.sh --json
bash tests/smoke/dayu-harness-profile.sh --profile local-fast --json
```

## Claude CLI 双语部署 Smoke 基线

该基线来自真实 Claude Code CLI 交互测试，已沉淀为 [claude-i18n-deploy-smoke.sh](../smoke/claude-i18n-deploy-smoke.sh) 和 [compare-i18n-deployments.sh](../helpers/compare-i18n-deployments.sh)。

测试意图：

- 新建两个空临时目录。
- 通过 Claude Code CLI 执行 `/dayu-harness`。
- 一个目录选择中文 `zh-CN`，另一个目录明确选择英文 `en`。
- 保留默认 Git 约束，包括 `.husky/commit-msg`、`commitlint.config.cjs`、`.gitignore`。
- 不启用任何 `github.*` 约束，根目录不得生成 `.github/`。
- 部署后运行 `validate.sh --json`、`audit.sh --json`、`check-consistency.sh --json`。
- 排除 `.git/`、`node_modules/`、Claude 日志和交互记录后，比较两套治理产物是否只有语言差异。

默认 CI 不直接运行 Claude CLI，因为它依赖本机认证、网络和权限提示。维护者需要显式开启：

```bash
RUN_CLAUDE_I18N_SMOKE=1 tests/smoke/claude-i18n-deploy-smoke.sh
RUN_CLAUDE_I18N_SMOKE=1 bats tests/unit/test-skill-interaction-e2e.bats
```

运行方式：

```bash
bats tests/unit/test-skill-interaction-e2e.bats
bats tests/unit
```

CI 依赖：

- `bats`
- `jq`
- 常见 shell 工具：`bash`、`awk`、`find`

临时运行实例只写入 `tests/unit/.tmp/`，该目录只保留 `.gitignore`。
