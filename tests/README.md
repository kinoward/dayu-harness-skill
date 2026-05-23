# Skill 执行测试基线

本目录是 大禹治库 Skill 自身的迭代测试基础，用来验证 Skill 的问答决策、脚本部署、融合行为和部署后能力是否生效。

这里的内容只服务 Skill 维护者和 CI，不属于部署给用户项目的治理体系。测试目录、fixture、E2E 回放和测试结果记录不会通过 `capabilities/*.json` 复制到目标项目，也不应被写入 `templates/`、`assets/` 或目标项目文档模板中。

## 测试层级

### 单元与契约测试

位置：`tests/unit/`

- `test-architecture-contracts.bats`：验证 Skill 包结构、capability manifest、模板索引、脚手架行为和脚本 JSON 契约。
- `test-audit.bats`：验证 `audit.sh`、`validate.sh`、`check-consistency.sh` 的核心诊断行为。
- `test-diff-helper.bats`：验证 diff/merge 描述辅助脚本。
- `phase1b-schema.test.ts`：验证 manifest v2、`dayu.config.yaml` schema、key-based i18n catalog、路径安全和 Phase 1 兼容契约。
- `phase1c-architecture.test.ts`：验证 CLI 命令树、部署 DAG、概念依赖图和 Frontend/Tool/Product 三层分离契约。
- `phase1d-cli.test.ts`：验证 TypeScript CLI 垂直切片的 dry-run JSON、apply、no-op、冲突检测、init roundtrip、diagnose、validate 和 generate。

其中新增环境依赖前置断言，覆盖：
- `scripts/ensure-environment.sh --check` 的标准 JSON 字段契约；
- `scaffold.sh` 与环境预检脚本的集成引用。

### 执行测试模板

位置：`tests/fixtures/`

- `skill-empty-template/`：空项目模板，用于验证脚手架模式。
- `skill-messy-template/`：已有松散项目模板，用于验证融合模式。
- `skill-usage-test-results.md`：本次会话沉淀出的执行测试记录，包括问答映射、部署结果、能力生效检查和 CI E2E 说明。

模板目录只作为输入样本。每次测试都应复制到 `tests/unit/.tmp/` 下运行，不直接修改模板。

### CI 稳定层 E2E

位置：`tests/unit/test-skill-interaction-e2e.bats`

这是对话回放式 E2E，不驱动真实聊天 UI。它将本次测试过程收束为可重复的 CI 验收：

- 空项目：模拟用户用旧 id 追加质量能力，验证默认 Git/知识库能力与兼容展开后的新原子能力。
- 已有项目：模拟用户在默认能力基础上追加 GitHub PR、分支保护、版本保护和质量工具，明确跳过 release-please，并确认 merge 既有 hook。
- 部署后能力：验证 `validate.sh`、`audit.sh`、`check-consistency.sh` 与 `capability-smoke`，覆盖所有已部署能力的 manifest 文件、`.gitignore`、`dayu-format.mjs`、commitlint CLI、`commit-msg`、linter CLI、pre-commit lint-staged、`pre-push` main 分支保护和 release tag 保护。
- 融合行为：验证已有项目中的 `CLAUDE.md`、根 `AGENTS.md` 断链和孤儿旧文档在用户确认后被修复并纳入渐进式文档索引。
- 双语部署：分别部署默认中文与 `--locale en` 英文产物，使用 [helpers/compare-i18n-deployments.sh](helpers/compare-i18n-deployments.sh) 验证真实治理产物只有语言差异，且 Git 约束存在、GitHub 约束不存在。

### Claude CLI 本地 Smoke

位置：`tests/smoke/claude-i18n-deploy-smoke.sh`

该脚本沉淀真实 Claude Code CLI 交互测试方式：创建两个空目录，分别通过 `/dayu-harness` 部署中文和英文，保留默认 Git 约束，不启用任何 GitHub 约束，最后复用同一个比较器检查双语产物等价性。

它依赖本机 Claude 登录态、网络和权限提示，不进入默认 CI。需要显式开启：

```bash
RUN_CLAUDE_I18N_SMOKE=1 tests/smoke/claude-i18n-deploy-smoke.sh
```

如需让 Bats 一并运行真实 Claude CLI smoke：

```bash
RUN_CLAUDE_I18N_SMOKE=1 bats tests/unit/test-skill-interaction-e2e.bats
```

### Profiled Skill Smoke

位置：`tests/smoke/dayu-harness-profile.sh`

该入口把空项目测试拆成三个 profile，减少每次都跑完整远端链路的成本：

- `local-fast`：只跑本地生成、模板渲染、validate 只读性和 fake-gh 单元检查。
- `remote-smoke`：显式开启后使用 disposable GitHub repo 验证 Issue -> PR：先创建格式错误的 Issue 和 PR，确认 issue-lint / pr-lint 会拒绝；再用 `dayu-format.mjs` 生成合规 Issue / PR，验证 PR Lint 通过、合并后自动关闭 Issue，并清理测试分支。
- `remote-release`：显式开启后验证 release-please 真实 push 触发；`docs:` / `chore:` 必须不发版，随后连续两次使用 releasable commit 推进版本、发布 tag / GitHub Release，并确认 release-please 分支和 Release PR 不残留。

```bash
tests/smoke/dayu-harness-profile.sh --profile local-fast
RUN_DAYU_REMOTE_SMOKE=1 tests/smoke/dayu-harness-profile.sh --profile remote-smoke
RUN_DAYU_REMOTE_RELEASE=1 tests/smoke/dayu-harness-profile.sh --profile remote-release
```

远端 profile 默认会在结束时删除 disposable 仓库，因此 GitHub CLI token 需要 `delete_repo` scope；缺少该 scope 时脚本会在创建仓库前停止。若需要保留临时仓库排查，可显式设置 `DAYU_KEEP_REMOTE_REPO=1`。

真实远端 profile 运行后必须做收尾核对：

- `gh pr list --repo <owner/repo>` 与 `gh issue list --repo <owner/repo>` 应为空，或只剩明确关闭的历史记录。
- `git ls-remote --heads origin` 不应残留测试分支或 `release-please--*` 分支。
- 如果 disposable repo 未能删除，先记录仓库名、确认 open PR/Issue 为空；刷新 `delete_repo` 权限后再执行 `gh repo delete <owner/repo> --yes`。
- 本地临时项目只允许出现在 `${TMPDIR:-/tmp}/dayu-remote-smoke.XXXXXX/project` 或 `${TMPDIR:-/tmp}/dayu-remote-release.XXXXXX/project`；失败排查后应确认这些目录已删除。

## 运行方式

单独运行执行层 E2E：

```bash
bats tests/unit/test-skill-interaction-e2e.bats
```

单独运行 i18n 漂移契约检查：

```bash
bash scripts/check-i18n-drift.sh --json
```

该检查会验证英文镜像是否保持中文源的 Markdown 格式结构，包括 README、`templates/` 与 `templates.en/` 的文件树、标题层级、列表层级、表格、引用、代码块和链接行。

单独运行 Phase 1b schema 契约检查：

```bash
npm run test:phase1b -- --test-reporter=spec
```

单独运行 Phase 1c 架构契约检查：

```bash
npm run test:phase1c -- --test-reporter=spec
```

单独运行 Phase 1d CLI 垂直切片检查：

```bash
npm run test:phase1d -- --test-reporter=spec
```

运行全部 TypeScript 单元契约：

```bash
npm run test:unit -- --test-reporter=spec
npx tsc --noEmit
```

运行完整维护者测试：

```bash
bats tests/unit
```

当前基线结果以本地实际运行输出为准；能力拆分后测试数量会随契约覆盖增减。

- `bats tests/unit/test-github-helper-scripts.bats`：34/34 通过。
- `bats tests/unit/test-skill-interaction-e2e.bats`：17/17 通过。
- `bash tests/smoke/dayu-harness-profile.sh --profile local-fast --json`：通过。
- `bats tests/unit`：完整维护者测试套件按需运行；远端 profile 默认不纳入本地快速基线。

## 迭代维护规则

- 修改 Skill 问答策略、capability 依赖、脚手架行为、安装脚本或部署后校验逻辑时，必须更新并运行 `test-skill-interaction-e2e.bats`。
- 修改 manifest v2 字段、`dayu.config.yaml` schema、locale key 或 TypeScript schema 时，必须更新并运行 `phase1b-schema.test.ts`。
- 修改 CLI 命令树、部署/概念依赖图、三层分离约束或 TypeScript 架构契约时，必须更新并运行 `phase1c-architecture.test.ts`。
- 修改 TypeScript CLI、apply planner、installer adapter、diagnose/validate/generate 行为或 Phase 1d 试点能力部署语义时，必须更新并运行 `phase1d-cli.test.ts`。
- 修改执行测试模板或测试流程时，同步更新 `tests/fixtures/skill-usage-test-results.md`。
- 只有当目标项目实际部署内容发生产品层变化时，才修改 `templates/`、`assets/`、`capabilities/`；不要为了测试记录改动部署内容。
- TypeScript/tsx 运行缓存写入根 `.tmp/`；Bats fixture 和临时项目运行实例写入 `tests/unit/.tmp/`。两个目录均通过 `.gitignore` 忽略运行产物，只保留忽略规则本身。
