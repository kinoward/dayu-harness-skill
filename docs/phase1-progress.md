# Phase 1 进度、计划与经验沉淀

本文记录 Dayu Harness Skill 自身的当前工程状态。它不是部署到目标项目的模板，也不是使用者安装指南；它服务维护者理解 Phase 1/Phase 2 已经完成什么、当前工具能做什么、后续应该怎样推进。

`docs/plan.md` 保留早期设计追溯和历史语境。当前事实以本文件、`SKILL.md`、`AGENTS.md`、`capabilities/*.json`、`src/`、CI 配置和非测试验证结果为准。

## 当前状态

截至 2026-05-29，本分支已把 Phase 1 从文档设计推进到 TypeScript-only CLI：

| 阶段 | 状态 | 当前事实 |
| --- | --- | --- |
| Phase 1b | 已落地 | `manifest v2`、`dayu.config.yaml`、locale catalog 和路径安全 schema 已由 TypeScript/Zod 契约覆盖。 |
| Phase 1c | 已落地 | CLI 命令树、部署 DAG、概念依赖图和 Frontend/Tool/Product 三层分离已固化为 `src/architecture/` 契约。 |
| Phase 1d | 已落地 | `src/cli/` 提供本地 CLI 垂直切片，能对 `core`、`git.hooks`、`git.commit-format`、`ai.execution` 进行规划、写入、诊断和校验。 |
| Phase 1e | 已落地 | 公开 CLI 收敛为 `init`、`apply`、`diagnose`、`validate`；`init` 默认 dry-run，`apply --only` 支持能力闭包部署，文件写入使用原子写入。 |
| Phase 2 | 已落地 | 当前 20 个 manifest 全部迁移到 v2 字段；CLI 公开 `init`、`apply`、`merge`、`generate`、`repair`、`status`、`diagnose`、`validate`、`finalize`、`environment`、`i18n-drift` 和 `sensor`，并支持 journal、lock、`--force`、orphan 清理和 npm 发布链路配置。 |
| CLI 收缩 | 已落地 | 原根目录 Bash 脚本和 hook snippet 已迁移为 `src/` 内 TypeScript/Node 实现；`scripts/` 不再作为发布或维护入口。 |
| 测试归档 | 已落地 | 历史测试、fixture 和 smoke 资料已归档到 `archive/tests/`；当前不执行、不新增测试代码。 |

当前可直接使用的本地 CLI 入口：

```bash
npm run dayu -- --help
npm run dayu -- init --target <target> --json
npm run dayu -- init --target <target> --apply --json
npm run dayu -- status --target <target> --config <target>/dayu.config.yaml --json
npm run dayu -- merge --target <target> --config <target>/dayu.config.yaml --dry-run --json
npm run dayu -- generate --target <target> --config <target>/dayu.config.yaml --capability core --json
npm run dayu -- repair core --target <target> --config <target>/dayu.config.yaml --json
npm run dayu -- apply --target <target> --config <target>/dayu.config.yaml --dry-run --json
npm run dayu -- diagnose --target <target> --config <target>/dayu.config.yaml --json
npm run dayu -- validate --target <target> --config <target>/dayu.config.yaml --json
npm run dayu -- environment <target> --check --json
npm run dayu -- i18n-drift --json
npm run dayu -- sensor audit --json <target>
```

当前 TypeScript CLI 是主确定性执行层，覆盖当前 20 个 manifest 的本地部署、融合、生成、修复、诊断、验证、环境检查、目标传感器和远端动作；真实 GitHub 远端同步和发布验证仍需要在 `finalize` 中按用户已确认范围显式开启。

## 覆盖图

| 已交付表面 | Reference | How-to | Tutorial | Explanation |
| --- | --- | --- | --- | --- |
| manifest v2 与 `dayu.config.yaml` schema | `docs/phase1b-schema.md`、`AGENTS.md`、`SKILL.md`、`src/schemas/` | `npm run lint` 与 `npm run build` 的类型/构建命令 | 暂无 | `docs/phase1b-schema.md` 与 schema 契约说明 |
| CLI 命令树与部署 DAG | `docs/phase1c-architecture.md`、`src/architecture/` | `docs/phase1d-cli.md` 的本地运行命令 | 暂无 | `docs/phase1c-architecture.md` 的三层分离和依赖模型 |
| TypeScript CLI 垂直切片 | `docs/phase1d-cli.md`、`docs/phase1e-cli-scope.md` | `README.md`、本文件和 `docs/getting-started.md` 的命令入口 | 暂无 | `docs/scaffold-sh-spike.md` 保留历史 Bash 行为追溯 |
| Phase 2 CLI 产品化 | `docs/phase2-product.md`、`docs/getting-started.md`、`docs/configuration.md`、`docs/troubleshooting.md` | `README.md` 与 `docs/getting-started.md` 的命令入口 | 暂无 | `docs/phase2-product.md` 解释状态机、事务语义和目标项目结构 |
| 临时目录回退策略 | 本文件、`.gitignore`、`src/` | 非测试验证命令和运行时缓存忽略规则 | 暂无 | 本文件的 QA 经验沉淀 |
| 历史测试归档 | `archive/tests/`、`AGENTS.md` | 当前无执行入口 | 暂无 | 本文件的验收说明 |

Tutorial 缺口仍是有意延后：Phase 2 已提供快速开始、配置和排障文档，但还没有面向新贡献者的完整教学。等 npm 首发和外部试用反馈稳定后，再补独立教程更合适。

## 维护者计划

近期计划：

1. 保持 `/dayu-harness` 本地部署、融合、生成、修复、诊断、验证、收尾和远端动作以 TypeScript CLI 为主；新增 CLI 行为必须收缩在 `src/` 内。
2. 每次修改 manifest v2、schema、CLI 命令、installer adapter 或部署 DAG，都同步更新说明文档、manifest 映射和非测试验证命令。
3. 将 QA 中发现的环境假设沉淀到 TypeScript 实现和文档约束中，尤其是临时目录、hook stdin、符号链接 hook、原子写入失败清理。
4. 只在目标项目实际部署内容变化时修改 `templates/`、`templates.en/`、`assets/` 和 `capabilities/`，避免把维护者测试记录误写进部署产物。
5. npm 首发前保持 `npm pack --dry-run`、`npm publish --dry-run` 和 production install smoke warning-free。

## QA 经验

本次 QA 暴露的核心问题是：维护脚本不能假设 `${TMPDIR:-/tmp}` 一定可写。Agent 沙箱、CI、受限用户目录或特殊 shell 环境都可能让系统临时目录不可用。

已经沉淀的规则：

- 优先使用 `DAYU_HARNESS_TMPDIR`，其次 `TMPDIR`，再回退到目标项目或输出目录内的 `.tmp`，最后才使用 `/tmp`。
- 创建临时文件前要 `mkdir -p` 候选目录，并通过 `mktemp` 的真实返回值判断是否可用。
- pre-push 多 snippet 已改为 Node hook 片段，仍必须共享同一份 `DAYU_HARNESS_PRE_PUSH_INPUT`，不能让第一个片段消耗 stdin 后导致后续片段读不到输入。
- 运行缓存统一写入根 `.tmp/` 或目标项目 `.dayu-harness/tmp/`，归档测试缓存位于 `archive/tests/unit/.tmp/` 并被忽略。
- 当前用户要求测试代码归档且暂不执行/编写测试；修复后只使用 TypeScript 编译、发布构建和 i18n drift 等非测试命令验证工具没有明显破坏。

当前可用的非测试验证命令：

```bash
git diff --check origin/main...HEAD
npm run dayu -- --help
npm run dayu -- init --target .tmp/review-tool-smoke --apply --json
npm run dayu -- diagnose --target .tmp/review-tool-smoke --config .tmp/review-tool-smoke/dayu.config.yaml --json
npm run dayu -- validate --target .tmp/review-tool-smoke --config .tmp/review-tool-smoke/dayu.config.yaml --json
npm run dayu -- apply --target .tmp/review-tool-smoke --config .tmp/review-tool-smoke/dayu.config.yaml --dry-run --json
npm run lint
npm run i18n:check
npm run build
```

本轮重构期间不执行测试、不新增测试。历史测试结果只保留在 `archive/tests/` 中作为参考，不再代表当前维护基线。

## 不变边界

- README 面向使用者，只保留安装、使用、产物和高层结构，不承载完整内部计划。
- `AGENTS.md` 是仓库级事实入口，目录或职责边界变化必须同步。
- `docs/plan.md` 是历史设计追溯，不再承担当前进度看板职责。
- `templates/` 与 `templates.en/` 是部署产物源，不用于记录本工具自身的测试结论、复盘或进度。
