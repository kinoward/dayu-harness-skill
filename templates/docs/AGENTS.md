# docs/AGENTS.md

本文件是 `docs/` 目录的索引。AI 应先读取根目录 `AGENTS.md` 了解项目总目标，再读取本文件了解 docs 内的结构。

## 目录结构

```
docs/
├── AGENTS.md                  # 你正在读
├── harness/                   # core：治理规则、反馈检查和维护流程
├── design-docs/               # 可选：架构与设计决策
├── exec-plans/                # core：执行计划
├── generated/                 # core：自动生成资料索引
├── product-specs/             # 可选：产品规格与项目上下文
├── references/                # 可选：外部资料和研究索引
├── troubleshooting/           # 可选：排障知识库
└── archive/                   # 可选：历史归档
```

目录结构变化（含目录、文件或能力部署清单变化）时，必须同步更新本区块。

## 核心入口

### [harness/](harness/AGENTS.md)

治理体系本身。`guides/` 是 AI 行动前读取的规则卡片，`sensors/` 是 AI 行动后用于检查和反馈的脚本、CI 与 review checklist，`maintenance.md` 说明如何维护整套体系。

### [exec-plans/](exec-plans/AGENTS.md)

执行计划。活跃计划放在 `active/`，完成后移入 `completed/`，让 AI 接手任务时能快速理解当前进度。

### [generated/](generated/AGENTS.md)

自动生成资料索引。AI 生成的临时报告、草稿或批量整理结果先放在这里，确认后再沉淀到长期目录。

## 可选知识库入口

启用对应能力后再进入这些目录；未启用时不假定目录存在。

- `design-docs/`：架构与设计决策记录（ADR）
- `troubleshooting/`：排障知识库
- `references/`：外部资料与版本化研究
- `product-specs/`：产品规格和项目专属上下文
- `archive/`：历史归档
