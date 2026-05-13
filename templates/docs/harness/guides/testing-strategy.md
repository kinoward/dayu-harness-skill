# 测试策略

> 触发时机：编写测试、选择测试工具、排查 E2E 不稳定时读取

## 分层总览

| 层 | 工具（按项目类型） | 职责 | 速度 |
|----|-------------------|------|------|
| **Unit / Integration** | vitest + jsdom / jest / pytest | 状态机逻辑、API 契约、错误映射、UI 瞬态 | 秒级 |
| **Browser E2E** | Playwright / Cypress | 真实 DOM wiring、跨 context 通信、HTTP 请求轨迹 | 分钟级 |

## 断言归属原则

每条断言只放**能稳定观察它的那一层**：

| 断言类型 | Unit | E2E | 原因 |
|----------|------|-----|------|
| 状态机中间态 | 适合 | 不适合 | mock 即时返回，E2E poll 抓不到瞬态 |
| HTTP 请求链 | 不适合 | 适合 | unit 用 fake client 不走网络 |
| DOM wiring | 不适合 | 适合 | jsdom 不模拟真实浏览器行为 |
| 错误映射 | 适合 | 不适合 | 只需 mock 返回 status |

## 工具选择指南

| 项目类型 | Unit 工具 | E2E 工具 |
|---------|----------|---------|
| JavaScript/TypeScript 前端 | vitest + jsdom | Playwright |
| Python 后端 | pytest + pytest-asyncio | — |
| 全栈 | vitest（前端）+ pytest（后端） | Playwright |

## E2E 策略

E2E 测试是可选的。是否引入 E2E 取决于：
- 项目是否涉及复杂 UI 交互
- 项目是否涉及跨进程/跨网络通信
- 团队是否有资源维护 E2E 测试

E2E 测试不应阻塞本地开发流程，可作为 CI 的可选步骤。

## 新增测试的 checklist

1. 确认断言归属——放错层会导致不稳定或假绿
2. 确认 mock 隔离——单元测试不依赖外部服务
3. 异步测试不使用 `sleep` 轮询——用 `waitUntil(predicate, timeout)`
4. 新增测试文件遵循项目测试目录约定

## 项目特定约束

<!-- 每个项目在此补充特定的测试约束，例如： -->
<!-- - Content script 不能直接 fetch localhost -->
<!-- - webextension-polyfill 在 vitest jsdom 下 crash -->
