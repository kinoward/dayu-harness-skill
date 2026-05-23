# scaffold.sh 内部逻辑 spike

本文记录 Phase 1d TypeScript CLI port 前必须理解的 `scripts/scaffold.sh` 行为。目标是识别可复用语义，不是把 Bash 代码机械翻译成 TypeScript。

## 1. Manifest 解析与依赖展开

入口：

- `scripts/scaffold.sh:667` 开始加载 `capabilities/*.json`。
- `scripts/scaffold.sh:691` 的 `manifest_path_for_id` 通过内存数组查找 manifest。
- `scripts/scaffold.sh:716` 的 legacy category mapping 把旧类别映射到新能力 ID。
- `scripts/scaffold.sh:772` 的 `resolve_request_ids` 合并默认能力、`--enable` 和 `--only`。
- `scripts/scaffold.sh:892` 的 `resolve_recursive` 展开依赖。

当前语义：

- Bash 版本使用 `jq` 读取 JSON，不调用 TypeScript schema。
- 依赖展开只读取 `.dependencies[]?`，尚未读取 `deployment_deps`。
- `default=true` 的能力始终进入请求集合。
- 内部能力不会在公开列表里出现，但可被依赖展开纳入部署，例如 `git.hooks`。

TypeScript port 启示：

- Phase 1d 应读取 `deployment_deps`，但只针对 v2 试点 manifest。
- 迁移期间不能删除 legacy `dependencies`，否则现有 `scaffold.sh` 行为会断。
- 依赖解析要返回结构化错误：unknown capability、missing dependency、cycle。

## 2. 文件收集

入口：

- `scripts/scaffold.sh:838` 的 `get_template_items_json` 根据 locale 选择模板。
- `scripts/scaffold.sh:871` 的 `get_kind_items_json` 统一读取 template/asset item。
- `scripts/scaffold.sh:934` 的 `collect_file_entries` 生成 dry-run/apply 的文件 item。
- `scripts/scaffold.sh:1043` 的 `collect_file_entries_blocked` 在策略未确认时生成 blocked item。

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

入口：

- `scripts/scaffold.sh:528` 的 `render_managed_file` 处理占位符并复制文件。
- `scripts/scaffold.sh:838` 的 locale 选择承担当前 i18n 行为。

当前语义：

- 当前模板 i18n 主要靠 `templates/` 与 `templates.en/` 双树。
- 渲染只替换 `__DAYU_DEFAULT_BRANCH__` 和 `__DAYU_PROJECT_VERSION__`。
- Phase 1b 新增的 `{{dayu:key}}` key-based i18n 目前只是 schema/token 契约，尚未接入 Bash 渲染。

TypeScript port 启示：

- Phase 1d 可先保留双模板树语义，避免扩大迁移面。
- key-based i18n 渲染应作为单独能力引入，不混入 apply planner 的第一版。
- 渲染器需要明确 binary/text 判断，避免对非文本资产做替换。

## 4. 写入与 managed_paths

入口：

- `scripts/scaffold.sh:244` 的 `add_managed_path` 去重并排除 `.claude` 与 `skills-lock.json`。
- `scripts/scaffold.sh:304` 的 `collect_managed_paths_for_apply` 收集默认项目文件、template、asset 和 installer 管理路径。
- `scripts/scaffold.sh:934` 的 `collect_file_entries` 在 apply 模式下执行 `mkdir`、copy/render、`chmod +x`。

当前语义：

- apply 会创建新文件，但默认不覆盖已有文件。
- executable 来自 manifest item 的 `executable` 字段。
- installer 的 managed paths 通过 `installer_managed_paths` 静态映射补充。
- managed paths 用于最终精确 stage，禁止 `git add .`。

TypeScript port 启示：

- apply plan 要显式区分 `create`、`skip-existing`、`missing-source`、`installer`。
- managed path registry 应来自 manifest + installer adapter，不能从实际 git diff 猜。
- Phase 1d 至少实现幂等 no-op 和漂移警告，`--force` 留到 Phase 2。

## 5. Git commit 与 remote 操作

入口：

- `scripts/scaffold.sh:333` 的 `finalize_git_after_apply` 精确 stage managed paths 并创建初始化提交。
- `scripts/scaffold.sh:545` 到 `scripts/scaffold.sh:622` 处理 remote action 选择与 GitHub remote 脚本调用。
- `scripts/scaffold.sh:1721` 的 `run_post_apply_checks` 运行 validate、audit、check-consistency 和 capability-smoke。
- `scripts/scaffold.sh:2280` / `2405` 分别是 dry-run 和 apply 主流程。

当前语义：

- `--finalize-git auto` 只有在 apply 和检查通过后才尝试提交。
- Git finalization 会检查 Git 仓库、`user.name`、`user.email`。
- GitHub remote 由 `scripts/github-remote.sh` 处理，Bash 主流程只传递 remote actions 与环境变量。
- post-apply checks 是部署成功判断的一部分，不是可选附加项。

TypeScript port 启示：

- Phase 1d 的 CLI apply 可以先不负责 Git finalization，把提交/远端同步留在后续阶段或通过 adapter 调用。
- remote actions 不应阻塞本地 3-capability 垂直切片，除非 config 显式启用 GitHub 能力。
- JSON 输出需要 schema 化，不能长期依赖手写字符串拼接。

## 主要风险

- Bash 输出 JSON 是手写字符串，消费端必须处理非 JSON 或 partial JSON。
- 当前 apply 不是事务型写入；Phase 1d 失败恢复只能做到可重试，不应承诺完整回滚。
- `scaffold.sh` 对旧 manifest 依赖 `dependencies`；TS 读取 `deployment_deps` 时必须限制到 v2 试点能力。
- 现有 Bats 对文件数量和能力输出有较多断言，任何默认能力变化都会放大测试影响。

## Phase 1d 建议

最小实现路径：

1. 加载并校验 `dayu.config.yaml`。
2. 只加载 4 个 v2 试点 manifest：`core`、`git.hooks`、`git.commit-format`、`ai.execution`。
3. 使用 Phase 1c 的部署 DAG 解析部署顺序。
4. 生成 dry-run plan，明确 create/skip/missing/conflict。
5. 在 apply 中写入新文件，已有文件只报告 drift/conflict，不覆盖。
6. 输出 human summary 和 `--json` 结构化报告。
