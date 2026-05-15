# Skill 执行测试基线

本目录是 大禹治库 Skill 自身的迭代测试基础，用来验证 Skill 的问答决策、脚本部署、融合行为和部署后能力是否生效。

这里的内容只服务 Skill 维护者和 CI，不属于部署给用户项目的治理体系。测试目录、fixture、E2E 回放和测试结果记录不会通过 `capabilities/*.json` 复制到目标项目，也不应被写入 `templates/`、`assets/` 或目标项目文档模板中。

## 测试层级

### 单元与契约测试

位置：`tests/unit/`

- `test-architecture-contracts.bats`：验证 Skill 包结构、capability manifest、模板索引、脚手架行为和脚本 JSON 契约。
- `test-audit.bats`：验证 `audit.sh`、`validate.sh`、`check-consistency.sh` 的核心诊断行为。
- `test-diff-helper.bats`：验证 diff/merge 描述辅助脚本。

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
- 部署后能力：验证 `validate.sh`、`audit.sh`、`check-consistency.sh`、`commit-msg`、`pre-push` main 分支保护和 release tag 保护。
- 融合行为：验证已有项目中的 `CLAUDE.md`、根 `AGENTS.md` 断链和孤儿旧文档在用户确认后被修复并纳入渐进式文档索引。

## 运行方式

单独运行执行层 E2E：

```bash
bats tests/unit/test-skill-interaction-e2e.bats
```

运行完整维护者测试：

```bash
bats tests/unit
```

当前基线结果以本地实际运行输出为准；能力拆分后测试数量会随契约覆盖增减。

- `bats tests/unit/test-skill-interaction-e2e.bats`：2/2 通过。
- `bats tests/unit`：完整维护者测试套件通过。

## 迭代维护规则

- 修改 Skill 问答策略、capability 依赖、脚手架行为、安装脚本或部署后校验逻辑时，必须更新并运行 `test-skill-interaction-e2e.bats`。
- 修改执行测试模板或测试流程时，同步更新 `tests/fixtures/skill-usage-test-results.md`。
- 只有当目标项目实际部署内容发生产品层变化时，才修改 `templates/`、`assets/`、`capabilities/`；不要为了测试记录改动部署内容。
- 临时运行实例只写入 `tests/unit/.tmp/`。该目录已用 `.gitignore` 忽略测试产物，只保留忽略规则本身。
