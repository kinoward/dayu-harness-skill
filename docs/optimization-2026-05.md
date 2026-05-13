# docs-governance Skill 优化记录

> **日期**: 2026-05-13
> **实施状态**: 已完成

> 范围说明：本文是 2026-05 优化记录，不是当前部署清单；是否部署以 `capabilities/*.json` 和 installer 行为为准。

## 用户确认的决策

- **AGENTS.md 路由**：采用任务触发路由（task-trigger-based），与 youtube-translate-tools 一致
- **Release-please**：作为 Q&A 独立可选资产，用户可选择启用或跳过
- **编排系统（orchestrator）**：暂不纳入 skill，聚焦治理体系脚手架

---

## Context

当前 `docs-governance` skill 是将 harness-engineering 工程理念（以 AGENTS.md 为根的渐进式披露文档体系 + 机械强制执行）落地为可复用的项目脚手架工具。通过对比参考项目（harness-engineering 学习仓库）和实践产物（youtube-translate-tools），发现 skill 的核心架构良好，但在以下方面与 harness-engineering 理念存在偏差：

**核心问题**：AGENTS.md 模板采用"类别路由"（工程约束/决策与经验/项目内容），而非 harness-engineering 倡导的"任务触发路由"（当你准备 commit 时读什么、当你准备创建 PR 时读什么）。这导致 AI 每次需要加载过多无关上下文。

**次要问题**：机械强制执行不够彻底（缺少 AI 署名剥离、issue 引用拦截）、渐进式披露不够精细（code review checklist 嵌在 ai-collaboration.md 中）、缺乏 release-please 完整的 CI/CD 闭环。

参考来源：
- harness-engineering 六大核心概念（尤其 #2 Map Not Manual、#3 Mechanical Enforcement）
- youtube-translate-tools 的实际实施模式（task-router AGENTS.md、3 层强制执行、ADR 追溯）

---

## 变更列表（共 10 项，分两阶段）

### 阶段一：核心架构变更

#### 变更 1：AGENTS.md 模板从类别路由改为任务触发路由

**影响文件**：`templates/AGENTS.md`（重写）、`templates/docs/practices/AGENTS.md`（更新）

- 将按类别分组的结构改为按 AI 实际操作任务分组
- 每个 section 以 blockquote 标注精确触发条件
- 同一文档可出现在多个 section，注明只读特定章节

**为什么**：harness-engineering "Map, Not Manual"——AI 在准备做具体操作时能立即知道「只读哪几个文档」。

#### 变更 2：添加项目状态横幅（Status Banner）

**影响文件**：`templates/AGENTS.md`（标题后插入）、`Q&A-TEMPLATE.md`（补充 Q0）、`templates/docs/doc-maintenance.md`

- 在 AGENTS.md 标题后插入状态横幅（INIT / ACTIVE / MAINTENANCE / ARCHIVED）
- 脚手架时通过 Q0 询问填充

**为什么**：youtube-translate-tools 的 AGENTS.md 顶部有状态快照，AI 第一眼就知道项目处于什么阶段。

#### 变更 3：拆分 code-review-checklist 为独立文档

**影响文件**：`templates/docs/practices/code-review-checklist.md`（新文件）、`templates/docs/practices/ai-collaboration.md`、`templates/docs/practices/AGENTS.md`、`scripts/scaffold.sh`

- 从 ai-collaboration.md Section 4 提取 6 个通用模式 + 3 个 Node.js/TS 参考模式
- ai-collaboration.md Section 4 缩减为简短指针 + TL;DR

**为什么**：渐进式披露——AI 做 code review 时只加载 checklist（~30 行），不需要加载完整 ai-collaboration.md。

#### 变更 4：commit-msg hook 增加 AI Co-Authored-By 剥离

**影响文件**：`assets/husky/commit-msg`、fixture 文件

- 静默剥离 `Co-Authored-By:` / `Co-authored-by:` 行

**为什么**：harness-engineering "Mechanical Enforcement"——AI 署名行不应进入永久 git 历史。

#### 变更 5：commit-msg hook 增加 issue 引用拦截

**影响文件**：`assets/husky/commit-msg`、fixture 文件

- 拦截 `Closes #N` / `Fixes #N` / `Refs #N` 等 4 种模式
- 报错提示引导至 PR body

**为什么**：release-please 会根据 commit 中的 `Closes #N` 在 CHANGELOG 中生成重复条目。

#### 变更 6：增加 release-please CI 工作流和配置

**影响文件**：`assets/github/workflows/release-please.yml`（新）、`assets/github/release-please-config.json`（新）、`assets/github/.release-please-manifest.json`（新）、`templates/docs/practices/branch-and-release.md`、`scripts/scaffold.sh`

- 新增 release-please.yml workflow（googleapis/release-please-action@v4）
- 新增 release-please-config.json（docs/ci/chore 默认 hidden）
- scaffold.sh 新增 `release-please` 类别

**为什么**：完善 CI/CD 闭环——husky + commitlint 本地拦截，pr-lint PR 层拦截，release-please 发布层自动化。

---

### 阶段二：品质和完整性提升

#### 变更 7：ai-collaboration.md Section 2 操作模式更具体化

**影响文件**：`templates/docs/practices/ai-collaboration.md`

- 增加后台执行 + Monitor 流式追进度、并行工具调用、遇错从 raw 输出诊断

**为什么**：youtube-translate-tools 的 ai-collaboration.md 有明确的操作模式描述，当前 skill 模板较抽象。

#### 变更 8：pr-lint.yml CI 增强——整合 pr_body_structure.py

**影响文件**：`assets/github/workflows/pr-lint.yml`、`templates/docs/practices/pr-guidelines.md`

- CI 中 pr body 结构检查改用 `pr_body_structure.py`（4-section 结构、Test plan bullet 格式、AI 水印检测）

**为什么**：pr_body_structure.py 已比 CI 中的 grep 更强大（水印检测是 grep 无法完成的），应作为主要校验入口。

#### 变更 9：Q&A 模板补充 pre-push hook 联动说明

**影响文件**：`Q&A-TEMPLATE.md`

- Q6 描述中明确提及 pre-push hook 作为本地层保护
- 联动规则表补充 pre-push hook 与 GitHub rulesets 的双层保护关系

**为什么**：pre-push hook 已在 assets 中存在且被部署，但 Q&A 模板未充分说明。

#### 变更 10：troubleshooting AGENTS.md 增加强制 TL;DR 格式

**影响文件**：`templates/docs/troubleshooting/AGENTS.md`

- `**TL;DR**` 为必需字段，必须出现在文件最前面
- 格式模板：`TL;DR: <一句话 — 症状 + 根因 + 修复>`

**为什么**：youtube-translate-tools 的 ADR-0016 Rule #14 强制 TL;DR，让 AI 无需读完整文件即可判断是否相关。

---

## 变更依赖和执行顺序

```
阶段一:
  变更 1 (AGENTS.md 重构)          — 独立
  变更 4 (AI 署名剥离)              — 独立
  变更 5 (issue 引用拦截)           — 依赖变更 4（同文件）
  变更 3 (拆分 review checklist)    — 依赖变更 1（路由引用新文件）
  变更 2 (状态横幅)                 — 依赖变更 1（同文件）
  变更 6 (release-please 资产)      — 依赖变更 5（语义关联）

阶段二:
  变更 7 (ai-collab 具体化)        — 依赖变更 3（同文件）
  变更 8 (pr-lint CI 增强)         — 独立
  变更 9 (Q&A pre-push 联动)       — 独立
  变更 10 (troubleshooting 格式)   — 独立
```

建议执行顺序：1, 4, 5, 3, 2, 6, 7, 8, 9, 10

---

## 验证方式

1. **单元测试**：`tests/unit/` 下 bats 测试确保 audit.sh / diff-helper.sh 行为不变
2. **fixture 测试**：对 5 个 fixture 项目分别 dry-run 验证
3. **端到端**：空项目 scaffold.sh --apply，验证 CJK 拦截、issue 引用拦截、AI 署名剥离
4. **渐进式披露验证**：确认 AI 读取 AGENTS.md 后对不同任务只加载对应文档子集
