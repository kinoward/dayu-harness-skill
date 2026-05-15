# Skill 使用效果测试结果

本文件是 docs-governance Skill 自身的执行测试记录，用于后续 Skill 迭代回归，不属于部署给用户项目的治理体系内容。

本记录只保留当前最终基线：空项目启用 Git 约束和非 GitHub 多数能力；已有松散项目启用 Git、GitHub PR/分支保护、质量工具和知识库能力，但跳过 release-please。模板本身不直接运行 Skill；每轮测试都复制到 `tests/unit/.tmp/` 后执行。

## 测试输入

- `skill-empty-template/`：真正的空项目模板。模板内只有 `.gitkeep`，测试复制后删除它，确保运行实例为空目录。
- `skill-messy-template/`：已有 Node CLI 项目模板。它带有代码、测试、松散文档、不完整治理入口、已有 Husky hook、CI 和格式化配置。

## 空项目基线

用户意图：

- 使用 Git，并启用提交约束。
- 不使用 GitHub，不安装 GitHub 相关 workflow、规则集或 release-please 配置。
- 启用质量工具、AI 协作说明、ADR、排障、研究记录、项目文档区和归档区。

能力映射：

```text
core, git.commit, git.language, quality.tooling,
ai.collaboration, knowledge.adr, knowledge.troubleshooting,
knowledge.research, project.docs, archive.project
```

明确跳过：

```text
github.pr, github.branch-release, github.release-please
```

执行路径：

```bash
cp -R tests/fixtures/skill-empty-template tests/unit/.tmp/<run>/empty-nongithub
rm -f tests/unit/.tmp/<run>/empty-nongithub/.gitkeep
bash scripts/scaffold.sh tests/unit/.tmp/<run>/empty-nongithub --dry-run --enable git.language,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project
bash scripts/scaffold.sh tests/unit/.tmp/<run>/empty-nongithub --apply --enable git.language,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project --strategy merge
```

结果：

- dry-run：`status="clean"`，能力集合为 10 个，自动带出 `core` 和 `git.commit`。
- apply：`status="ok"`，部署后验证通过。
- 未生成 `.github/`、`release-please-config.json`、`.release-please-manifest.json`，符合“不启用 GitHub 相关能力”的选择。

完整结构：

```text
<empty-nongithub>/
├── AGENTS.md
├── CLAUDE.md
├── commitlint.config.cjs
├── eslint.config.js
├── .gitignore
├── .husky/
│   ├── commit-msg
│   ├── pre-commit
│   └── pre-push
├── .lintstagedrc.json
├── .prettierrc
└── docs/
    ├── AGENTS.md
    ├── archive/
    │   ├── AGENTS.md
    │   └── product-specs/
    │       └── AGENTS.md
    ├── design-docs/
    │   ├── AGENTS.md
    │   └── adr-template.md
    ├── exec-plans/
    │   ├── AGENTS.md
    │   ├── active/
    │   │   └── AGENTS.md
    │   └── completed/
    │       └── AGENTS.md
    ├── generated/
    │   └── AGENTS.md
    ├── harness/
    │   ├── AGENTS.md
    │   ├── maintenance.md
    │   ├── guides/
    │   │   ├── AGENTS.md
    │   │   ├── ai-collaboration.md
    │   │   ├── commit-guidelines.md
    │   │   ├── dev-hygiene.md
    │   │   ├── git-language-policy.md
    │   │   └── testing-strategy.md
    │   └── sensors/
    │       ├── AGENTS.md
    │       ├── reviews/
    │       │   └── AGENTS.md
    │       └── scripts/
    │           ├── AGENTS.md
    │           ├── audit.sh
    │           ├── check-consistency.sh
    │           ├── diff-helper.sh
    │           └── validate.sh
    ├── product-specs/
    │   └── AGENTS.md
    ├── references/
    │   ├── AGENTS.md
    │   └── research/
    │       └── AGENTS.md
    └── troubleshooting/
        └── AGENTS.md
```

部署后能力检查：

| 意图 | 检查方式 | 当前结果 |
| --- | --- | --- |
| Git 约束可用 | 构造中文提交信息和 issue trailer 提交信息，执行 `.husky/commit-msg` | 均被拦截 |
| 推送保护可用 | 构造删除 `main` 分支的 pre-push 输入 | 被拦截 |
| 渐进式文档入口可读 | 执行 `audit.sh --json` | 通过 |
| 文档索引一致 | 执行 `check-consistency.sh --json` | 通过 |
| GitHub 能力未安装 | 检查 `.github/` 和 release-please 文件 | 均不存在 |

## 已有松散项目基线

用户意图：

- 保留原有 Node CLI 代码、测试、README、CI、Husky hook 和格式化配置。
- 启用 Git 提交约束、语言约束、GitHub PR 规范、分支/标签保护、质量工具、AI 协作说明、ADR、排障、研究记录、项目文档区和归档区。
- 暂不启用 release-please。
- 对已有 hook 和配置使用 merge/保留策略；入口文档断链和旧文档索引问题由 AI 在用户确认后融合修复。

能力映射：

```text
core, git.commit, git.language, github.pr, github.branch-release,
quality.tooling, ai.collaboration, knowledge.adr,
knowledge.troubleshooting, knowledge.research, project.docs, archive.project
```

明确跳过：

```text
github.release-please
```

执行路径：

```bash
cp -R tests/fixtures/skill-messy-template tests/unit/.tmp/<run>/messy-selected
bash templates/docs/harness/sensors/scripts/audit.sh --json tests/unit/.tmp/<run>/messy-selected
bash scripts/install-husky.sh tests/unit/.tmp/<run>/messy-selected --check
bash scripts/scaffold.sh tests/unit/.tmp/<run>/messy-selected --dry-run --enable git.language,github.pr,github.branch-release,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project
bash scripts/scaffold.sh tests/unit/.tmp/<run>/messy-selected --apply --enable git.language,github.pr,github.branch-release,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project --strategy merge
```

部署后 AI 按用户确认进行的语义融合：

- 将 `CLAUDE.md` 改为 `@AGENTS.md`。
- 将根 `AGENTS.md` 中过时的发布流程断链改为已部署的分支和发布指南。
- 将原有 `docs/notes/decision-log.md` 和 `docs/practices/commit-guidelines.md` 补入 `docs/AGENTS.md`，避免旧文档成为孤儿文档。

结果：

- 初始诊断按预期失败，能发现入口路由、断链、缺少 docs 索引和缺少维护脚本等问题。
- Husky 检查能识别已有 hook，并给出 merge plan。
- dry-run 能识别已有文件冲突。
- apply 使用 merge 策略后保留原项目内容，并补齐治理体系。
- release-please 相关文件没有生成，符合用户选择。

完整结构：

```text
<messy-selected>/
├── AGENTS.md
├── CLAUDE.md
├── README.md
├── commitlint.config.cjs
├── eslint.config.js
├── package.json
├── .gitignore
├── .lintstagedrc.json
├── .prettierrc
├── .github/
│   ├── rulesets/
│   │   ├── protect-main.json
│   │   └── protect-tags.json
│   ├── scripts/
│   │   └── pr_body_structure.py
│   └── workflows/
│       ├── ci.yml
│       ├── issue-lint.yml
│       └── pr-lint.yml
├── .husky/
│   ├── commit-msg
│   ├── pre-commit
│   └── pre-push
├── docs/
│   ├── AGENTS.md
│   ├── overview.md
│   ├── archive/
│   │   ├── AGENTS.md
│   │   ├── old-plan.md
│   │   └── product-specs/
│   │       └── AGENTS.md
│   ├── design-docs/
│   │   ├── AGENTS.md
│   │   └── adr-template.md
│   ├── exec-plans/
│   │   ├── AGENTS.md
│   │   ├── active/
│   │   │   └── AGENTS.md
│   │   └── completed/
│   │       └── AGENTS.md
│   ├── generated/
│   │   └── AGENTS.md
│   ├── harness/
│   │   ├── AGENTS.md
│   │   ├── maintenance.md
│   │   ├── guides/
│   │   │   ├── AGENTS.md
│   │   │   ├── ai-collaboration.md
│   │   │   ├── branch-and-release.md
│   │   │   ├── commit-guidelines.md
│   │   │   ├── dev-hygiene.md
│   │   │   ├── git-language-policy.md
│   │   │   ├── pr-guidelines.md
│   │   │   └── testing-strategy.md
│   │   └── sensors/
│   │       ├── AGENTS.md
│   │       ├── reviews/
│   │       │   ├── AGENTS.md
│   │       │   └── code-review-checklist.md
│   │       └── scripts/
│   │           ├── AGENTS.md
│   │           ├── audit.sh
│   │           ├── check-consistency.sh
│   │           ├── diff-helper.sh
│   │           └── validate.sh
│   ├── notes/
│   │   └── decision-log.md
│   ├── practices/
│   │   └── commit-guidelines.md
│   ├── product-specs/
│   │   └── AGENTS.md
│   ├── references/
│   │   ├── AGENTS.md
│   │   └── research/
│   │       └── AGENTS.md
│   └── troubleshooting/
│       └── AGENTS.md
├── src/
│   └── index.js
└── test/
    └── index.test.js
```

部署后能力检查：

| 意图 | 检查方式 | 当前结果 |
| --- | --- | --- |
| 原项目内容被保留 | 检查 `src/`、`test/`、`README.md`、既有 docs 和 `ci.yml` | 均保留 |
| Git 约束可用 | 构造中文提交信息和 issue trailer 提交信息，执行 `.husky/commit-msg` | 均被拦截 |
| 推送保护可用 | 构造删除 `main` 分支的 pre-push 输入 | 被拦截 |
| 渐进式文档入口可读 | 执行 `audit.sh --json` | 语义融合后通过 |
| 文档索引一致 | 执行 `check-consistency.sh --json` | 语义融合后通过 |
| GitHub PR/分支能力已安装 | 检查 PR/issue workflow 和 ruleset | 均存在 |
| release-please 未安装 | 检查 workflow、config 和 manifest | 均不存在 |

## CI 稳定层 E2E

上述基线已经固化为 [test-skill-interaction-e2e.bats](../unit/test-skill-interaction-e2e.bats)。

覆盖范围：

- 从两个模板复制临时实例，不直接修改模板。
- 回放 AI 问答后的能力选择，不默认启用全部能力。
- 验证 dry-run、apply、merge、部署后检查和语义融合后的结果。
- 验证 Git 约束、渐进式文档读取和跳过能力不会被误部署。

运行方式：

```bash
bats tests/unit/test-skill-interaction-e2e.bats
bats tests/unit
```

CI 依赖：

- `bats`
- `jq`
- 常见 shell 工具：`bash`、`awk`、`perl`、`find`

临时运行实例只写入 `tests/unit/.tmp/`，该目录只保留 `.gitignore`。
