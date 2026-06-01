# scaffold.sh 内部逻辑 spike

本文记录 Phase 1d TypeScript CLI port 前必须理解的历史 Bash 脚手架行为。当前实现已收缩到 `src/` 内 TypeScript CLI；本文只作为旧行为追溯和风险清单，不再描述当前执行入口。

## 1. Manifest 解析与依赖展开

入口函数：

- manifest 加载块读取 `capabilities/*.json`，建立内存数组。
- `manifest_path_for_id` 通过内存数组查找 manifest。
- legacy category mapping 把旧类别映射到新能力 ID。
- `resolve_request_ids` 合并默认能力、`--enable` 和 `--only`。
- `resolve_recursive` 展开依赖。

> 说明：本文以函数名和语义为主，不把行号当成契约。原 Bash 入口已迁移，旧行号和文件路径只保留历史参考价值。

当前语义：

- Bash 版本使用 `jq` 读取 JSON，不调用 TypeScript schema。
- 依赖展开只读取 `.dependencies[]?`，尚未读取 `deployment_deps`。
- `default=true` 的能力始终进入请求集合。
- 内部能力不会在公开列表里出现，但可被依赖展开纳入部署，例如 `git.hooks`。

TypeScript port 启示：

- Phase 1d 应读取 `deployment_deps`，但只针对 v2 试点 manifest。
- 当前仍保留 legacy `dependencies` 作为兼容字段和人工审阅线索，必须与 `deployment_deps` 同步。
- 依赖解析要返回结构化错误：unknown capability、missing dependency、cycle。

## 2. 文件收集

入口函数：

- `get_template_items_json` 根据 locale 选择模板。
- `get_kind_items_json` 统一读取 template/asset item。
- `collect_file_entries` 生成 dry-run/apply 的文件 item。
- `collect_file_entries_blocked` 在策略未确认时生成 blocked item。

当前语义：

- 中文 locale 使用 `template_files`。
- 英文 locale 优先使用 `template_files_i18n.en`；缺失时尝试把 `templates/` 路径替换为 `templates.en/` 并标记 source 是否存在。
- dry-run 统计 `new`、`existing`、`missing_source`。
- apply 对已有目标文件默认 `skipped_existing`，不覆盖。

TypeScript port 启示：

- Phase 1d planner 应先产出完整 file operation plan，再执行写入。
- `existing` 不是成功写入，应进入 drift/conflict 语义。
- 英文模板 fallback 要可测试，不能只依赖路径猜测。

## 3. 模板渲染与 i18n

入口函数：

- `render_managed_file` 处理占位符并复制文件。
- `get_template_items_json` 的 locale 选择承担当前 i18n 行为。

当前语义：

- 当前模板 i18n 主要靠 `templates/` 与 `templates.en/` 双树。
- 渲染只替换 `__DAYU_DEFAULT_BRANCH__` 和 `__DAYU_PROJECT_VERSION__`。
- Phase 1b 新增的 `{{dayu:key}}` key-based i18n 目前只是 schema/token 契约，尚未接入 Bash 渲染。

TypeScript port 启示：

- Phase 1d 可先保留双模板树语义，避免扩大迁移面。
- key-based i18n 渲染应作为单独能力引入，不混入 apply planner 的第一版。
- 渲染器需要明确 binary/text 判断，避免对非文本资产做替换。

## 4. 写入与 managed_paths

入口函数：

- `add_managed_path` 去重并排除 `.claude` 与 `skills-lock.json`。
- `collect_managed_paths_for_apply` 收集默认项目文件、template、asset 和 installer 管理路径。
- `collect_file_entries` 在 apply 模式下执行 `mkdir`、copy/render、`chmod +x`。

当前语义：

- apply 会创建新文件，但默认不覆盖已有文件。
- executable 来自 manifest item 的 `executable` 字段。
- installer 的 managed paths 通过 `installer_managed_paths` 静态映射补充。
- managed paths 用于最终精确 stage，禁止 `git add .`。

TypeScript port 启示：

- apply plan 要显式区分 `create`、`skip-existing`、`missing-source`、`installer`。
- managed path registry 应来自 manifest + installer adapter，不能从实际 git diff 猜。
- Phase 1d 至少实现幂等 no-op 和漂移警告，`--force` 留到 Phase 2。

## 5. 临时目录与受限环境

入口函数：

- `dayu_tmp_candidates` 统一给出临时目录候选。
- `make_writable_tmpfile` 为 smoke、remote stderr、PR/Issue body、policy 校验等场景创建可写临时文件。
- `make_writable_tmpdir` 为 release/remote 验证创建可写临时目录。

当前语义：

- 不假设 `${TMPDIR:-/tmp}` 可写。
- 回退顺序是 `DAYU_HARNESS_TMPDIR`、`TMPDIR`、`TARGET/.tmp`、`OUTPUT_BASE/.tmp`、`/tmp`。
- 每个候选目录先 `mkdir -p`，再以 `mktemp` 的真实返回值判断是否可用。
- pre-push snippet 自身也需要回退临时目录；它们共享 `DAYU_HARNESS_PRE_PUSH_INPUT`，避免多个 snippet 重复消费 stdin。

TypeScript port 启示：

- CLI 和脚手架都应允许调用方显式指定可写临时目录，尤其是在 Agent sandbox 和 CI 中。
- 测试应覆盖不可写 `TMPDIR`，不能只靠默认开发机环境。
- `.tmp/` 是本仓库维护者运行缓存，不是部署产物。

## 6. Git commit 与 remote 操作

入口函数：

- `finalize_git_after_apply` 精确 stage managed paths 并创建初始化提交。
- remote action 选择逻辑与 `run_github_remote` 负责 GitHub remote 脚本调用。
- `run_post_apply_checks` 运行 validate、audit、check-consistency 和 capability-smoke。
- dry-run 和 apply 主流程分别组织预览和写入。

当前语义：

- `--finalize-git auto` 只有在 apply 和检查通过后才尝试提交。
- Git finalization 会检查 Git 仓库、`user.name`、`user.email`。
- GitHub remote 由 `scripts/github-remote.sh` 处理，Bash 主流程只传递 remote actions 与环境变量。
- post-apply checks 是部署成功判断的一部分，不是可选附加项。

TypeScript port 启示：

- Phase 1d 的 CLI apply 可以先不负责 Git finalization，把提交/远端同步留在后续阶段或通过 adapter 调用。
- remote actions 不应阻塞本地 v2 试点能力垂直切片，除非 config 显式启用 GitHub 能力。
- JSON 输出需要 schema 化，不能长期依赖手写字符串拼接。

## 7. Hook installer 原子写入

入口函数：

- `scripts/install-husky.sh` 的 `hook_write_target` 解析普通 hook 文件与符号链接 hook。
- `hook_file_mode` 保留既有 hook 的文件模式。
- `write_hook_atomically` 写入同目录临时文件后 rename，失败时清理临时文件。

当前语义：

- merge 既有 hook 时保留原内容并追加 Dayu snippet。
- 如果 `.husky/commit-msg` 是符号链接，写入目标是符号链接指向的实际文件，不替换 symlink。
- 既有可执行位需要保留，避免安装 snippet 后破坏 hook 可执行性。

TypeScript port 启示：

- installer adapter 不能把 hook 文件当作普通文本覆盖。
- 原子写入和 symlink/mode 保留应有专门测试，避免后续 CLI 化时退化。

## 主要风险

- Bash 输出 JSON 是手写字符串，消费端必须处理非 JSON 或 partial JSON。
- 当前 apply 不是事务型写入；Phase 1d 失败恢复只能做到可重试，不应承诺完整回滚。
- `scaffold.sh` 对旧 manifest 依赖 `dependencies`；TS 读取 `deployment_deps` 时必须限制到 v2 试点能力。
- 临时目录不可写是实际 QA 风险；新增 smoke 或脚本时必须使用 `make_writable_tmpfile` / `make_writable_tmpdir`，不要重新写 `${TMPDIR:-/tmp}` 假设。
- 现有 Bats 对文件数量和能力输出有较多断言，任何默认能力变化都会放大测试影响。

## Phase 1d 建议

最小实现路径：

1. 加载并校验 `dayu.config.yaml`。
2. 只加载 4 个 v2 试点 manifest：`core`、`git.hooks`、`git.commit-format`、`ai.execution`。
3. 使用 Phase 1c 的部署 DAG 解析部署顺序。
4. 生成 dry-run plan，明确 create/skip/missing/conflict。
5. 在 apply 中写入新文件，已有文件只报告 drift/conflict，不覆盖。
6. 输出 human summary 和 `--json` 结构化报告。
