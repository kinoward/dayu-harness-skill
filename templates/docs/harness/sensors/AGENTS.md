# harness/sensors/AGENTS.md

本目录包含治理体系的反馈检查。脚本、CI、hook 和 review checklist 在 AI 完成工作后发现问题，并把结果反馈给 AI 和人类。

## 目录结构

```
sensors/
├── AGENTS.md          # 你正在读
├── scripts/           # core：诊断、验证、差异、一致性脚本
└── reviews/           # 可选：review checklist
```

目录结构变化（含目录、文件或能力部署清单变化）时，必须同步更新本区块。

## 子目录

### [scripts/](scripts/AGENTS.md)

维护脚本。包含治理体系诊断、配置 smoke test、差异分析和索引一致性检查。

### [reviews/](reviews/AGENTS.md)

Review checklist。启用 PR 能力后部署具体 checklist。
