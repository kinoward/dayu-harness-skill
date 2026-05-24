# Phase 1 进度、计划与经验沉淀

本文记录 Dayu Harness Skill 自身的当前工程状态。它不是部署到目标项目的模板，也不是使用者安装指南；它服务维护者理解 Phase 1/Phase 2 已经完成什么、当前工具能做什么、后续应该怎样推进。

`docs/plan.md` 保留早期设计追溯和历史语境。当前事实以本文件、`SKILL.md`、`AGENTS.md`、`capabilities/*.json`、`src/` 和测试结果为准。

## 当前状态

截至 2026-05-24，本分支已把 Phase 1 从文档设计推进到 Phase 2 可实践 CLI：

| 阶段 | 状态 | 当前事实 |
| --- | --- | --- |
| Phase 1b | 已落地 | `manifest v2`、`dayu.config.yaml`、locale catalog 和路径安全 schema 已由 TypeScript/Zod 契约覆盖。 |
| Phase 1c | 已落地 | CLI 命令树、部署 DAG、概念依赖图和 Frontend/Tool/Product 三层分离已固化为 `src/architecture/` 契约。 |
| Phase 1d | 已落地 | `src/cli/` 提供本地 CLI 垂直切片，能对 `core`、`git.hooks`、`git.commit-format`、`ai.execution` 进行规划、写入、诊断和校验。 |
| Phase 1e | 已落地 | 公开 CLI 收敛为 `init`、`apply`、`diagnose`、`validate`；`init` 默认 dry-run，`apply --only` 支持能力闭包部署，文件写入使用原子写入。 |
| Phase 2 | 已落地 | 当前 20 个 manifest 全部迁移到 v2 字段；CLI 公开 `init`、`apply`、`merge`、`generate`、`repair`、`status`、`diagnose`、`validate`，并支持 journal、lock、`--force`、orphan 清理和 npm 发布链路配置。 |
| QA 修复 | 已落地 | `scaffold.sh` 和 pre-push snippet 不再假设 `${TMPDIR:-/tmp}` 可写，会回退到仓库或目标项目内的可写临时目录。 |

当前可直接使用的本地 CLI 入口：

```bash
npm run dayu -- --help
npm run dayu -- init --target <target> --json
npm run dayu -- init --target <target> --apply --json
npm run dayu -- status --target <target> --config <target>/dayu.config.yaml --json
npm run dayu -- merge --target <target> --config <target>/dayu.config.yaml --dry-run --json
npm run dayu -- generate --target <target> --config <target>/dayu.config.yaml --only core --json
npm run dayu -- repair core --target <target> --config <target>/dayu.config.yaml --json
npm run dayu -- apply --target <target> --config <target>/dayu.config.yaml --dry-run --json
npm run dayu -- diagnose --target <target> --config <target>/dayu.config.yaml --json
npm run dayu -- validate --target <target> --config <target>/dayu.config.yaml --json
```

当前仍保留 `scripts/scaffold.sh` 作为完整 Skill 交互流程和 GitHub 远端 E2E 的兼容入口。TypeScript CLI 是 Phase 2 的确定性执行层，覆盖当前 20 个 manifest 的本地部署、融合、生成、修复、诊断和验证；真实 GitHub 远端同步和发布验证仍通过 profile smoke 显式开启。

## 覆盖图

| 已交付表面 | Reference | How-to | Tutorial | Explanation |
| --- | --- | --- | --- | --- |
| manifest v2 与 `dayu.config.yaml` schema | `docs/phase1b-schema.md`、`AGENTS.md`、`SKILL.md`、`src/schemas/` | `tests/README.md` 中的 Phase 1b 命令 | 暂无 | `docs/phase1b-schema.md` 与测试契约说明 |
| CLI 命令树与部署 DAG | `docs/phase1c-architecture.md`、`src/architecture/` | `docs/phase1d-cli.md` 的本地运行命令 | 暂无 | `docs/phase1c-architecture.md` 的三层分离和依赖模型 |
| TypeScript CLI 垂直切片 | `docs/phase1d-cli.md`、`docs/phase1e-cli-scope.md` | `README.md`、本文件和 `tests/README.md` 的命令入口 | 暂无 | `docs/scaffold-sh-spike.md` 解释 Bash 到 TypeScript 的迁移边界 |
| Phase 2 CLI 产品化 | `docs/phase2-product.md`、`docs/getting-started.md`、`docs/configuration.md`、`docs/troubleshooting.md` | `README.md` 与 `tests/README.md` 的命令入口 | 暂无 | `docs/phase2-product.md` 解释状态机、事务语义和目标项目结构 |
| 临时目录回退策略 | 本文件、`.gitignore`、`scripts/scaffold.sh` | `tests/README.md` 的 `.tmp` 约定和本文件的验证命令 | 暂无 | 本文件的 QA 经验沉淀 |
| 当前验证基线 | `tests/README.md` | `tests/README.md` 的命令清单 | 暂无 | 本文件的验收说明 |

Tutorial 缺口仍是有意延后：Phase 2 已提供快速开始、配置和排障文档，但还没有面向新贡献者的完整教学。等 npm 首发和外部试用反馈稳定后，再补独立教程更合适。

## 维护者计划

近期计划：

1. 保持 Bash `scaffold.sh` 和 TypeScript CLI 的职责边界清晰：Bash 继续承载完整 Skill 交互和远端 E2E，TypeScript CLI 承载可测试的本地 planner / apply / merge / generate / repair / status / diagnose / validate。
2. 每次修改 manifest v2、schema、CLI 命令、installer adapter 或部署 DAG，都同步更新对应 Phase 测试。
3. 将 QA 中发现的环境假设转成测试，尤其是临时目录、hook stdin、符号链接 hook、原子写入失败清理。
4. 只在目标项目实际部署内容变化时修改 `templates/`、`templates.en/`、`assets/` 和 `capabilities/`，避免把维护者测试记录误写进部署产物。
5. npm 首发前保持 `npm pack --dry-run`、`npm publish --dry-run` 和 production install smoke warning-free。

## QA 经验

本次 QA 暴露的核心问题是：维护脚本不能假设 `${TMPDIR:-/tmp}` 一定可写。Agent 沙箱、CI、受限用户目录或特殊 shell 环境都可能让系统临时目录不可用。

已经沉淀的规则：

- 优先使用 `DAYU_HARNESS_TMPDIR`，其次 `TMPDIR`，再回退到目标项目或输出目录内的 `.tmp`，最后才使用 `/tmp`。
- 创建临时文件前要 `mkdir -p` 候选目录，并通过 `mktemp` 的真实返回值判断是否可用。
- pre-push 多 snippet 必须共享同一份 `DAYU_HARNESS_PRE_PUSH_INPUT`，不能让第一个 snippet 消耗 stdin 后导致后续 snippet 读不到输入。
- 测试和 smoke 产生的运行缓存统一写入根 `.tmp/` 或 `tests/unit/.tmp/`，并通过 `.gitignore` 只保留目录占位。
- 修复后要验证工具真实可用，而不只验证语法。最小证据包括 CLI smoke、TypeScript 编译、i18n drift、Bats 完整套件和一个不可写 `TMPDIR` 的定向回归。

2026-05-24 的本地验证结果：

```bash
git diff --check origin/main...HEAD
bash -n scripts/scaffold.sh assets/husky/snippets/branch-protection.sh assets/husky/snippets/release-versioning.sh scripts/install-husky.sh
npm run dayu -- --help
npm run dayu -- init --target .tmp/review-tool-smoke --apply --json
npm run dayu -- diagnose --target .tmp/review-tool-smoke --config .tmp/review-tool-smoke/dayu.config.yaml --json
npm run dayu -- validate --target .tmp/review-tool-smoke --config .tmp/review-tool-smoke/dayu.config.yaml --json
npm run dayu -- apply --target .tmp/review-tool-smoke --config .tmp/review-tool-smoke/dayu.config.yaml --dry-run --json
npm run test:unit -- --test-reporter=spec
npx tsc --noEmit
TMPDIR=.tmp bash scripts/check-i18n-drift.sh --json
TMPDIR=.tmp bats tests/unit
TMPDIR=.tmp/review-nonwritable scripts/scaffold.sh .tmp/review-fallback-target --dry-run
```

结果：本地 CLI smoke、43 个 TypeScript 单元测试、8 项 i18n drift 检查、206 个 Bats 测试全部通过；Claude CLI 真实交互 smoke 仍是 opt-in，不纳入默认本地基线。

## 不变边界

- README 面向使用者，只保留安装、使用、产物和高层结构，不承载完整内部计划。
- `AGENTS.md` 是仓库级事实入口，目录或职责边界变化必须同步。
- `docs/plan.md` 是历史设计追溯，不再承担当前进度看板职责。
- `templates/` 与 `templates.en/` 是部署产物源，不用于记录本工具自身的测试结论、复盘或进度。
