# Skill 执行完成报告模板

本模板用于大禹治库 Skill `finalize` 完成后的最后一步。它是 Skill 自身的交互模板，不属于部署到用户项目的治理体系内容。

## 使用时机

以下操作完成并完成 `finalize` 后，必须使用本模板向用户收尾：

- 新项目脚手架完成后
- 已有项目融合完成后
- 维护模式修改完成后
- 生成特定文档或配置完成后

CLI `apply`、`init --apply`、`merge --apply` 或任何手工写入完成后，必须立即进入 `finalize`。运行时优先调用 CLI `finalize`，并以它的 JSON 结果作为汇报依据；不得绕过 CLI 手工拼接 stage、commit、远端创建、PR 或 release 验证流程。

## Finalize 流程

向用户汇报前，AI 需要先执行 `finalize`。默认使用 `$CLI finalize --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --skill-root "$SKILL_ROOT" --json`；已启用 GitHub 远端同步或用户明确选择远端治理时，追加 `--github-remote apply`。Release Please 默认使用 `--release-validation readiness`；只有用户明确要求真实发版验收时，才追加 `--release-validation real`。`npx dayu-harness ...` 只作为已发布包 fallback，不作为源码或本地 Skill 安装目录的默认路径。CLI `finalize` 可用时，不得手工执行 GitHub 远端同步替代远端 apply。

当前环境没有 `finalize` 入口时，先说明 CLI 不可用和影响，再按以下清单做降级检查；降级路径不能汇报为完整成功，除非能证明与 CLI finalize 覆盖范围等价。

推荐顺序：

1. 运行 `node "$TARGET_ROOT/docs/harness/sensors/scripts/validate.mjs" --json "$TARGET_ROOT"`，确认已启用的自动检查、配置和协作流程能正常工作。
2. 运行 `node "$TARGET_ROOT/docs/harness/sensors/scripts/audit.mjs" --json "$TARGET_ROOT"`，确认项目入口、文档索引和维护说明完整。
3. 运行 `node "$TARGET_ROOT/docs/harness/sensors/scripts/check-consistency.mjs" --json "$TARGET_ROOT"`，确认文档之间能互相找到，旧文档没有被遗漏。
4. 运行 `$CLI diagnose --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --json`、`$CLI validate --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --json` 和 `$CLI status --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --json`，确认所有已部署能力都被覆盖：manifest 文件存在性、漂移、执行位、依赖图、`.gitignore`、commitlint CLI、Git commit hook、pre-commit lint-staged hook、pre-push 保护、Node linter/formatter CLI、PR/Issue body validators、TDD policy、release-please policy 等。CLI 或传感器没有直接覆盖的硬能力必须手动抽查对应命令或脚本；不要只抽查 GitHub 能力。
5. 基于 `.dayu-harness/managed-paths.json` 精确 stage 托管路径和长期状态，并创建初始化或维护提交。`.dayu-harness/managed-paths.json` 是长期状态，必须提交；`.dayu-harness/apply.lock`、`.dayu-harness/journal.jsonl` 和 `.dayu-harness/tmp/` 是临时/恢复用产物，必须忽略，不得提交。
6. 如果启用了 GitHub/release 远端能力，CLI `finalize` 可用时必须通过 `$CLI finalize --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --skill-root "$SKILL_ROOT" --github-remote apply --json` 应用远端动作。远端动作完成后再回读远端仓库设置、workflow permissions、rulesets 和默认分支状态；这一步只说明远端配置是否存在，不等同于 GitHub Actions 端到端成功。`.github/rulesets/*.json` 只是本地 payload，只有 GitHub Rulesets API 写入并回读后才能汇报为远端 ruleset 已应用。
7. 如果 CLI finalize 已执行 GitHub Issue/PR E2E，转述其结果和清理状态。降级路径只有在用户明确授权远端 E2E 时，才创建测试 Issue、测试分支和测试 PR；验证通过后必须清理测试 PR、测试 Issue 和测试分支。只有 disposable `remote-smoke` profile 才验证合并后自动关闭 Issue。
8. 如果启用了自动化版本发布流程，默认汇报 Release Please readiness 结果。真实 release 验证只在用户明确授权时执行：在目标仓库或 disposable `remote-release` 仓库中验证策略要求的触发路径和触发类型。文件存在性、语法检查、策略检查或 `workflow_dispatch` 不能替代真实验证；如果没有做真实验证，报告中必须写明未做真实发版。
9. PR body、Issue body、commit message 等固定格式内容，优先用 `node "$TARGET_ROOT/docs/harness/sensors/scripts/dayu-format.mjs"`、GitHub CLI `--body-file`、Commitizen/cz-git、commitlint、release-please、changesets 或项目内同类确定性工具生成/校验；模型只提供结构化字段和错误解释。
10. 负向测试只能说明门禁会拦截错误输入，不能替代合规 Issue/PR/release 流程通过；如果只观察到失败 workflow，不能汇报为远端 E2E 成功。
11. 如果某项检查失败，先自行修复可确定的问题，再重新检查；只有需要用户取舍时才把问题交给用户确认。

## 汇报原则

- 用自然语言描述结果，避免把脚本名、字段名和计数作为主体。
- “启用了什么”“没有启用什么”“检查了什么”只能使用自然语言能力名；不要在用户可见报告里展示 `core`、`git.commit-format`、`github.release-please` 等 capability key。维护者日志、配置、JSON 或命令参数可保留 key。
- 先告诉用户“是否已经可用”，再说明“启用了什么”和“还需要注意什么”。
- 不把跳过的能力说成失败；只说明“这次没有启用，所以没有安装相关内容”。
- 不把 `partial`、`failed`、`needs_user_action` 或已部署能力的 smoke 跳过项说成成功；必须说明影响和下一步。已启用远端动作但未执行 `--github-remote apply` 时，整体必须汇报为 partial/blocked，并列出未应用的远端动作。
- 不把 `validate/audit/check-consistency`、YAML/Python 语法检查、workflow 文件存在或本地 ruleset JSON 存在说成 GitHub Actions 或 GitHub Rulesets 端到端测试；GitHub E2E 必须有 CLI finalize 结果，或测试 Issue/PR 和对应 workflow 成功记录。rulesets 必须有远端 API 回读结果。
- 如果有剩余问题，说明影响和建议，不堆叠原始日志。
- 不把完整测试输出写入用户项目；报告只在对话中呈现。
- 完成报告不得把 `finalize` 中应执行的命令列为后续建议；如果没有完成，必须汇报为 `partial`、`failed` 或 `needs_user_action`。

## 报告模板

```markdown
已完成这次处理和检查。

我已经把这次选择的项目协作规则放进目标项目，并检查了它们是否能正常使用。整体结果是：{整体结果一句话，例如“可以使用，没有发现阻塞问题”。}

这次已经启用：
- {能力的自然语言名称，例如“项目入口索引和文档维护说明”}
- {能力的自然语言名称，例如“提交规范与协作轨迹约束”}
- {能力的自然语言名称，例如“AI 协作边界与长期记忆沉淀”}

我已经确认：
- 从 `AGENTS.md` 可以顺利进入项目文档。
- 关键文档之间的链接是通的。
- 这次启用的自动检查和能力验证可以运行，并覆盖已部署能力。
- 已经基于托管路径状态完成精确提交，临时锁、恢复日志和缓存没有进入长期提交。
- {如启用 Git 约束：提交规范检查和推送前保护已经生效。}
- {如启用质量工具：提交前质量与格式化配置已经就绪。}
- {如启用 GitHub 能力：远端同步和仓库设置回读已经完成。}
- {如启用 PR/Issue 能力：测试 Issue、测试分支和测试 PR 已经跑通，并已清理测试产物。}
- {如启用自动化版本发布流程：Release Please readiness 已通过；如用户明确授权真实发版验收，再写真实正向/负向验证结果。}

这次没有启用：
- {未启用能力的自然语言说明，例如“GitHub 发布自动化”，如果没有则省略本段。}

需要你知道：
- {剩余风险或用户需要决定的事项；没有则写“没有需要你立即处理的事项。”}

后续你可以直接按 `AGENTS.md` 作为项目入口继续协作。以后如果要新增或调整约束，可以再次运行 `/dayu-harness`。
```

完成报告之后，仅当本次 Skill 安装目录是项目内临时一次性副本（例如 `<target>/.claude/skills/dayu-harness`）时，继续提出清理问题。若 Skill 来自 `$CODEX_HOME/skills`、插件缓存、共享安装目录或源码仓库，不默认询问删除；只说明本次未清理持久安装目录。

```markdown
是否删除本次一次性 Skill 安装目录？
Do you want to delete this one-time Skill installation directory?

路径 / Path: `{一次性 Skill 安装目录的绝对路径}`

[1] 删除（默认，推荐）/ Delete (default, recommended)
[2] 保留 / Keep
[3] 暂不处理 / Not now
```

用户选择删除时，只删除上面展示的绝对路径，不删除目标项目中的 `AGENTS.md`、`docs/`、hooks、CI、`.dayu-harness/managed-paths.json` 或任何治理产物。

## 常用能力名称

本表用于维护者把 manifest/config/JSON 中的 key 映射成自然语言。面向用户的报告只使用右列说法，不展示左列 key。

| 维护者 capability id（运行时不展示） | 面向用户的说法 |
| --- | --- |
| `core` | 项目入口索引、文档维护说明和基础检查脚本 |
| `git.commit-format` | Git 提交格式约束和提交信息检查 |
| `quality.practices` | 通用开发纪律和测试策略 |
| `quality.node-tooling` | Node.js 代码质量与格式化工具 |
| `project.gitignore` | 忽略文件配置 |
| `github.repository-settings` | 仓库设置策略说明 |
| `github.pr` | PR/Issue 协作质量护栏 |
| `github.branch-protection` | 分支保护 |
| `github.issue` | Issue 依赖关系与顺序约束检查 |
| `release.versioning` | 版本与标签保护 |
| `github.release-please` | 自动化版本发布流程 |
| `quality.tdd` | PR TDD 门禁 |
| `ai.execution` | AI 执行边界和协作方式 |
| `ai.memory` | AI 记忆边界与经验沉淀 |
| `knowledge.adr` | 重要架构决策记录 |
| `knowledge.troubleshooting` | 可复用排障知识 |
| `knowledge.research` | 研究资料记录 |
| `project.context` | 项目背景和产品规格文档区 |
| `knowledge.archive` | 历史内容归档区 |
