# V2EX Post: Dayu Harness Skill

## 发帖信息

首选节点：`分享创造`

备选节点：`程序员`

### 推荐标题

```text
[开源] 大禹治库：一次 Harness Engineering 实践，把 AI 协作规则沉淀进仓库
```

### 备选标题

```text
[开源] 基于 Harness Engineering 理念做了一个项目治理 Skill：大禹治库
```

## 图片素材链接

README banner：

```text
https://raw.githubusercontent.com/kinoward/dayu-harness-skill/main/assets/readme/dayu-harness-banner.png
```

Harness Engineering 流程图：

```text
https://raw.githubusercontent.com/kinoward/dayu-harness-skill/main/marketing/v2ex/dayu-harness-v2ex-flow.svg
```

## V2EX 正文

````markdown
![Dayu Harness Skill banner](https://raw.githubusercontent.com/kinoward/dayu-harness-skill/main/assets/readme/dayu-harness-banner.png)

大家好，分享一个最近整理出来的开源项目：Dayu Harness Skill，也叫「大禹治库」。

项目地址：
https://github.com/kinoward/dayu-harness-skill

如果这个方向对你有帮助，也欢迎 Star；如果试用中遇到问题，或者觉得某些设计不符合真实项目习惯，也欢迎直接提 Issue。

## 为什么做这个

它的核心想法来自 Harness Engineering：人不再只是在每次对话里反复提醒 AI Agent，而是把项目约束、协作规则和反馈机制沉淀到仓库里，让 Agent 在一个更明确、更可检查的工程环境中工作。

我自己理解的 Harness Engineering，大概是：

> 人类定义意图、边界和反馈回路；Agent 执行具体任务；仓库负责沉淀长期事实；脚本和 CI 负责机械化检查。

如果用一张图概括，它大概是这个流向：

![Harness Engineering flow](https://raw.githubusercontent.com/kinoward/dayu-harness-skill/main/marketing/v2ex/dayu-harness-v2ex-flow.svg)

如果图片没有正常显示，可以先看这个简化版：

```text
聊天提示 / PR 评论 / 口头约定 / 旧文档
        |
        v
Dayu Harness Skill 分析、融合、部署
        |
        v
AGENTS.md + docs/harness + hooks + CI + sensors
        |
        v
Agent 读取项目地图 -> 执行任务 -> 脚本检查 -> 经验回写仓库
```

## 想解决的问题

这个项目想解决的问题也比较具体：

现在很多项目已经开始让 Claude Code、Codex 或其他 Agent 参与开发、审查、排障和文档维护，但规则经常散在聊天记录、PR 评论、口头约定和旧文档里。结果就是每次开新会话、换新工具、换新成员，都要重新解释一遍项目规则。

Dayu Harness Skill 的做法不是让某个 Agent 在某次对话里更听话，而是把这些长期规则写回项目仓库，让仓库自己拥有一套可版本化、可审查、可迁移的协作体系。

## 它会做什么

它主要会做几件事：

- 建立以 `AGENTS.md` 为根的项目地图和渐进式文档索引
- 在 `docs/harness/` 里沉淀 AI 协作规则、维护说明和检查入口
- 按需生成 Git hooks、CI、提交规范、PR 指南和质量检查配置
- 提供 audit / validate / consistency 脚本，尽量用机械化检查替代口头承诺
- 把 ADR、排障记录、研究资料、产品上下文等长期知识放到固定目录

它是一个一次性部署、融合、诊断和维护入口，不是长期运行时服务。使用完成后可以删除 Skill，真正留下来生效的是目标项目里的 `AGENTS.md`、`docs/`、hooks、CI 和维护脚本。

## 怎么使用

安装方式大概是：

```bash
cd <target-project>
npx skills add kinoward/dayu-harness-skill
```

然后在支持 Agent Skills 的客户端里输入：

```text
/dayu-harness
```

它会先分析项目现状，再给出 dry-run 或 merge plan。已有 hooks、CI、lint、发布配置默认不会直接覆盖，会先让你确认是保留、替换、合并还是跳过。

## 适合哪些项目

比较适合这些场景：

- 新项目想从第一天就建立 AI 协作和项目治理入口
- 老项目已经有零散文档、hooks、CI 或提交规范，想整理成一套可维护体系
- 团队希望 AI 协作经验能沉淀到仓库，而不是留在不可检索的聊天记录里
- 希望 Claude Code、Codex、通用 Agent Skills 客户端之间的项目规则尽量可迁移

## 参考资料

项目参考过这些资料和仓库：

- OpenAI: Harness Engineering
  https://openai.com/zh-Hans-CN/index/harness-engineering/

- Martin Fowler: Harness Engineering
  https://martinfowler.com/articles/harness-engineering.html

- deusyu/harness-engineering
  https://github.com/deusyu/harness-engineering

- agentsmd/agents.md
  https://github.com/agentsmd/agents.md

- microsoft/skills
  https://github.com/microsoft/skills

## 还不成熟的地方

目前项目肯定还有不成熟的地方，比如模板还偏通用，对不同语言栈、团队规模和已有工程体系的适配还需要更多真实项目反馈。也欢迎大家直接指出哪些设计过重、哪些地方不符合实际开发习惯，可以在帖子里交流，也可以到 GitHub 提 Issue。

如果你也在折腾 AI Agent 参与真实项目开发，或者已经在实践 Harness Engineering、AGENTS.md、Claude Skills、Codex 这类工作流，欢迎交流一下你们是怎么管理项目规则、长期上下文和自动化反馈的。项目如果对你有一点启发，也欢迎顺手给个 Star。

感谢各位。
````
