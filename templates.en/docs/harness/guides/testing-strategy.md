# Testing Strategy

> Trigger: read when writing tests, selecting testing tools, or investigating E2E instability.

## Layered Overview

| Layer | Tools (by project type) | Responsibility | Speed |
|----|-------------------|------|------|
| **Unit / Integration** | vitest + jsdom / jest / pytest | State-machine logic, API contracts, error mapping, UI transient states | Seconds |
| **Browser E2E** | Playwright / Cypress | Real DOM wiring, cross-context communication, HTTP request traces | Minutes |

## Assertion Placement Principle

Place each assertion on the layer where it can be observed reliably:

| Assertion type | Unit | E2E | Why |
|----------|------|-----|------|
| State-machine intermediate states | Suitable | Not suitable | Mocks return immediately; E2E polling misses transient states |
| HTTP request chains | Not suitable | Suitable | Unit tests often use fake clients and do not hit network |
| DOM wiring | Not suitable | Suitable | jsdom does not emulate real browser behavior |
| Error mapping | Suitable | Not suitable | Unit tests only need mocked return status |

## Tool Selection Guide

| Project type | Unit tools | E2E tools |
|---------|----------|---------|
| JavaScript/TypeScript frontend | vitest + jsdom | Playwright |
| Python backend | pytest + pytest-asyncio | — |
| Full-stack | vitest (frontend) + pytest (backend) | Playwright |

## E2E Strategy

E2E is optional. Decide whether to include E2E by checking:
- whether UI interactions are complex
- whether cross-process or cross-network communication is involved
- whether the team has capacity to maintain E2E tests

E2E should not block local development flow; it can be optional in CI.

## New Test Checklist

1. Confirm assertion placement; placing assertions at the wrong layer causes flakiness or false positives
2. Confirm mock isolation; unit tests should not depend on external services
3. Do not use `sleep` polling in async tests; use `waitUntil(predicate, timeout)`
4. New test files should follow project test directory conventions

## Project-Specific Constraints

<!-- Add project-specific test constraints here, for example: -->
<!-- - Content scripts should not fetch localhost directly -->
<!-- - webextension-polyfill crashes under vitest jsdom in some environments -->
