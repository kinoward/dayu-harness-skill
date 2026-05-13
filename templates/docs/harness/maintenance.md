# 文档维护规范

> 触发时机：新增、修改、删除文档或约束时读取。本文件是体系自洽的关键——Skill 删除后，AI 仅凭本文件即可独立执行所有维护操作。

## AGENTS.md 层级结构

```
CLAUDE.md              → 仅含 @AGENTS.md 引用，不直接写内容
AGENTS.md              → 项目总入口，按任务类型路由到 docs/ 下的文档或子目录
docs/AGENTS.md         → docs 级索引：列出所有子目录入口 + 独立文档
docs/子目录/AGENTS.md   → 子目录级索引：本目录职责 + 文件列表
```

### 目录索引同步

凡 `AGENTS.md` 或 `README.md` 中存在 `## 目录索引`/`## 目录结构` 区块，目录、文件、子目录或 capability 部署清单变化时，必须同步更新该区块。`AGENTS.md` 仅维护 `## 目录索引`（本层和直接子目录）；`README.md` 可维护 `## 目录结构`（项目或部署后整体结构）。

`AGENTS.md` 的可选标记应仅用于 core 索引到未部署的 capability 入口，并且必须写明合法 `可选：capability.id`；同一 capability 内部文件链接不要求也不应标可选。  
通配和占位路径（如 `*.md`、`YYYY-MM-DD-vN/`）不应写成 Markdown 链接，需使用反引号文本说明。

## 能力清单与部署模型

目标项目内的 `AGENTS.md`、`docs/`、`docs/harness/sensors/scripts/` 与已部署 hook/CI/config 等资产是运行时权威；Skill 只作为初始化或升级这些文件的来源。

目标项目通过能力清单（capability manifest）定义可用能力，并以 `core + module` 方式部署：

- `core`：基础治理骨架（短根 AGENTS 路由、CLAUDE.md、harness 入口、maintenance、维护脚本、exec-plans 索引）
- `module`：被部署到目标项目的可选治理能力模块（guide 文档、Git hooks、GitHub CI、release-please、知识库目录等）

联动组件是治理能力部署出的文件、hook、CI、脚本等。
新增治理能力优先更新能力清单；未启用的治理能力不会在目标项目生效。
目标项目部署后的文档不依赖 Skill 内部文件路径；若后续需要未启用能力，需要重新安装 Skill，或手工引入对应模块。

### 核心原则

- **每层只描述本级**：AGENTS.md 只列出本目录的文件和直接子目录入口，不跨级展开内容
- **渐进式导航**：AI 从根 AGENTS.md 出发，根据任务类型逐层深入
- **子目录必有 AGENTS.md**：docs/ 下每个子目录必须有自己的 AGENTS.md 作为入口
- **纯索引不展开**：AGENTS.md 只放标题 + 触发条件 + 链接，具体内容在独立文档中
- **目录索引同步**：目录索引、链接和 `## 目录索引` 区块必须同时维护，避免 AGENTS 索引与实际文件或已启用能力脱节

### 触发条件格式

每个根 AGENTS.md 章节以 blockquote 标注触发条件（何时读取），例如：

```markdown
## 章节标题

> 触发条件描述

详见 [链接](路径)。
```

## 工程约束 vs 项目内容

整个 docs/ 体系从目录层面区分两个方向：

| 方向 | 含义 | 目录 |
|------|------|------|
| **工程约束** | AI 读取的规则、经验和决策，跨项目可复用 | `harness/guides/`、`design-docs/`、`troubleshooting/`、`references/research/`、`harness/sensors/`、各级 `AGENTS.md` |
| **项目内容** | 项目强相关的产物，非 AI 规则 | `product-specs/`、`archive/product-specs/` |

工程约束文档描述 AI 应遵守的规范和积累的经验。项目内容文档是 AI 需要了解的上下文，但不是行为规范。

## 项目记忆边界

项目中的 `AGENTS.md` 与 `docs/` 是项目级长期记忆的单一事实源。AI 或外部工具可以使用 Agent memory、LangChain/LangGraph store、向量库或产品内置记忆进行运行时检索、会话恢复和上下文召回，但这些系统不替代仓库内文档，也不作为权威规则来源。

写入长期目录前必须先归纳：
- 保留可复用结论、背景、适用条件、验证方式和失效条件
- 不保存完整对话记录、临时假设、未确认方案、重复推理过程或敏感信息
- 自动生成资料先进入 `docs/generated/`，确认后再沉淀到 `design-docs/`、`troubleshooting/`、`references/research/`、`product-specs/` 或 `harness/guides/`
- 外部记忆系统产生的有价值内容，必须整理成项目文档并同步对应 `AGENTS.md` 索引后，才视为项目长期记忆

## 约束生命周期管理

### 新增约束

1. 确定归属目录（`harness/guides/`、`design-docs/`、`troubleshooting/`、`references/research/` 或 `product-specs/`）
2. 创建文档文件（遵循本规范的语言和命名规则）
3. 如需联动治理能力，更新能力清单并部署对应能力模块
4. 更新该目录的 `AGENTS.md`，添加文件条目，并同步相关 `## 目录索引` 区块（含 `README.md` 的 `## 目录结构`）
5. 更新「文档与脚本联动关系」节（如涉及）
6. 验证：确认从根 AGENTS.md 可逐级导航到新文档

### 修改约束

1. 定位受影响的文档和脚本（参考「文档与脚本联动关系」节）
2. 修改文档内容
3. 如涉及脚本变更，同步更新对应脚本
4. 如涉及索引变更（文件增删），更新对应 `AGENTS.md`，并同步受影响的 `## 目录索引` 区块（及 `README.md` 的 `## 目录结构`）
5. 使用 `docs/harness/sensors/scripts/diff-helper.sh` 生成变更描述（如可用），用户确认
6. 执行 `docs/harness/sensors/scripts/validate.sh` 验证（如可用）

### 删除约束

1. 分析影响范围——检查「文档与脚本联动关系」表中的联动链
2. 展示受影响的所有文档和联动组件（完整列表）
3. 用户确认后执行：
   - 删除文档文件
   - 删除关联联动组件
   - 更新所有受影响的 AGENTS.md 索引及相关 `## 目录索引` 区块（含 `README.md` 的 `## 目录结构`）
   - 更新联动关系表
4. 验证：确认无断链残留

## 诊断与完整性检查

### 自动诊断

优先执行 `docs/harness/sensors/scripts/audit.sh`（如存在）。若不可用，AI 按以下检查清单手动逐项执行。

### 检查清单

1. **AGENTS.md 链路**
   - 根 `CLAUDE.md` 是否存在且内容为 `@AGENTS.md`
   - 根 `AGENTS.md` 是否存在，链接是否指向存在的文件
   - `docs/AGENTS.md` 是否存在，列出的子目录是否实际存在
   - 各子目录的 `AGENTS.md` 是否存在，列出的文件是否实际存在
- `AGENTS.md` 的 `## 目录索引` / `README.md` 的 `## 目录结构` 是否与实际目录和已启用能力一致

2. **索引一致性**
   - 各 AGENTS.md 中列出的文件与实际目录内容是否一致
   - 是否有未被任何 AGENTS.md 引用的「孤儿文件」
   - 是否有 AGENTS.md 引用了不存在的文件（断链）

3. **联动约束完整性**
   - 联动组件是否已按能力清单部署且可执行
   - 联动规则表中的约束是否都有对应文档和联动组件

4. **命名规范**
   - 文件名是否使用英文小写 + 连字符
   - 版本化目录是否使用 `YYYY-MM-DD-vN` 格式

## Q&A 决策参考

以下治理约束是交互式问答参考。实际启用项、依赖、模板文件、资产文件、验收标准以能力清单 manifest 为准；如两者不一致，先修正 manifest，再更新本节。

### Git 相关

| capability | 约束 | 实施方式 | 联动组件 | 适用条件 |
|---|------|---------|---------|---------|
| `git.commit` | 提交信息格式校验 | husky + commitlint | husky hook + commitlint config | Git 项目 |
| `git.language` | Git 内容语言规范 | husky hook + 可选 CI | commit-msg 中 CJK 检测 | Git 项目（需 `git.commit` 的 hook 载体） |
| `github.pr` | PR 工作流规范 | 文档约定 + 可选 CI | pr-lint.yml（仅 GitHub） | GitHub 项目 |
| `github.branch-release` | 分支与发布管理 | 文档约定 + 可选 rulesets | rulesets JSON（仅 GitHub） | GitHub 项目 |

### 代码质量

| capability | 约束 | 实施方式 | 联动组件 | 适用条件 |
|---|------|---------|---------|---------|
| `quality.tooling` | 代码风格、质量与测试策略 | ESLint + Prettier + lint-staged + 文档指引 | eslint config + prettier config + lint-staged config + .gitignore | 含代码项目 |

### 开发规范

| capability | 约束 | 实施方式 | 联动组件 | 适用条件 |
|---|------|---------|---------|---------|
| `quality.tooling` | 开发环境纪律 | 文档指引 + validate.sh | — | 含代码项目 |
| `ai.collaboration` | AI 协作风格 | 文档约定 | — | AI 经常参与实现的项目 |

### 知识管理

| capability | 约束 | 实施方式 | 联动组件 | 适用条件 |
|---|------|---------|---------|---------|
| `knowledge.adr` | 决策记录 (ADR) | `docs/design-docs/` 目录 + 模板 | adr-template.md | 通用 |
| `knowledge.troubleshooting` | 排障知识库 | `docs/troubleshooting/` 目录 | — | 通用 |
| `knowledge.research` | 版本化研究院 | `docs/references/research/` 目录 | — | 有持续研究需求 |
| `project.docs` | 产品规格与项目上下文 | `docs/product-specs/` 目录 | — | 有项目专属内容 |
| `archive.project` | 历史归档 | `docs/archive/` 目录 | — | 有已废弃的历史内容 |

### 文档与脚本联动关系

| capability | 联动组件 | 说明 |
|------|---------|------|
| `git.commit` | husky + commitlint | `install-husky.sh` + commitlint config |
| `git.language` | commit-msg 中 CJK 检测 | 必须依赖 `git.commit` 的 husky hook 载体 |
| `github.pr` | PR 本体化检查（pr-lint.yml + pr_body_structure.py） | 仅 GitHub 项目联动 CI |
| `github.branch-release` | rulesets JSON + pre-push hook | GitHub rulesets（远程）+ pre-push hook（本地）双重保护 |
| `quality.tooling` | ESLint + Prettier + lint-staged + .gitignore + validate.sh | 复杂配置默认人工确认 |
| `github.release-please` | release-please.yml + config + manifest | 仅 GitHub 项目；依赖 `git.commit` + `github.pr`；需要 PAT |
| 诊断 | audit.sh + check-consistency.sh | 文档完整性自动检查 |

> 纯文档能力（如 `ai.collaboration`、知识库目录）仍由 manifest 控制启用，不通过脚本资产隐式部署。

## 兼容化处理参考

当需要修改已有配置时，按以下流程操作（本流程可由 AI 手动执行，也可由 `diff-helper.sh` 辅助）：

1. **检测**：检查目标位置是否已有对应配置（如 `.husky/commit-msg`、`commitlint.config.cjs`）
2. **差异分析**：比较已有配置和 docs-governance 提供的治理模板差异
3. **生成变更描述**：用自然语言描述变更内容，例如「你的项目已有 commit-msg hook，包含 Conventional Commits 校验。新增内容与现有规则并存，不影响既有行为」
4. **用户确认**：提供 [1] 保留现有 [2] 替换 [3] 合并 [4] 跳过 四个选项
5. **执行**：按用户选择处理
6. **校验**：验证变更结果（hook 可执行、config 语法正确）

## 交互式问答指引

> 当 AI 需要引导用户完成治理体系初始化或扩展时，按以下流程操作。本指引确保 Skill 删除后 AI 仍能按相同质量执行交互式问答。

### 现状分析前置步骤

提问前必须先分析项目现状：

1. 检查是否存在 `CLAUDE.md`、`AGENTS.md`、`docs/` 目录
2. 检查 `.husky/`、`commitlint.config.cjs`、`.github/workflows/` 等已有配置
3. 基于检测结果适配提问——已有配置的不直接问「是否启用」，而是问「检测到已有 X，是否保留/增强/跳过」

### 提问措辞模板

对每项约束，用描述性语言提问而非技术术语：

| 约束 | 提问措辞建议 |
|------|------------|
| 提交信息格式校验 | 「每次 git commit 时自动检查提交信息是否符合 Conventional Commits 格式。启用后会安装 husky 和 commitlint 作为本地检查工具。」 |
| Git 内容语言规范 | 「要求 commit、PR、issue 等 Git 相关内容全部使用英文。启用后会在 commit 时自动拦截中文内容。需要注意的是，这个功能需要和提交信息格式校验一起使用。」 |
| PR 工作流规范 | 「为 PR 建立标题、正文模板和 Test plan 格式标准。如果使用 GitHub，还可以安装自动 CI 检查。」 |
| 代码风格与质量 | 「安装 ESLint + Prettier，在 commit 前自动检查和格式化代码。」 |
| AI 协作风格 | 「建立 AI 和人类的分工规则，包括自主执行、review 自检、经验沉淀等约定。推荐所有项目启用。」 |

### 确认汇总格式

提问完成后，展示汇总：

```
## 确认汇总

### 启用的约束
- 提交信息格式校验 → 安装 husky + commitlint
- Git 内容语言规范 → CJK 检测将在 commit-msg hook 中配置
- AI 协作风格 → 部署 ai-collaboration.md 文档

### 联动组件
- .husky/commit-msg
- .husky/pre-commit
- commitlint.config.cjs

### 跳过的项
- 代码风格与质量（用户选择跳过）
- PR 工作流规范（用户选择跳过）

[1] 确认执行 [2] 回退修改 [3] 取消
```

### 融合模式额外选项措辞

检测到已有配置时，对每个已有配置询问：

> 检测到你的项目已有 `.husky/commit-msg`（包含 Conventional Commits 校验）。你希望如何处理？
> [1] 保留现有配置，不做任何修改
> [2] 替换为新的模板配置
> [3] 合并——保留你现有的校验逻辑，补充 CJK 检测等新增功能（我将展示具体变更内容）
> [4] 跳过此项，不做任何操作

## 语言规则

- `docs/**` 下所有文档使用**中文**
- git 与 GitHub 远程仓库相关内容（commit / PR / issue / release notes / branch 名）使用**英文**

## 文件命名规则

- 文件名使用英文小写 + 连字符（如 `commit-guidelines.md`）
- 版本化目录命名格式：`YYYY-MM-DD-vN`（如 `2026-04-17-v3`）
- 中文文件名仅在 `product-specs/` 和 `archive/product-specs/` 下允许（项目内容文档可使用中文命名）

## 新增文档流程

1. 在目标目录下创建 `.md` 文件（工程约束用英文命名，项目内容可用中文命名）
2. 更新该目录的 `AGENTS.md`，添加文件条目，并同步该目录的 `## 目录索引` 区块
3. 如果是新建子目录，同时创建该子目录的 `AGENTS.md`，在父级 `AGENTS.md` 中添加子目录入口，并同步所有受影响的 `## 目录索引` 区块（及 `README.md` 的 `## 目录结构`）
