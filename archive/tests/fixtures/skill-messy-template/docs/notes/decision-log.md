# 决策日志

## 2026-03-11

- 确认使用 CommonJS 风格，后续可改为 ESM 统一风格。
- 暂时不引入测试框架，先使用原生断言。

## 2026-03-12

- Hook 先用 husky 安装，commit-msg 与 pre-commit 并行运行。
- 发现 `.husky` 目录应当用 `husky install` 维护，与 AGENTS 里的描述可能不一致。

