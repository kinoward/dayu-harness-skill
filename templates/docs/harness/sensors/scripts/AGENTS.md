# docs/harness/sensors/scripts/AGENTS.md

本目录包含文档治理体系的维护脚本。脚本负责确定性检查和结构化输出，AI 负责解释结果并与用户确认。

## 目录索引

- [AGENTS.md](AGENTS.md) - 当前索引
- [audit.sh](audit.sh) - 治理体系完整性诊断
- [check-consistency.sh](check-consistency.sh) - AGENTS 链接、索引、孤儿文件、一致性检查
- [dayu-format.mjs](dayu-format.mjs) - PR、Issue、commit 等固定格式内容的确定性生成器
- [diff-helper.sh](diff-helper.sh) - 变更差异与 merge plan 描述
- [validate.sh](validate.sh) - 初始化或维护后的 smoke test

目录索引变化时，必须同步更新本区块；含目录、文件或能力部署清单变化。

## 下一步看什么

- **检查治理体系完整性** → 运行 `docs/harness/sensors/scripts/audit.sh --json <project-root>`
- **验证维护后状态** → 运行 `docs/harness/sensors/scripts/validate.sh --json <project-root>`
- **检查 AGENTS 索引一致性** → 运行 `docs/harness/sensors/scripts/check-consistency.sh --json <project-root>`
- **生成固定格式内容** → 运行 `docs/harness/sensors/scripts/dayu-format.mjs pr-body|issue-body|commit-message ...`
- **分析已有文件与模板差异** → 运行 `docs/harness/sensors/scripts/diff-helper.sh merge-plan <existing> <incoming>`
