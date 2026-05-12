# docs-governance

帮助项目建立和维护渐进式披露的 AI 工程约束文档体系。

## 功能概述

本 Skill 是一个**一次性引导工具**，用于在项目中建立以 AGENTS.md 为根的渐进式披露文档体系。初始化完成后，Skill 的作用大幅减少，可安全删除——项目的治理体系已独立运行。

核心能力：
- **脚手架**：在新项目中从零建立 AGENTS.md + docs/ 文档体系
- **融合**：与已有文档体系合并，保留现有内容，补全缺失
- **诊断**：检查现有体系的完整性和一致性
- **维护**：增删改约束、更新项目文档
- **生成**：根据项目特征智能生成适配内容

## 项目结构

```
.claude/skills/docs-governance/
  README.md                 # 本文件
  skill.md                  # Skill 行为定义
  Q&A-TEMPLATE.md           # Q&A 参考模板

  docs/                     # Skill 自身文档
    plan.md                 # 设计计划

  templates/                # 文档模板（部署到目标项目）
    CLAUDE.md
    AGENTS.md
    docs/
      AGENTS.md
      doc-maintenance.md
      practices/            # 7 个工程规范
      decisions/            # ADR 决策记录
      troubleshooting/      # 排障知识库
      research/             # 版本化研究院
      project/              # 项目专属内容
      archive/              # 历史归档
      scripts/              # 维护脚本

  assets/                   # 脚本和配置资产
    husky/                  # Git hooks（commit-msg + pre-commit + pre-push）
    commitlint/             # Commitlint 配置
    github/                 # GitHub workflows + rulesets JSON + CI scripts
      workflows/
      rulesets/
      scripts/
    eslint/                 # ESLint 配置
    prettier/               # Prettier 配置
    lint-staged/            # lint-staged 配置
    gitignore/              # .gitignore 模板

  scripts/                  # 初始化脚本（仅 Skill 内部使用）
  tests/                    # Skill 自身测试
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

Skill 存在时，通过以下方式激活：

- **显式**：`/docs-governance`
- **隐式**：自然语言描述意图，如「删除提交校验」「检查项目完整性」

Skill 删除后，AI 读取项目中的 `doc-maintenance.md` 自行处理上述意图。
