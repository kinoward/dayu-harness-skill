# AGENTS.md

Skill 自身入口。本 Skill 帮助项目建立以 AGENTS.md 为根的渐进式披露文档体系。

## 目录索引

- [AGENTS.md](AGENTS.md) - 当前索引
- [SKILL.md](SKILL.md) - Skill 行为定义
- [README.md](README.md) - 人类阅读概述
- [Q&A-TEMPLATE.md](Q&A-TEMPLATE.md) - 初始化与融合问答参考
- [agents/](agents/) - Codex UI 与触发策略元数据
- [references/agent-compatibility.md](references/agent-compatibility.md) - 跨 Agent 兼容说明
- [capabilities/](capabilities/) - 治理能力 manifest，部署清单单一事实源
- [templates/](templates/) - 部署到目标项目的文档模板
- [assets/](assets/) - 按能力部署的 hook、CI、配置资产
- [scripts/](scripts/) - Skill 内部初始化与安装脚本
- [docs/AGENTS.md](docs/AGENTS.md) - Skill 自身文档入口
- [tests/](tests/) - Skill 自身测试和 fixture 项目
- [tests/README.md](tests/README.md) - Skill 自身执行测试基线

目录、文件或能力部署清单变化导致结构变化时，必须同步更新本区块与 [README.md](README.md) 中对应的 `## 目录结构` 描述。

## 理解 Skill

> 触发时机：需要理解 Skill 的定位、行为和模式时读取

- Skill 行为定义：[SKILL.md](SKILL.md)
- 人类阅读概述：[README.md](README.md)
- 跨 Agent 兼容说明：[references/agent-compatibility.md](references/agent-compatibility.md)

## 维护 Skill

> 触发时机：修改 Skill 自身设计或实现时读取

- 设计计划：[docs/plan.md](docs/plan.md)
- Q&A 参考模板：[Q&A-TEMPLATE.md](Q&A-TEMPLATE.md)
- 执行完成报告模板：[docs/completion-report-template.md](docs/completion-report-template.md)

## Skill 产物

> 触发时机：理解 Skill 的产出和部署目标时读取

- 文档模板：[templates/](templates/)
- 脚本与配置资产：[assets/](assets/)
- 内部初始化脚本：[scripts/](scripts/)
- Skill 自身文档：[docs/AGENTS.md](docs/AGENTS.md)

## 测试

> 触发时机：修改 Skill 后需要验证时读取

- 测试目录：[tests/](tests/)
- 执行测试基线：[tests/README.md](tests/README.md)
