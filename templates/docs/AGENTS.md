# docs/AGENTS.md

本文件是 `docs/` 目录的索引。AI 应先读取根目录 `AGENTS.md` 了解项目总目标，再读取本文件了解 docs 内的结构。

## 目录索引

- [AGENTS.md](AGENTS.md) - 当前入口
- [harness/AGENTS.md](harness/AGENTS.md) - core：治理规则、反馈检查和维护流程
- [design-docs/AGENTS.md](design-docs/AGENTS.md) - 默认：架构与设计决策
- [exec-plans/AGENTS.md](exec-plans/AGENTS.md) - core：执行计划
- [generated/AGENTS.md](generated/AGENTS.md) - core：自动生成资料索引
- [product-specs/AGENTS.md](product-specs/AGENTS.md) - 默认：产品规格与项目上下文
- [references/AGENTS.md](references/AGENTS.md) - 默认：外部资料和研究索引
- [troubleshooting/AGENTS.md](troubleshooting/AGENTS.md) - 默认：排障知识库
- [archive/AGENTS.md](archive/AGENTS.md) - 默认：历史归档

目录索引变化（含目录、文件或能力部署清单变化）时，必须同步更新本区块。

## 核心入口

### [harness/](harness/AGENTS.md)

治理体系本身。`guides/` 是 AI 行动前读取的规则卡片，`sensors/` 是 AI 行动后用于检查和反馈的脚本、CI 与 review checklist，`maintenance.md` 说明如何维护整套体系。

### [exec-plans/](exec-plans/AGENTS.md)

执行计划。活跃计划放在 `active/`，完成后移入 `completed/`，让 AI 接手任务时能快速理解当前进度。

### [generated/](generated/AGENTS.md)

自动生成资料索引。AI 生成的临时报告、草稿或批量整理结果先放在这里，确认后再沉淀到长期目录。

## 默认知识库入口

以下目录由默认治理能力部署，作为项目长期记忆和上下文的固定入口。

- `design-docs/`：架构与设计决策记录（ADR）
- `troubleshooting/`：排障知识库
- `references/`：外部资料与版本化研究
- `product-specs/`：产品规格和项目专属上下文
- `archive/`：历史归档
