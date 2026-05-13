# harness/AGENTS.md

本目录包含治理体系本身：AI 行动前读取的规则、行动后使用的反馈检查，以及维护这些内容的流程。

## 目录结构

```
harness/
├── AGENTS.md          # 你正在读
├── maintenance.md     # 文档体系维护规范
├── guides/            # 行动前规则卡片
└── sensors/           # 行动后检查与反馈
```

目录结构变化（含目录、文件或能力部署清单变化）时，必须同步更新本区块。

## 核心入口

### [maintenance.md](maintenance.md)

新增、修改、删除文档或约束时读取。Skill 删除后，AI 仍依靠本文件维护项目内的治理体系。

### [guides/](guides/AGENTS.md)

AI 执行具体任务前读取的规则卡片，例如 commit、PR、测试、发布、AI 协作方式。

### [sensors/](sensors/AGENTS.md)

AI 执行后使用的检查与反馈机制，例如维护脚本、CI 检查、review checklist。
