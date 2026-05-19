# Development and Testing Hygiene

> Trigger: read when starting, finishing, or troubleshooting environment issues. Violating these rules commonly causes port conflicts, memory pressure, and repeated download waste.

## 1. Stop Related Processes at the End of Development/Testing

At the end of each development or testing session, proactively stop all background processes started for that work.

### Scope

- dev server (for example, `npm run dev`, `vite`, `uvicorn`)
- watch process (for example, `vitest --watch`, `pytest -W`)
- browser instances (for example, Playwright `launchPersistentContext`)
- long-running scripts

### Why This Is Required

- **Port conflict**: restarting the same server later may hit `Address already in use`
- **Memory pressure**: orphaned processes consume virtual memory and can trigger swap thrashing
- **AI collaboration**: AI should run a cleanup check at the end of each full dev/test segment.

### Operating Procedure

- **Inspect command** (run once during wrap-up or when suspecting resource issues):
  ```bash
  ps aux | grep -iE 'node|vite|vitest|playwright|python|uvicorn' | grep -v grep
  ```
- **Kill strategy**: use `kill <pid>` (SIGTERM) by default; if there is no response, run `kill -9 <pid>`.
- **AI collaboration**: inspect and clean up after each development/testing segment; do not assume processes exit automatically

## 2. Preserve Project-Specific Assets, Do Not Delete Proactively

Keep **large file assets** used by development/testing as local cache for reuse. Do not delete them proactively, and do not commit them.

### Scope

<!-- Define project-specific assets to retain here, for example: -->
<!-- - Large dependency caches (node_modules, .venv, ~/.cache, etc.) -->
<!-- - Docker images -->
<!-- - Large datasets or binary assets -->

### Why Preserve Assets

- Large assets are expensive to download repeatedly and waste bandwidth/time.
- Development and testing often require repeated behavior verification, so unnecessary re-downloads create avoidable overhead.

### Operating Rules (Hard Boundaries)

- Do not call deletion APIs.
- Do not run `rm -rf` on cache directories.
- Use test-local temporary paths (`pytest tmp_path`, vitest mock), never global cache locations.
- Ensure `.gitignore` covers large assets to avoid accidental commits.

### User-Managed Cleanup

If disk space is needed, the user should perform cleanup manually from the command line. Code paths and automation scripts should not touch cache directories.

## 3. Multi-Step Validation for Large Files and Long Operations

For operations involving large downloads (>100MB) or long-running network paths, perform two-stage validation instead of launching full operations immediately.

### Two-Layer Pattern

| Layer | Purpose | Method | Expected Time |
|----|------|------|---------|
| **smoke** | Validate connectivity, authorization, path write permission | Minimal request with metadata only | Seconds |
| **full** | Validate throughput, mid-flight failures, resume | Full operation, run in background | Tens of seconds to minutes |

### Procedure

1. **Layer 1 smoke (blocking)**: pass connectivity, authorization, and write-path checks; failures should surface quickly.
2. **Layer 2 full (background)**: run full operation only after smoke passes; keep other tasks running in the foreground.
3. Record both layer durations in the Test Plan as evidence.

### Anti-patterns

- Skipping smoke and running full operation directly → long delay before failure is detected.
- Running a full operation in the foreground while blocking → unnecessary serialization.
