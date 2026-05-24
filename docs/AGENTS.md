# docs/AGENTS.md

Skill 自身文档索引。

## 目录索引

- [AGENTS.md](AGENTS.md) - 当前索引
- [plan.md](plan.md) - 完整设计计划和架构文档
- [phase1-progress.md](phase1-progress.md) - Phase 1 当前进度、维护者计划和 QA 经验沉淀
- [phase1b-schema.md](phase1b-schema.md) - Phase 1b schema、manifest v2、config、i18n 和路径安全契约
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
- [phase1-progress.md](phase1-progress.md)：Phase 1b-1e 当前进度、后续计划、验证基线和临时目录回退 QA 经验
- [phase1b-schema.md](phase1b-schema.md)：Phase 1b schema、manifest v2、`dayu.config.yaml`、locale catalog 和路径安全契约
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
