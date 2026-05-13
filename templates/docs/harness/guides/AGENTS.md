# harness/guides/AGENTS.md

本目录索引 AI 行动前读取的规则卡片。每个规则文档由对应 capability manifest 控制；未启用能力时，不假定目标文件存在。

## 目录结构

```
guides/
├── AGENTS.md                 # 你正在读
├── commit-guidelines.md      # git.commit
├── git-language-policy.md    # git.language
├── pr-guidelines.md          # github.pr
├── branch-and-release.md     # github.branch-release
├── dev-hygiene.md            # quality.tooling
├── testing-strategy.md       # quality.tooling
└── ai-collaboration.md       # ai.collaboration
```

目录结构变化（含目录、文件或能力部署清单变化）时，必须同步更新本区块。

## 文档与能力

- `git.commit`：`commit-guidelines.md`
- `git.language`：`git-language-policy.md`
- `github.pr`：`pr-guidelines.md`，review checklist 见 `../sensors/reviews/`
- `github.branch-release`：`branch-and-release.md`
- `quality.tooling`：`dev-hygiene.md`、`testing-strategy.md`
- `ai.collaboration`：`ai-collaboration.md`
