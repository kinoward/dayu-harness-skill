# 计划：构建渐进式披露的 AI 管理和约束文档体系

## Context

从 youtube-translate-tools 提炼经验，构建一个完整的项目治理 Skill `docs-governance`。在当前项目中实现并验证，未来独立成 git 仓库分发。

> 历史说明：本文保留早期设计追溯。当前行为以 `SKILL.md`、`README.md`、`capabilities/*.json` 为准；Skill 仅通过 `/docs-governance` 显式激活；自然语言维护意图由项目 AGENTS/doc-maintenance 体系处理；部署清单以 capability manifest 为单一事实源。

**Skill 定位**：一次性引导工具。帮助项目建立自己的治理体系，初始化完成后作用大幅减少，可安全删除。项目治理体系的演化是内生的，不依赖外部 Skill。

## 核心设计原则

1. **渐进式披露**：CLAUDE.md → AGENTS.md → docs/AGENTS.md → 子目录/AGENTS.md → 具体文档
2. **工程约束 vs 项目内容 二分**：
   - **工程约束**（AI 读取的规则和经验）：`practices/`、`decisions/`、`troubleshooting/`、`research/`、`scripts/`、各级 `AGENTS.md`
   - **项目内容**（项目强相关的产物，非 AI 规则）：`project/`、`archive/project/`
3. **脚本实施为主，文档约束为辅**（约束执行语境）：hooks、configs 以可执行脚本交付（如 husky 本地拦截 commit），文档描述规则和原理。脚本是约束的强制手段，文档是约束的说明
4. **兼容优先，不覆盖**：检测 → 展示 diff + 自然语言描述 → 用户确认 → 合并 → smoke test
5. **能力导向**：从「项目需要什么治理能力」出发，不预设项目类型
6. **项目文档为权威**：项目 AGENTS.md 体系是最终权威。Skill 存在时是辅助工具，Skill 删除后体系独立运行
7. **经验自发沉淀**：AI 对话中产生的经验和总结，主动沉淀到项目体系的对应位置（decisions/、troubleshooting/、research/），项目本身成为 AI 经验的归纳场所
8. **体系自洽，不依赖 Skill**（体系维护语境）：Skill 仅是引导初始化的工具。Skill 删除后，`doc-maintenance.md` 包含所有维护逻辑（新增/删除/修改约束、诊断完整性、Q&A 决策树），AI 仅凭项目文档即可独立执行所有维护操作

> 原则 #3 和 #8 的语境区分：#3 适用于约束的日常执行（如每次 git commit 时 husky hook 强制校验），#8 适用于治理体系的维护操作（如新增/删除约束、诊断完整性）。两者不冲突。

## Skill 边界与优先级

### 边界规则

Skill 存在时：

| 场景 | Skill 角色 |
|------|-----------|
| 项目无 AGENTS.md，首次初始化 | 脚手架工具。创建完成后项目 AGENTS.md 即时生效为权威 |
| 项目已有 AGENTS.md，融合 | 融合工具。经用户确认逐项合并，项目 AGENTS.md 仍为权威 |
| 项目已有 AGENTS.md，日常 AI 协作 | **不介入**。AI 读取项目 AGENTS.md 并遵循 |
| 用户要求修改约束 | 通过自然语言或显式命令激活，协助修改项目文档体系 |

Skill 删除后：

| 场景 | 行为 |
|------|------|
| 日常 AI 协作 | AI 读取项目 AGENTS.md 并遵循，与 Skill 存在时完全一致 |
| 用户要求修改约束 | AI 读取 `doc-maintenance.md` 中的维护逻辑，按流程自行执行 |
| 用户要求诊断完整性 | AI 读取 `doc-maintenance.md` 中的诊断清单，逐项检查并报告 |

### 优先级声明（双重声明）

**skill.md 中**：
> Skill 是管理和维护项目治理体系的工具，不是治理体系本身。项目中以 AGENTS.md 为根的渐进式披露文档体系是最终权威。Skill 帮助创建和维护这套体系，但不替代或凌驾于它。初始化完成后，Skill 可安全删除——项目的治理体系已独立运行。

**模板 CLAUDE.md 中**：
> 本文件是项目级权威入口。外部工具和模板（包括 docs-governance skill）仅作为创建和维护本体系的辅助参考。如发生冲突，以本文件及 docs/ 下的项目文档为准。

### 激活方式

> 历史说明：本段中的隐式激活为早期设计，当前已废弃。

以下激活方式仅在 Skill 存在时有效：

- **显式**：`/docs-governance`（初始化、大改动时）
- **隐式**：自然语言触发。Skill 识别以下意图并自动激活：
  - 添加/删除/修改某种约束或规范
  - 更新项目文档内容
  - 检查项目完整性或诊断问题

Skill 删除后，上述意图由 AI 读取项目中的 `doc-maintenance.md` 自行处理，无需 Skill 介入。

## Skill 完整结构

```
.claude/skills/docs-governance/
  README.md                         # 人类阅读：功能说明、项目结构、使用与删除建议
  skill.md                          # Skill 定义 + 5 模式 + 边界规则 + 激活条件
  Q&A-TEMPLATE.md                   # Q&A 参考模板（skill 根据项目实际状态适配）

  docs/                             # Skill 自身文档（供后续维护参考）
    plan.md                         # 本计划文件

  templates/
    CLAUDE.md                       # 含优先级声明
    AGENTS.md                       # 根索引（≤50行），纯路由
    docs/
      AGENTS.md
      doc-maintenance.md
      practices/                    # [工程约束] 工程规范（按能力模块部署）
        AGENTS.md
        commit-guidelines.md        # ~50行
        pr-guidelines.md            # ~100行
        branch-protection.md        # 分支保护
        release-versioning.md       # 版本与 release tag 规则
        testing-strategy.md         # ~60行
        dev-hygiene.md              # ~80行
        ai-execution.md             # AI 执行规则
        ai-memory.md                # AI 经验沉淀与记忆边界
        git-language-policy.md      # ~100行
      decisions/                    # [工程约束] ADR
        AGENTS.md + adr-template.md
      troubleshooting/              # [工程约束] 排障
        AGENTS.md
      research/                     # [工程约束] 版本化研究
        AGENTS.md
      project/                      # [项目内容] 专属内容
        AGENTS.md
      archive/                      # [归档] 仅预设 project/，其余子目录由项目自行演化
        AGENTS.md
        project/
          AGENTS.md
      scripts/                      # [工程约束] 维护脚本（部署到项目）
        audit.sh                    # 诊断完整性
        validate.sh                 # smoke test
        diff-helper.sh              # diff → 自然语言描述

  assets/                           # 脚本和配置资产（按用户选择部署到项目，未选不部署）
    husky/
      snippets/                     # 按能力安装的 hook 片段
    commitlint/
      commitlint.config.cjs
    github/
      workflows/
        pr-lint.yml
        repo-language-issue-lint.yml
      rulesets.md
    eslint/
      eslint.config.js
    prettier/
      .prettierrc
    lint-staged/
      .lintstagedrc.json
    gitignore/
      node.gitignore / python.gitignore / universal.gitignore

  scripts/                          # Skill 初始化脚本（仅 Skill 内部使用，不部署到项目）
    scaffold.sh                     # 主脚手架
    install-husky.sh
    install-commitlint.sh
    install-github-workflows.sh
    install-eslint.sh
    install-prettier.sh
    install-lint-staged.sh
    install-gitignore.sh

  tests/
    unit/                           # bats 单元测试
    fixtures/                       # 5 个测试夹具
```

### 部署策略

初始化时，**仅部署用户选择的约束**，未选择的内容不复制到项目中：

- `templates/docs/practices/` 中用户启用的文档 → 部署到项目 `docs/practices/`
- `templates/docs/decisions/` 等子目录 → 用户启用则部署
- `templates/docs/scripts/` → **始终部署**（维护脚本是体系基础设施）
- `assets/` 中用户启用的资产 → 部署到项目对应位置（如 husky hooks → `.husky/`）
- `assets/` 中未启用的资产 → **不部署**，保持项目结构精简

后续用户需要新增约束时，重新安装 Skill 执行即可。

### doc-maintenance.md 扩展内容（体系自洽的关键）

除原有内容（层级结构、核心原则、新增流程、语言规则、文件命名）外，扩展以下自维护逻辑：

**约束生命周期管理**：
- 新增约束：确定归属目录 → 创建文档/脚本 → 更新 AGENTS.md 索引 → 更新联动关系
- 修改约束：定位影响的文档+脚本 → 展示变更 → 更新
- 删除约束：分析影响范围（联动链上的其他文档/脚本）→ 移除 → 更新索引

**诊断与完整性检查**：
- 执行 `docs/scripts/audit.sh` 进行自动诊断；Skill 删除后 AI 也可按本节的检查清单手动逐项对比
- 检查清单：各级 AGENTS.md 是否存在且链接有效、联动约束的脚本是否已安装、索引与实际文件是否一致

**Q&A 决策参考**（从 Q&A-TEMPLATE.md 提炼）：
- 15 项治理约束的描述、实施方式、联动关系
- 每项适用条件（Git 项目 / GitHub 项目 / 通用）
- AI 可根据此参考在后续自行重现决策流程

**兼容化处理参考**：
- 执行 `docs/scripts/diff-helper.sh` 生成 diff 和自然语言描述；Skill 删除后 AI 也可按本节流程手动执行
- 检测已有配置 → 生成变更描述 → 用户确认 → 合并的流程说明

### README.md 内容要点

- Skill 功能概述：帮助项目建立渐进式披露的 AI 工程约束文档体系
- 项目结构说明
- **安装建议**：仅在项目中安装此 Skill（`.claude/skills/`），不要在全局安装（`~/.claude/skills/`）
- **删除建议**：初始化完成后，此 Skill 可安全删除。项目的治理体系已独立存在，`doc-maintenance.md` 包含所有维护所需的知识。Skill 的后续版本更新对已完成初始化的项目没有影响

## 5 个模式

| 模式 | 触发 | 行为 |
|------|------|------|
| **脚手架** | 新项目，无 AGENTS.md | 分析项目现状 → 按 Q&A 模板适配提问 → 确认 → 复制模板+安装资产 → smoke test |
| **诊断** | 已有项目 | Skill 存在时用 audit.sh 加速；Skill 删除后 AI 按 doc-maintenance.md 诊断清单逐项检查 |
| **融合** | 已有文档体系 | 诊断现有 → 适配提问 → diff-helper 展示变更 → 逐项确认 → 合并 |
| **维护** | 用户要求增删改约束 | 分析影响范围 → 展示变更 → 确认 → 执行 → 更新索引 |
| **生成** | 需要特定文档/配置 | 根据项目特征和 doc-maintenance.md 中的 Q&A 决策参考，智能生成适配内容 |

### 维护模式子功能

| 子功能 | 行为 |
|--------|------|
| **删除约束** | 定位影响的文档+脚本+联动 → 展示影响范围 → 确认 → 移除 → 更新索引 |
| **修改约束** | 定位文档+脚本 → 展示 diff → 确认 → 更新 |
| **完整性检查** | Skill 存在时用 audit.sh 加速；Skill 删除后按 doc-maintenance.md 诊断清单逐项检查 |
| **更新项目文档** | 按 doc-maintenance 流程 → 更新内容 → 同步索引 |

## Q&A 模板设计（Q&A-TEMPLATE.md）

### 重要：模板是参考，不是绝对流程

Skill 在提问前应**先分析项目现状**（读取已有文件、检查已有配置），然后基于模板生成适配的提问。例如：
- 项目已有 `commitlint.config.cjs` → 不直接问「是否启用提交校验」，而是确认「检测到已有 commitlint，是否保留/增强/跳过」
- 项目已有 `docs/` 但结构不同 → 进入融合模式，逐项确认

### 提问流程（连续，描述优先）

每项 3 选项：[1] 启用 [2] 跳过 [3] 自定义需求

```
Q1: 项目是否使用 Git 版本控制？
    选项：[1] 是 [2] 否 [3] 其他版本控制系统（请描述）

Q2: 是否使用 GitHub 远程托管？
    （仅 Q1=[1] 时）
    选项：[1] 是 [2] 否 [3] 其他托管平台（请描述）

—— 治理约束逐项确认 ——

Q3: 「提交信息格式校验」— git commit 时自动校验 Conventional Commits 格式
    实施：husky + commitlint 本地 hook
    说明：启用后会安装 husky 和 commitlint。Q4 的语言检测将集成到同一个 husky hook 中

Q4: 「Git 内容语言规范」— commit/PR/issue/release notes/branch 名使用英文
    （仅 Q1=[1] 时）
    实施：husky hook 本地拦截 + 可选 GitHub CI 校验
    说明：需要 Q3 启用（共用 husky hook 载体），但不强制自动启用

Q5: 「PR 工作流规范」— PR 标题、正文模板、Test plan 格式约束
    实施：文档约定（通用）+ GitHub pr-lint CI（仅 Q2=[1] 时联动安装）
    说明：文档部分在任何远程托管项目中适用；CI 自动校验仅在 GitHub 项目中有

Q6: 「分支与发布管理」— 分支命名、合并策略、版本发布流程
    实施：文档约定（通用）+ GitHub rulesets（仅 Q2=[1] 时联动安装）
    说明：文档部分在任何远程托管项目中适用；rulesets 配置仅在 GitHub 项目中有

Q7: 「代码风格与质量」— ESLint + Prettier + lint-staged
    实施：本地 lint + pre-commit hook

Q8: 「测试策略」— 测试分层、断言归属、工具选择
    实施：文档指引

Q9: 「开发环境纪律」— 进程清理、资产保留、分层验证
    实施：文档指引 + validate.sh

Q10: 「AI 协作风格」— 分工、自主执行、test plan 执行、review 自检、经验沉淀、汇报格式
     实施：文档约定
     说明：可选能力，推荐 AI 经常参与实现的项目启用

Q11: 「决策记录 (ADR)」— 架构决策的记录和索引

Q12: 「排障知识库」— 分类记录排障经验

Q13: 「版本化研究院」— 产品研究、技术选型的版本化管理

Q14: 「项目专属文档」— 项目特有的内容文档目录

Q15: 「历史归档」— 废弃项目内容的归档目录

—— 确认汇总 ——

展示：启用的约束、对应的文档+脚本、跳过的项及原因
确认：[1] 确认执行 [2] 回退修改 [3] 取消
```

### 联动规则（双向，不可独立选择）

| 约束 | 联动资产 | 说明 |
|------|---------|------|
| 提交信息格式校验 | husky + commitlint | — |
| Git 内容语言规范 | commit-msg 中 CJK 检测 | 需要 Q3 的 husky hook 作为载体 |
| PR 工作流规范 | pr-lint.yml | 仅 GitHub 项目联动 CI，文档部分不受影响 |
| 分支与发布管理 | rulesets.md | 仅 GitHub 项目联动 CI，文档部分不受影响 |

### 兼容化处理流程（每个 install-*.sh）

1. **检测**：检查目标项目是否已有对应配置
2. **差异分析**：生成 diff
3. **自然语言描述**：diff-helper.sh 翻译
4. **用户确认**：接受/拒绝/自定义
5. **执行**：合并或跳过
6. **校验**：validate.sh 验证

### 融合模式额外提问

```
Qx: 检测到已有 .husky/commit-msg（Conventional Commits 校验）
    [1] 保留现有  [2] 替换  [3] 合并（展示 diff）  [4] 跳过
```

## 经验沉淀机制

### 分阶段行为

**Skill 存在时**（skill.md 中明确）：
每次 AI 协作会话中，如产生可复用的经验，Skill 主动建议沉淀到对应位置。

**Skill 删除后**（ai-memory.md 驱动）：
AI 读取 ai-memory.md 中的「经验沉淀」章节，自行判断何时沉淀。

### 沉淀位置

| 经验类型 | 沉淀位置 | 触发条件 |
|---------|---------|---------|
| 架构/技术决策 | `docs/decisions/` | 做出影响项目结构或技术方向的选择 |
| 问题排障 | `docs/troubleshooting/` | 遇到并解决了非显而易见的错误 |
| 研究发现 | `docs/research/` | 产品调研、技术选型评估 |
| 约束变更 | `docs/practices/` + AGENTS.md | 修改了工程规范 |

### ai-memory.md 模板中加入

> AI 在每次协作中产生的经验（决策、排障、研究），应在会话结束前主动建议沉淀到 docs/ 对应位置。项目是 AI 经验的唯一归纳场所，不应依赖全局记忆或外部系统。

## 工程规范文档（7 文档）

| # | 文档 | 行数 | 关键变化 |
|---|------|------|---------|
| 1 | `commit-guidelines.md` | ~50 | 移除 release-please 专属规则 |
| 2 | `pr-guidelines.md` | ~100 | 从 196 行瘦身 |
| 3 | `branch-protection.md` + `release-versioning.md` | ~80 | 分拆分支保护与版本/tag 规则 |
| 4 | `testing-strategy.md` | ~60 | 提炼通用原则 |
| 5 | `dev-hygiene.md` | ~80 | 规则2 改为通用模板 |
| 6 | `ai-execution.md` + `ai-memory.md` | ~110 | 分拆执行规则与经验沉淀章节 |
| 7 | `git-language-policy.md` | ~100 | GitHub 绑定改为可选 |

## 实施步骤（本次仅执行阶段 1）

### 阶段 1：构建 Skill

1. 创建 `.claude/skills/docs-governance/` 目录
2. 将本计划文件复制到 `docs/plan.md`（供后续 Skill 维护参考）
3. 编写 `README.md`（人类阅读：功能、结构、安装与删除建议）
3. 编写 `skill.md`（5 模式 + 边界规则 + 优先级声明 + 激活条件 + 分阶段经验沉淀行为）
4. 编写 `Q&A-TEMPLATE.md`（参考模板 + 适配说明）
5. 创建 `templates/`（含优先级声明的 CLAUDE.md + 全部文档模板 + docs/scripts/ 维护脚本）
6. 创建 `assets/` 全部脚本和配置
7. 编写 `scripts/`（初始化脚本）
8. 编写 `tests/`（unit + 5 fixtures）
9. 在 fixtures 上验证 5 个模式

### 阶段 2：应用到当前项目（后续手动触发）

Skill 构建完成后，通过 `/docs-governance` 显式触发融合模式，按 Q&A 模板连续提问，完成当前项目的治理体系迁移。迁移内容包括：文章大纲/设计风格/写作草稿 → `docs/project/`，废弃文档 → `docs/archive/project/`，已有 husky + commitlint 的兼容合并。

## Verification（阶段 1）

1. Skill 3 层测试通过（unit + 5 fixtures + self-check）
2. 5 个模式在 fixtures 上验证通过
3. README.md 明确说明「初始化后可安全删除」
4. 模板 CLAUDE.md 含优先级声明
5. doc-maintenance.md 含完整自维护逻辑（约束生命周期、诊断清单、Q&A 决策参考、兼容化处理）
6. templates/docs/scripts/ 含 audit.sh、validate.sh、diff-helper.sh

---

## 阶段 1 优化（2026-05-12）

基于三方审计（计划合规 + youtube-translate-tools 实践 + harness-engineering 设计理念）的优化计划。

### 一、架构决策

**方案 C：脚本输出结构化结果，LLM 负责交互**

所有脚本支持 `--json` 模式输出结构化数据（含 `status`、`diff`、`recommendation`、`description_nl` 等字段）。LLM 调用脚本获取结构化结果 → 语义增强 → 自然语言呈现给用户 → 确认 → 调用脚本执行。分析质量的底限由脚本保证，不受 LLM 能力影响。

**Skill 仅显式激活**

- 移除 SKILL.md 中所有隐式激活条件，仅保留 `/docs-governance` 显式命令
- SKILL.md frontmatter 添加 `disable-model-invocation: true`
- 边界规则不再有矛盾：Skill 只在用户显式调用时工作

**模板通用化 + Node.js/TS 参考**

- 所有模板文档移除特定技术栈假设，改为通用原则
- Node.js/TypeScript 作为参考示例保留，但加标签明确标注适用范围
- `dev-hygiene.md` 移除 ML 模型权重特定内容

### 二、脚本改造（方案 C 落地）

#### 2.1 维护脚本增强（templates/docs/scripts/）

| 脚本 | 改造 |
|------|------|
| `diff-helper.sh` | 新增 `--json` 模式；修复 macOS 兼容（`diff -u` 替代裸 `diff`）；输出 `{"status":"conflict/clean/missing","existing":{...},"incoming":{...},"diff":{"added":N,"removed":N},"recommendation":"merge/replace/skip","description_nl":"..."}` |
| `audit.sh` | 新增 `--json` 模式；修复 macOS 兼容（`grep -E` 替代 `grep -P`）；输出 `{"results":[],"summary":{"total":N,"passed":N,"failed":N,"warnings":N},"description_nl":"..."}` |
| `validate.sh` | 新增 `--json` 模式；输出结构化校验报告 `{"checks":[],"summary":{"passed":N,"failed":N},"description_nl":"..."}` |
| `check-consistency.sh`（新增） | 从 harness-engineering 借鉴 C1-C7 理念，通用化为文档一致性检查：AGENTS.md 链接有效性、索引与实际文件一致性、跨文件计数同步。输出结构化报告。可配置 `.consistency-checks.conf` |

#### 2.2 安装脚本改造（scripts/）

所有 `install-*.sh` + `scaffold.sh` 改为双模式：

| 模式 | 标志 | 行为 |
|------|------|------|
| 检查 | `--check` | 检测已有配置 → 调用 diff-helper.sh --json → 输出结构化 merge plan → 不写入任何文件 |
| 执行 | `--apply merge\|replace\|skip` | 按指定策略执行，执行后调用 validate.sh 做 smoke test |

`scaffold.sh` 额外改造：
- `--dry-run`：展示所有将要创建/修改的文件列表（结构化输出）
- 不再仅是 helper 函数，改为真正的编排入口——包含 Q&A 答案到 install-*.sh 的映射关系

#### 2.3 脚本输出约定

所有脚本遵循统一的结构化输出协议：
- `--json` 模式：stdout 输出纯 JSON，stderr 输出诊断日志
- JSON 必须包含 `description_nl` 字段（自然语言描述，LLM 可直接呈现给用户）
- 退出码：0=成功/无变更，1=检测到冲突/失败，2=脚本自身错误

### 三、新增资产

| 资产 | 来源 | 路径 |
|------|------|------|
| pre-push snippets | ytt 实践 | `assets/husky/snippets/branch-protection.sh` + `release-versioning.sh` |
| rulesets JSON | ytt 实践 | `assets/github/rulesets/protect-main.json` + `protect-tags.json` |
| PR body 结构校验 | ytt 实践 | `assets/github/scripts/pr_body_structure.py` |
| 文档一致性检查 | harness-engineering 理念 | `templates/docs/scripts/check-consistency.sh` |

#### 3.1 pre-push hook 设计

通用化 ytt 的 pre-push：
- 阻止删除 `main`/`master` 分支
- 阻止非 fast-forward 推送到 `main`/`master`
- 阻止删除 `v*` release 标签
- 阻止覆盖 `v*` release 标签
- 无 ytt 特定的 release-please 逻辑

#### 3.2 GitHub rulesets JSON 设计

替代 `assets/github/rulesets.md`（说明文档）为可机器应用的 JSON 文件：
- `protect-main.json`：禁止删除 main、禁止 force push、要求 PR merge
- `protect-tags.json`：禁止删除/覆盖 `v*` 标签
- 保留 `.md` 作为应用说明文档

#### 3.3 pr_body_structure.py 设计

通用化 ytt 的 PR body 校验：
- 保留：4-section 结构校验（Summary/Implementation notes/Test plan/Closes）
- 保留：AI 工具签名过滤（17+ 正则模式）
- 保留：Test plan 必须含可执行命令
- 移除：ytt 特定的 release-please 跳过逻辑、TDD 检查、troubleshooting 索引检查
- 所有 section 名称通过配置文件参数化

#### 3.4 check-consistency.sh 设计

从 harness-engineering 的 C1-C7 中提取通用模式：
- C1：AGENTS.md 中列出的文件链接是否有效（无断链）
- C2：AGENTS.md 中声明的文件数量与实际目录内容是否一致
- C3：docs/ 下所有 .md 文件是否被至少一个 AGENTS.md 索引引用（无孤儿文件）
- C4：联动脚本（husky hooks、config 文件等）是否已安装且可执行

### 四、文档扩展

#### 4.1 branch-protection.md + release-versioning.md

新增内容：
- 分支策略决策树（Git Flow / GitHub Flow / Trunk-based 的适用场景）
- Release 自动化流程（release-please 触发条件、auto-merge 机制、CHANGELOG 生成）
- 版本号规范（SemVer 2.0.0）

#### 4.2 ai-execution.md + ai-memory.md

新增内容：
- **Auto-Retry 通用约定**：
  - Commit 被 hook 拒绝 → 翻译 CJK 内容 → 重新提交
  - PR 创建被 CI 拒绝 → 修正格式 → 重新推送
  - 不假设失败是最终结果，主动尝试修复
- **Test plan 执行与报告**（当前仅占 10 行，展开为完整流程）
- **结构化输出消费模式**：解释 LLM 应如何消费脚本的 `--json` 输出 → 翻译 → 呈现给用户
- **Code review 自检**：6 项从 TypeScript 改为通用模式（资源释放、输入校验、错误处理、并发安全、边界条件、日志敏感信息），原有 TS 条目标注为参考示例

#### 4.3 git-language-policy.md（67→~100 行）

新增内容：
- CJK 检测的 hook 实现细节和正则原理
- CI 层双重校验逻辑（local hook + remote CI）
- 例外处理：Escape hatch 机制（如 `<!-- skip-cjk-check -->` 注释标记）
- Auto-Retry：检测到 CJK → 自动翻译 → 重试提交流程

### 五、SKILL.md 关键修改

1. **frontmatter**：添加 `disable-model-invocation: true`
2. **激活条件**：移除隐式激活，仅保留显式 `/docs-governance`
3. **边界规则**：移除矛盾规则，简化为「Skill 仅在用户显式调用时工作」
4. **融合模式步骤**：明确 LLM 必须先调 `install-*.sh --check` 获取结构化 merge plan
5. **诊断模式步骤**：明确 LLM 优先调 `audit.sh --json`
6. **新增章节「结构化输出约定」**：说明脚本和 LLM 的分工协议

### 六、清理与修正

1. **移除** `templates/docs/project/` 下计划外的子目录（写作草稿/、engineering/、project/）
2. **修正** `practices/AGENTS.md` 中陈旧的行数标注
3. **修正** `Q&A-TEMPLATE.md` 中 Q4 的误导性说明（"不强制自动启用"→"必须依赖 Q3 的 husky hook 载体"）
4. **修正** `doc-maintenance.md` 联动关系表与 `Q&A-TEMPLATE.md` 联动规则表的格式一致性
5. **修正** `audit.sh` 和 `diff-helper.sh` 的 macOS 兼容性（GNU grep → POSIX grep，`diff` → `diff -u`）
6. **修正** `dev-hygiene.md` 中 ML 模型权重特定措辞，改为通用资产保护模板

### 七、doc-maintenance.md Q&A 补全

在现有 Q&A 决策参考表格（静态）基础上，新增「交互式问答指引」章节：
- 每项约束的提问措辞建议（自然语言模板）
- 确认汇总格式（启用项列表 + 联动脚本 + 跳过的项及原因）
- 现状分析前置步骤（读取已有文件 → 适配提问 → 不机械照搬）
- 融合模式额外选项措辞

### 八、实施顺序

1. **修复阻断级 bug**：audit.sh + diff-helper.sh macOS 兼容性
2. **SKILL.md 修改**：frontmatter + 仅显式激活 + 结构化输出约定章节
3. **脚本改造**：diff-helper.sh --json → install-*.sh --check/--apply → audit.sh --json → validate.sh --json → scaffold.sh 编排
4. **新增资产**：pre-push → rulesets JSON → pr_body_structure.py → check-consistency.sh
5. **文档扩展**：branch-protection.md / release-versioning.md → ai-execution.md / ai-memory.md → git-language-policy.md
6. **清理与修正**：project/ 子目录 → 行数标注 → Q4 依赖说明 → dev-hygiene 通用化
7. **doc-maintenance.md Q&A 补全**
8. **最终验证**：fixture 项目上验证 5 个模式

### 九、验证标准

1. 所有脚本 `--json` 模式输出合法 JSON，含 `description_nl` 字段
2. `audit.sh` 在 macOS 上正确检测链接有效性
3. `diff-helper.sh` 在 macOS 上正确统计行数
4. SKILL.md 不含隐式激活条件，frontmatter 含 `disable-model-invocation: true`
5. 扩展后的 3 个文档达到目标行数，内容覆盖 Auto-Retry 和程序化校验
6. 4 个新资产存在且可工作
7. `templates/docs/project/` 仅含 `AGENTS.md`
8. doc-maintenance.md 含交互式问答指引章节
9. 5 个 fixture 项目可用作测试目标
