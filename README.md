# docs-governance

帮助项目建立和维护渐进式披露的 AI 工程约束文档体系。

设计哲学源自 [Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/)——人类设计约束，智能体写代码。这套文档体系将 HE 六大概念落地为可部署的工程工件。

## 功能概述

本 Skill 是一个**一次性引导工具**，帮助项目低成本接入 Harness Engineering 理念。以 AGENTS.md 为根的渐进式披露文档体系，将 HE 六大概念——仓库即记录系统、地图而非手册、机械化执行、智能体可读性、熵管理、人类掌舵——落地为可部署、可验证的工程工件。初始化完成后，Skill 可安全删除——项目的约束体系已独立运行。

核心能力：
- **脚手架**：在新项目中从零建立 AGENTS.md + docs/ 文档体系
- **融合**：与已有文档体系合并，保留现有内容，补全缺失
- **诊断**：检查现有体系的完整性和一致性
- **维护**：增删改约束、更新项目文档
- **生成**：根据项目特征智能生成适配内容
- **强制执行**：AI 署名剥离、issue 引用拦截、Conventional Commits 校验等自动化约束
- **release-please CI/CD**：Google release-please 自动化版本发布工作流

## 项目结构

```
.claude/skills/docs-governance/
  README.md                 # 本文件
  SKILL.md                  # Skill 行为定义
  AGENTS.md                 # Skill 自身渐进式披露入口
  Q&A-TEMPLATE.md           # Q&A 参考模板

  docs/                     # Skill 自身文档
    plan.md                 # 设计计划
    AGENTS.md               # Skill 文档入口
    optimization-2026-05.md # 2026-05 优化记录

  templates/                # 文档模板（部署到目标项目）
    CLAUDE.md
    AGENTS.md
    docs/
      AGENTS.md
      doc-maintenance.md
      practices/            # 8 个工程规范
        AGENTS.md
        ai-collaboration.md
        branch-and-release.md
        code-review-checklist.md
        commit-guidelines.md
        dev-hygiene.md
        git-language-policy.md
        pr-guidelines.md
        testing-strategy.md
      decisions/            # ADR 决策记录
        AGENTS.md
        adr-template.md
      troubleshooting/      # 排障知识库
        AGENTS.md
      research/             # 版本化研究院
        AGENTS.md
      project/              # 项目专属内容
        AGENTS.md
      archive/              # 历史归档
        AGENTS.md
        project/
          AGENTS.md
      scripts/              # 维护脚本
        audit.sh
        check-consistency.sh
        diff-helper.sh
        validate.sh

  assets/                   # 脚本和配置资产（按用户选择部署）
    husky/                  # Git hooks（commit-msg + pre-commit + pre-push）
      commit-msg
      pre-commit
      pre-push
    commitlint/             # Commitlint 配置
      commitlint.config.cjs
    github/                 # GitHub workflows + rulesets + CI 脚本
      workflows/
        issue-lint.yml
        pr-lint.yml
        release-please.yml
      rulesets/
        protect-main.json
        protect-tags.json
      rulesets.md
      release-please-config.json
      .release-please-manifest.json
      scripts/
        pr_body_structure.py
    eslint/                 # ESLint 配置
      eslint.config.js
    prettier/               # Prettier 配置
      .prettierrc
    lint-staged/            # lint-staged 配置
      .lintstagedrc.json
    gitignore/              # .gitignore 模板
      node.gitignore
      python.gitignore
      universal.gitignore

  scripts/                  # 初始化脚本（仅 Skill 内部使用）
    scaffold.sh
    install-commitlint.sh
    install-eslint.sh
    install-github-workflows.sh
    install-gitignore.sh
    install-husky.sh
    install-lint-staged.sh
    install-prettier.sh

  tests/                    # Skill 自身测试
    unit/                   # bats 单元测试
    fixtures/               # 5 个测试夹具项目
```

## 安装与删除

### 安装

仅在**项目级别**安装此 Skill，不要在全局安装：

```
# 将整个 docs-governance/ 目录放到目标项目的 .claude/skills/ 下
cp -r docs-governance/ <target-project>/.claude/skills/
```

### 删除

初始化完成后，此 Skill 可**安全删除**：

```
rm -rf .claude/skills/docs-governance/
```

项目的治理体系（AGENTS.md + docs/ + 已安装的脚本资产）独立存在，不受 Skill 删除影响。`doc-maintenance.md` 包含所有维护所需的知识，AI 仅凭项目文档即可执行后续维护操作。

Skill 的后续版本更新对已完成初始化的项目没有影响。如需新增初始化时跳过的约束，重新安装最新版 Skill 执行即可。

## 使用方式

Skill 存在时，通过 `/docs-governance` 显式命令激活。Skill 不在日常 AI 协作中自动介入。

Skill 删除后，AI 读取项目中的 `doc-maintenance.md` 自行处理所有维护意图。

## 参考引用

- [OpenAI — Harness Engineering](https://openai.com/zh-Hans-CN/index/harness-engineering/) — 本 Skill 的设计哲学来源
- [Martin Fowler — Harness Engineering](https://martinfowler.com/articles/harness-engineering.html) — Guides × Sensors 控制论框架
- [agentsmd/agents.md](https://github.com/agentsmd/agents.md) — AGENTS.md 开放格式规范，本项目的文档体系根节点遵循此标准
- [microsoft/skills](https://github.com/microsoft/skills) — 微软官方的 Skills、MCP servers、Agents.md 集合
- [agent-sh/agnix](https://github.com/agent-sh/agnix) — AGENTS.md / CLAUDE.md / SKILL.md 的 linter 和 LSP，与诊断功能互补
