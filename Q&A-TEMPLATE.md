# Q&A 参考模板

> 重要：本模板是参考，不是绝对流程。Skill 在提问前应先分析项目现状（读取已有文件、检查已有配置），然后基于本模板生成适配的提问。

## 适配规则

- 项目已有 `commitlint.config.cjs` → 不直接问「是否启用提交校验」，而是确认「检测到已有 commitlint，是否保留/增强/跳过」
- 项目已有 `docs/` 但结构不同 → 进入融合模式，逐项确认
- 项目已有 `.husky/` → 检测已有 hook 内容，展示差异，提供 [保留/替换/合并/跳过] 四个选项

## 提问流程（连续，描述优先）

每项 3 选项：[1] 启用 [2] 跳过 [3] 自定义需求

```
Q1: 项目是否使用 Git 版本控制？
    选项：[1] 是 [2] 否 [3] 其他版本控制系统（请描述）

Q2: 是否使用 GitHub 远程托管？
    （仅 Q1=[1] 时）
    选项：[1] 是 [2] 否 [3] 其他托管平台（请描述）

—— 治理约束逐项确认 ——

Q3: 「提交信息格式校验」— git commit 时自动校验 Conventional Commits 格式
    实施：husky + commitlint 本地 hook
    说明：启用后会安装 husky 和 commitlint。
         Q4 的语言检测将集成到同一个 husky hook 中

Q4: 「Git 内容语言规范」— commit/PR/issue/release notes/branch 名使用英文
    （仅 Q1=[1] 时）
    实施：husky hook 本地拦截 + 可选 GitHub CI 校验
    说明：必须依赖 Q3 的 husky hook 载体——CJK 检测代码嵌入在同一个 commit-msg hook 中。
         若 Q3 被跳过，Q4 的本地 hook 拦截无法独立安装，仅可通过 CI 层校验。

Q5: 「PR 工作流规范」— PR 标题、正文模板、Test plan 格式约束
    实施：文档约定（通用）+ GitHub pr-lint CI（仅 Q2=[1] 时联动安装）
    说明：文档部分在任何远程托管项目中适用；CI 自动校验仅在 GitHub 项目中有

Q6: 「分支与发布管理」— 分支命名、合并策略、版本发布流程
    实施：文档约定 + pre-push hook（本地实时拦截 delete/force push main + delete/override v* 标签）
         + GitHub rulesets（仅 Q2=[1] 时联动安装，远程层双重保障）
    说明：pre-push hook 随 husky 安装始终部署；GitHub rulesets 作为远程层双重保障

Q7: 「代码风格与质量」— ESLint + Prettier + lint-staged
    实施：本地 lint + pre-commit hook

Q8: 「测试策略」— 测试分层、断言归属、工具选择
    实施：文档指引

Q9: 「开发环境纪律」— 进程清理、资产保留、分层验证
    实施：文档指引 + validate.sh

Q10: 「AI 协作风格」— 分工、自主执行、test plan 执行、review 自检、经验沉淀、汇报格式
     实施：文档约定
     说明：核心模块，推荐所有项目启用

Q11: 「决策记录 (ADR)」— 架构决策的记录和索引

Q12: 「排障知识库」— 分类记录排障经验

Q13: 「版本化研究院」— 产品研究、技术选型的版本化管理

Q14: 「项目专属文档」— 项目特有的内容文档目录

Q15: 「历史归档」— 废弃项目内容的归档目录

Q16: 「自动发版 (release-please)」— 自动生成 CHANGELOG、版本号、release PR
     （仅 Q2=[1] GitHub 项目时）
     实施：GitHub Actions workflow（release-please-action@v4）+ release-please-config.json + .release-please-manifest.json
     说明：需要仓库设置 `secrets.RELEASE_TOKEN`（PAT）。纯 docs/ci/chore 等非用户可见变更默认不在 changelog 显示。
          依赖于 Q3（Conventional Commits）和 Q5（PR 规范）的已部署。
          合并策略必须为 merge commit，PR 标题使用自然语言。

—— 确认汇总 ——

展示：启用的约束、对应的文档+脚本、跳过的项及原因
确认：[1] 确认执行 [2] 回退修改 [3] 取消
```

## 联动规则（双向，不可独立选择）

| 约束 | 联动资产 | 说明 |
|------|---------|------|
| Q3 提交信息格式校验 | husky + commitlint | `install-husky.sh` + `install-commitlint.sh` |
| Q4 Git 内容语言规范 | commit-msg 中 CJK 检测 | 必须依赖 Q3 的 husky hook 载体；若 Q3 跳过，仅 CI 层可用 |
| Q5 PR 工作流规范 | pr-lint.yml | 仅 GitHub 项目联动 CI（`install-github-workflows.sh`），文档部分不受影响 |
| Q6 分支与发布管理 | rulesets JSON + pre-push hook | pre-push hook 本地始终部署（随 husky）；GitHub rulesets（远程）双重保护。详见 branch-and-release.md「保护规则」章节 |
| Q7 代码风格与质量 | ESLint + Prettier + lint-staged | `install-eslint.sh` + `install-prettier.sh` + `install-lint-staged.sh` |
| Q8 测试策略 | — | 纯文档，无联动脚本 |
| Q9 开发环境纪律 | validate.sh | — |
| Q10 AI 协作风格 | — | 纯文档（核心模块） |
| Q11-15 知识管理 | — | 纯文档，初始化时在 templates/docs/ 下创建对应目录结构 |
| Q16 release-please | release-please.yml + config + manifest | 仅 GitHub 项目可用；依赖 Q3（Conventional Commits）+ Q5（PR 规范）；需要 PAT |

### Q&A 答案到安装脚本的映射

| 用户选择 | 调用的脚本 |
|---------|-----------|
| Q3 启用 | `install-husky.sh` → `install-commitlint.sh` |
| Q4 启用（依赖 Q3） | CJK 检测已在 commit-msg hook 中，随 husky 安装 |
| Q5 启用 + GitHub | `install-github-workflows.sh`（pr-lint.yml + issue-lint.yml） |
| Q6 启用 + GitHub | 部署 `assets/github/rulesets/` + 安装 `pre-push` hook（本地始终安装，远程双重保障） |
| Q7 启用 | `install-eslint.sh` → `install-prettier.sh` → `install-lint-staged.sh` |
| Q11-15 启用 | `scaffold.sh` 创建对应 docs/ 子目录和模板 |
| Q16 启用 + GitHub | `scaffold.sh --only release-please`（部署 release-please.yml + config + manifest） |

## 融合模式额外提问

检测到已有配置时，对每个已有配置询问：

```
Qx: 检测到已有 .husky/commit-msg（Conventional Commits 校验）
    [1] 保留现有  [2] 替换为 Skill 版本
    [3] 合并（展示 diff + 自然语言描述）  [4] 跳过此项
```

## 兼容化处理流程

每个 install-*.sh 遵循：

1. **检测**：检查目标项目是否已有对应配置
2. **差异分析**：生成 diff
3. **自然语言描述**：diff-helper.sh 翻译
4. **用户确认**：接受/拒绝/自定义
5. **执行**：合并或跳过
6. **校验**：validate.sh 验证
