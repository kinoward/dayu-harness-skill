# 测试夹具说明

本目录存放 大禹治库 Skill 的测试夹具。夹具本身是 Skill 迭代测试输入样本，不属于部署给用户项目的治理体系；需要运行测试时，先复制到 `tests/unit/.tmp/skill-run-*` 这类临时目录，再在临时目录中执行脚手架、融合或诊断流程。

本仓库中 “messy” 一词指治理状态不完整（如入口缺失、断链、索引不齐等），不是 Markdown 结构或语法本身错误。

## 使用效果模板

- `skill-empty-template/`：空项目模板。目录内仅保留 `.gitkeep` 以便 Git 追踪；复制为运行实例后应删除 `.gitkeep`，确保实例目录实际为空。当前执行基线用它验证空项目默认启用 Git 约束和非 GitHub 文档能力，可追加质量工具，同时明确不部署 GitHub 相关资产。
- `skill-messy-template/`：已有项目模板。它包含小型 Node CLI 代码、松散文档、不完整治理入口以及已有 hooks/CI/config，用于验证 Skill 在融合、诊断和 merge 策略下不会覆盖原项目内容。

## 既有单元测试夹具

- `empty-project/`、`messy-project/` 以及 `has-*` 目录继续服务现有 bats 单元测试。
- 新增的 `skill-*-template/` 目录用于更接近真实使用路径的手工或集成验证；后续可从这些模板提炼稳定断言再固化为 bats。

完整执行测试基线见：[../README.md](../README.md)。
