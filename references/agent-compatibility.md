# Agent 兼容说明

本 Skill 的 canonical 入口是 `SKILL.md`。为兼容 Claude、Codex 和其他 Agent Skills 客户端，核心 frontmatter 只使用通用字段，工具专属策略放在 sidecar 文件或客户端配置中。

## 兼容目标

- **通用 Agent Skills 客户端**：读取 `SKILL.md` 的 `name`、`description`、`metadata` 和正文说明。
- **Claude Code**：可将整个 `docs-governance/` 目录安装到目标项目的 `.claude/skills/docs-governance/`。
- **Codex**：读取 `SKILL.md`；Codex UI 和隐式触发策略由 `agents/openai.yaml` 提供。

## 触发策略

本 Skill 仍采用显式调用策略：只有用户输入 `/docs-governance`，或明确要求使用本 Skill 时才启用。

canonical `SKILL.md` 不再使用 `disable-model-invocation: true`，因为该字段是 Claude 专属扩展，当前 Codex 校验器不接受。Codex 侧通过 `agents/openai.yaml` 中的 `policy.allow_implicit_invocation: false` 表达相同意图。

如果 Claude 安装环境需要机械禁止隐式触发，应在 Claude 客户端或安装侧配置中设置，不要把 Claude-only 字段重新写入 canonical `SKILL.md`。

## 安装建议

优先使用项目级安装，初始化或升级完成后可删除 Skill 目录。

- Claude Code：`<target-project>/.claude/skills/docs-governance/`
- Codex：使用 Codex 当前支持的项目级或用户级 skills 目录；若只能放在用户级目录，完成目标项目部署后可删除。
- 其他客户端：将整个 `docs-governance/` 目录作为一个 Skill 包安装，入口文件为 `SKILL.md`。

## 与部署产物的关系

`templates/CLAUDE.md` 是部署到目标项目后的 Claude 路由文件，作用于目标项目治理体系，不是本 Skill 自身的兼容层。

目标项目内的 `AGENTS.md`、`docs/`、`hooks`、`CI` 和维护脚本是运行时权威。Skill 目录只作为初始化或升级这些文件的来源。
