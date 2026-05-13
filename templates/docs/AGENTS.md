# docs/AGENTS.md

本文件是 `docs/` 目录的索引。AI 应先读取根目录 `AGENTS.md` 了解项目总目标，再读取本文件了解 docs 内的结构。

## 核心入口

### [practices/](practices/AGENTS.md)

能力模块的实践文档索引。具体实践文档只在对应能力启用后部署。

### [scripts/](scripts/)

维护脚本。包含诊断完整性（audit.sh）、smoke test（validate.sh）、差异分析（diff-helper.sh）、一致性检查（check-consistency.sh）。已部署的 hook/CI/config 等配套资产按能力清单分布在项目对应位置。

### [doc-maintenance.md](doc-maintenance.md)

文档体系维护规范。包含层级结构定义、新增/删除/修改约束流程、诊断清单、Q&A 决策参考。

## 可选知识库入口

启用对应能力后再进入这些目录；未启用时不假定目录存在。

- `decisions/`：架构决策记录（ADR）
- `troubleshooting/`：排障知识库
- `research/`：版本化研究院
- `project/`：项目专属文档
- `archive/`：历史归档
