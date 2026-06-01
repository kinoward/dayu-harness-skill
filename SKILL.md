---
name: dayu-harness
description: 大禹治库 Skill（Dayu Harness Skill）是帮助项目低成本接入 Harness Engineering 理念的一次性部署工具。将以 AGENTS.md 为根的渐进式披露治理体系部署到目标项目。仅通过 /dayu-harness 显式命令激活。
metadata:
  invocation_policy: "explicit-command-only"
  command: "/dayu-harness"
  compatible_agents: "agent-skills-common, claude-code, codex"
---

# Dayu Harness Skill Runtime

## 运行定位

本 Skill 只在用户显式输入 `/dayu-harness` 时运行。它负责引导用户选择治理范围、生成或维护 `dayu.config.yaml`，然后调用确定性的 `dayu-harness` TypeScript CLI 完成环境准备、部署、验证、提交和可选远端同步。

不要把本仓库的 `AGENTS.md` 当成运行时说明。`AGENTS.md` 只服务开发本 Skill；README 面向人类用户，运行时也不需要读取。Skill 使用时的长期权威是目标项目里部署出的 `AGENTS.md`、`docs/`、Node hooks、CI、`.mjs` 传感器和 `.dayu-harness/managed-paths.json`。

运行时细节只按需查阅：兼容性说明见 `references/agent-compatibility.md`，完成报告结构见 `docs/completion-report-template.md`，问答细则见 `Q&A-TEMPLATE.md`。

本 Skill 的确定性执行层全部位于 `src/`，发布后从 `dist/cli/main.js` 运行。历史 Bash 脚本和测试代码已归档；运行时不得调用 `scripts/*.sh`、`templates/**/*.sh`、`tests/`、`bats` 或 smoke 脚本。

## 先固定路径

进入任何命令前，先明确两个绝对路径，并在后续命令中始终显式使用：

- `TARGET_ROOT`：用户要部署治理体系的项目根目录。通常是 `/dayu-harness` 被调用时的当前工作目录；如果用户给了目标目录，以用户路径为准。
- `SKILL_ROOT`：当前 Skill 安装目录，即宿主提示的 `Base directory for this skill`，或包含本文件的目录。

关键边界：

- 不能从 `SKILL_ROOT` 用 `../../..` 推导 `TARGET_ROOT`。
- 进入 `SKILL_ROOT` 构建 CLI 后，不要再运行裸 `git add`、`git commit`、`npm install` 等目标项目命令。
- 目标项目命令必须使用 `--target "$TARGET_ROOT"`、`--config "$TARGET_ROOT/dayu.config.yaml"`、`git -C "$TARGET_ROOT"`，或先 `cd "$TARGET_ROOT"` 后立即执行单个目标命令。
- Skill 自身命令必须使用 `cd "$SKILL_ROOT"` 或绝对路径。

CLI 解析：

```bash
CLI="node $SKILL_ROOT/dist/cli/main.js"
```

如果 `dist/cli/main.js` 不存在，先在 `SKILL_ROOT` 中准备本地构建。这里只构建 CLI，不运行测试：

```bash
cd "$SKILL_ROOT"
[ -d node_modules ] || npm install
npm run build
```

已发布包场景也可以使用 `npx dayu-harness ...`，但源码或本地 Skill 安装目录优先使用上面的 `node "$SKILL_ROOT/dist/cli/main.js"`，避免调用到全局旧版本。

## 交互原则

- 所有用户问题和选项中英双语展示，中文在前，英文在后。
- 初始化第一个阻塞问题必须是部署内容语言：中文 / English。不得先询问项目编程语言、技术栈或项目类型；这些由脚本和文件自动判断。
- 如果宿主有原生选择器/确认框，优先使用；没有时一次只问一个阻塞问题，问完立即停下等待用户回答。
- 为了友好和快速，优先问“治理 profile”，不要逐项问完所有能力。只有用户选择自定义或检测到现有配置冲突时，才继续细问。
- 面向用户展示时使用自然语言能力名，不展示 `core`、`github.pr`、`quality.node-tooling` 等 capability key；key 只允许出现在 `dayu.config.yaml`、CLI JSON、命令参数或维护者调试里。
- `partial`、`failed`、`needs_user_action`、`skipped` 必须按原状态汇报，不能包装成成功。

## 模式选择

- 目标项目没有 `AGENTS.md`：脚手架模式。
- 目标项目已有治理文件但不完整，或已有 hooks/workflows/lint 配置需要合并：融合模式。
- 用户要求增删改治理约束或重新部署能力：维护模式。
- 用户要求检查完整性：诊断模式。
- 用户只要求生成某类文档或配置：生成模式。

## 统一执行流程

所有会写入目标项目的模式都按同一条主流程执行，不能跳步：

```text
固定 TARGET_ROOT / SKILL_ROOT
-> 准备本地 TypeScript CLI
-> 判断模式和目标项目现状
-> 询问语言与治理范围（必要时）
-> environment --check
-> 用户确认后 environment --apply
-> 生成或更新 dayu.config.yaml
-> dry-run / merge / generate 预览
-> 用户确认后 apply / merge --apply / repair
-> finalize
-> 按完成报告模板汇报
```

执行规则：

- `environment --check` 必须早于任何写入；最终能力集合确定后必须用同一组 capability id 再跑一次环境检查。
- `environment --apply` 负责目标项目 Git 初始化、Git `core.hooksPath=.husky`、Node 项目初始化、必需 devDependencies、`package-lock.json`、版本源和基础文件准备；不要手写替代这些步骤。
- `apply`、`merge --apply`、`repair` 只代表本地写入完成。只要发生写入，就必须立即进入 `finalize`。
- `finalize` 是唯一完整收尾入口，负责本地传感器、CLI 校验、精确提交、提交后复验和可选远端动作。CLI 可用时不得手工拼接 Git/GitHub 流程。
- 诊断模式只读，不写入、不提交、不做远端动作。
- 生成模式默认只预览；用户明确要求写入时，转入维护模式并走完整写入与 `finalize` 流程。
- 任何失败、`needs_user_action` 或 `partial` 都必须停止在当前阶段并如实汇报，不能继续后续阶段伪造成成功。

## 脚手架模式

1. 固定 `TARGET_ROOT` 和 `SKILL_ROOT`，读取目标项目顶层文件结构，判断是否空项目、是否已有 Git、是否已有配置。
2. 询问部署内容语言；默认中文。
3. 运行默认能力环境检查，不写入。环境预检锚点是 TypeScript CLI 的 `environment --check`：

   ```bash
   $CLI environment "$TARGET_ROOT" --check --json
   ```

4. 如果环境检查返回 `needs_install`、`needs_initialization` 或 `needs_user_action`，用自然语言说明影响并询问是否继续。用户确认后先执行：

   ```bash
   $CLI environment "$TARGET_ROOT" --apply --json
   ```

5. 选择治理 profile。优先提供 3 个快速选项：

   ```markdown
   请选择本次治理范围。
   Please choose the governance scope for this run.

   [1] 快速本地治理（默认，推荐）/ Fast local governance (default, recommended)
       部署项目入口、文档维护、提交格式、.gitignore、AI 协作、ADR、排障、研究、项目上下文和归档入口。
   [2] GitHub 协作治理 / GitHub collaboration governance
       在 [1] 基础上加入 GitHub 远端同步、仓库 PR 设置、PR/Issue 检查和分支保护。
   [3] 完整治理 / Complete governance
       在 [2] 基础上加入版本/tag 规则、Release Please、通用质量实践、Node 质量工具链和 TDD 门禁；耗时更长。
   ```

   如果用户要求自定义，使用一个 multi-select 问题收集可选能力；宿主不支持 multi-select 时，按 GitHub、发布、质量三组追问，不要逐能力追问 10 多轮。

6. 得到最终 capability id 集后，必须用同一组 id 重新执行环境检查。若需要安装或初始化，用户确认后用同一组 id 执行 `--apply`：

   ```bash
   $CLI environment "$TARGET_ROOT" --check --capabilities "<resolved capability ids>" --json
   $CLI environment "$TARGET_ROOT" --apply --capabilities "<resolved capability ids>" --json
   ```

   这一步不能省略；它负责安装启用能力所需的目标项目 devDependencies，例如 `@eslint/js`、`lint-staged`、`@commitlint/cli`。

7. 写入或更新 `dayu.config.yaml`。仅默认 profile 且目标无配置时，可直接用 CLI 初始化；包含可选能力时，按已确认的能力列表写入配置文件，再让 CLI 预览。配置写入必须保持 `deployment_deps` 闭包由 CLI 解析，不在对话中手工展开依赖。

8. 预览并确认本地部署：

   ```bash
   $CLI apply --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --dry-run --json
   ```

   向用户总结将写入的自然语言能力和文件数量。用户确认后执行：

   ```bash
   $CLI apply --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --json
   ```

9. 写入成功后立即运行 CLI `finalize`。默认走快速、安全的 readiness 验证；只有用户明确要求真实发版验收时才使用 `--release-validation real`。

   ```bash
   $CLI finalize \
     --target "$TARGET_ROOT" \
     --config "$TARGET_ROOT/dayu.config.yaml" \
     --skill-root "$SKILL_ROOT" \
     --github-remote <apply|skip> \
     --release-validation readiness \
     --json
   ```

   `finalize` 已负责本地检查、精确 stage/commit、提交后复验、远端创建/绑定、远端设置回读、Issue/PR E2E 和 Release Please readiness/real 验证。CLI 存在时不要手工执行 `git add`、`git commit`、`git push`、`gh repo create`、`gh pr merge` 或自写 E2E 流程；如果本地检查或提交后复验失败，必须停止，不能继续远端 apply。

10. 根据 `finalize` JSON 汇报结果。只有 `SKILL_ROOT` 位于 `TARGET_ROOT/.claude/skills/dayu-harness` 这类项目内临时一次性副本时，才询问是否删除该目录；源码仓库、`$CODEX_HOME/skills`、插件缓存或共享安装目录默认不提示删除。用户选择删除时，只删除展示的 `SKILL_ROOT`，不删除目标项目治理体系。

## 融合与维护模式

先确认目标配置和能力集合。若本次新增或启用能力，先按最终 capability id 集合执行 `environment --check` / `environment --apply`。然后运行结构化预览，不直接覆盖已有配置：

```bash
$CLI environment "$TARGET_ROOT" --check --capabilities "<resolved capability ids>" --json
$CLI environment "$TARGET_ROOT" --apply --capabilities "<resolved capability ids>" --json
$CLI merge --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --json
$CLI generate --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --json
```

处理原则：

- `.husky`、`.github/workflows`、ESLint/Prettier/lint-staged、commitlint、ruleset 等已有配置必须先展示 merge plan。
- `replace` 只能由用户显式选择。
- 有 installer 的组件优先走 manifest installer；静态模板和资产优先走 CLI `merge`/`generate` 预览。
- 写入完成后仍必须运行 `finalize`，不能把验证和提交留给用户。

执行命令口径：

```bash
$CLI merge --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --dry-run --json
$CLI merge --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --apply --strategy <keep|replace|skip> --json
$CLI repair <capability> --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --json
```

写入后立即运行与脚手架模式相同的 `finalize` 命令。

## 生成模式

生成模式默认只做内容预览，不写入目标项目：

```bash
$CLI generate --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --json
```

如果用户确认要把生成结果写入项目，不要手工复制生成内容；应更新 `dayu.config.yaml` 或对应能力配置，然后转入维护模式，用 `apply`、`merge --apply` 或 `repair` 写入，并执行 `finalize`。

## 诊断模式

优先使用目标项目已部署的 Node 传感器；传感器不存在时使用 CLI：

```bash
node "$TARGET_ROOT/docs/harness/sensors/scripts/validate.mjs" --json "$TARGET_ROOT"
node "$TARGET_ROOT/docs/harness/sensors/scripts/audit.mjs" --json "$TARGET_ROOT"
node "$TARGET_ROOT/docs/harness/sensors/scripts/check-consistency.mjs" --json "$TARGET_ROOT"
$CLI validate --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --json
$CLI diagnose --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --json
$CLI status --target "$TARGET_ROOT" --config "$TARGET_ROOT/dayu.config.yaml" --json
```

只转述关键结论和可行动问题，不贴大段原始 JSON。

传感器 `.mjs` 会优先委托全局 `dayu-harness sensor ...`；全局 CLI 不存在时使用模板内置 fallback。fallback 失败会返回非零退出码，诊断模式必须尊重退出码，不能把失败报告当成成功。

## 禁止路径

除非 CLI 缺失且已向用户说明 fallback 原因，否则不要执行以下操作：

- `gh repo create`、手写 GitHub API 创建默认分支、手写 `git push origin main`。
- `gh pr merge --admin`、force push、绕过刚部署的分支保护。
- 在 `SKILL_ROOT` 下运行目标项目的裸 `git add`/`git commit`/`npm install`。
- 使用 `../../..`、`.claude/skills/dayu-harness` 相对层级推导目标项目。
- 在默认路径执行真实 release 发布验证；真实发布只在用户明确选择后进行。
- 把 GitHub workflow 文件存在、ruleset JSON 存在或语法检查通过说成远端规则已经生效。

## CLI 不可用时的 fallback

如果 CLI 构建失败或当前安装缺少 `finalize` 子命令：

1. 先说明 CLI 不可用和影响。
2. 只使用目标项目中已部署的 `docs/harness/sensors/scripts/*.mjs` 传感器做只读诊断。
3. 所有 Git 命令使用 `git -C "$TARGET_ROOT"`。
4. 不做写入、远端同步或真实发布验证；报告必须标记为 `partial` 或 `needs_user_action`。
5. 不运行或恢复历史测试、Bats、smoke 或归档脚本。
