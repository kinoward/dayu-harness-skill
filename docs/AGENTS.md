# docs/AGENTS.md

Skill 自身文档索引。

## 目录索引

- [AGENTS.md](AGENTS.md) - 当前索引
- [getting-started.md](getting-started.md) - Phase 2 CLI 快速开始与常用命令
- [configuration.md](configuration.md) - `dayu.config.yaml` 配置契约与能力口径
- [troubleshooting.md](troubleshooting.md) - CLI 常见问题与排查方式
- [phase2-product.md](phase2-product.md) - Phase 2 CLI 状态机、目标目录树和产品化口径
- [plan.md](plan.md) - 完整设计计划和架构文档
- [optimization-2026-05.md](optimization-2026-05.md) - 优化记录和实施范围说明
- [phase1c-architecture.md](phase1c-architecture.md) - Phase 1c CLI 命令树、依赖图和三层分离架构契约
- [phase1d-cli.md](phase1d-cli.md) - Phase 1d TypeScript CLI 垂直切片命令语义、边界和验证方式
- [phase1e-cli-scope.md](phase1e-cli-scope.md) - Phase 1e CLI 公开范围收口、init/apply 行为和验证方式
- [scaffold-sh-spike.md](scaffold-sh-spike.md) - `scaffold.sh` 内部逻辑 spike 与 TypeScript port 风险记录
- [completion-report-template.md](completion-report-template.md) - Skill 执行完成后的验证与自然语言收尾模板

目录索引变化时，必须同步更新本区块；含目录、文件或能力部署清单变化，并同步根 [AGENTS.md](../AGENTS.md) 和 [README.md](../README.md) 中对应的 `## 目录索引` 与 `## 目录结构` 描述。

## 设计

> 触发时机：需要理解 Skill 架构决策、设计原理时读取

- [plan.md](plan.md)：完整设计计划和架构文档
- [getting-started.md](getting-started.md)：Phase 2 CLI 安装、初始化、部署、检查和修复流程
- [configuration.md](configuration.md)：`dayu.config.yaml` 字段、能力数量口径、依赖和全能力示例
- [troubleshooting.md](troubleshooting.md)：npm cache、conflict、wrong-mode、lock、orphan、merge 等常见问题
- [phase2-product.md](phase2-product.md)：Phase 2 CLI 状态机、目标项目目录树和事务语义
- [optimization-2026-05.md](optimization-2026-05.md)：2026-05 优化记录和实施范围说明
- [phase1c-architecture.md](phase1c-architecture.md)：Phase 1c CLI 命令树、DAG 和三层边界契约
- [phase1d-cli.md](phase1d-cli.md)：Phase 1d TypeScript CLI 垂直切片实现边界、命令语义和验证方式
- [phase1e-cli-scope.md](phase1e-cli-scope.md)：Phase 1e 公开 CLI 命令收口、默认 dry-run 和 `apply --only` 契约
- [scaffold-sh-spike.md](scaffold-sh-spike.md)：现有 `scaffold.sh` 的关键执行语义与 TS port 注意事项
- [completion-report-template.md](completion-report-template.md)：Skill 执行完成后如何检查目标项目并向用户汇报结果

## 约定

Skill 自身文档遵循与模板相同的约定：

- 文件名使用英文小写 + 连字符
- 文档内容保持清晰、可维护
- 本目录仅保留 Skill 自身设计文档，产物模板在 `templates/` 中
