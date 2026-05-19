# Code Review Self-Checklist

> Trigger: review PR changes or self-check after completing a segment. This is a quick checklist for frequent issue patterns, not an exhaustive list.

## Common Patterns

1. **Resource cleanup**: file handles, DB connections, and network sockets are closed correctly on error paths.
2. **Input validation**: API path params, `postMessage` origin, and user inputs validate types and boundaries.
3. **Error handling**: avoid over-broad catches (`except Exception` / bare `try/catch`); list expected exception types explicitly.
4. **Concurrency safety**: shared state read/write has no race conditions; singleton/Promise caches clear failure state on rejection.
5. **Boundary conditions**: empty arrays, `null`/`undefined`, oversized input, negative amounts are all handled.
6. **Log hygiene**: no token, password, or PII leakage in error logs.

## Stack-Specific References

> These are common patterns for Node.js/TypeScript projects. Other stacks should use equivalent checks or remove this section.

1. **Missing runtime type checks for external data**: use of `as` assertions or unguarded `json.loads()` parsing -> corresponds to Common Pattern #2.
2. **Utility logic scattered across components**: move shared formatting/conversion logic to a common module, avoid duplication.
3. **Index vs business ID confusion**: list index is not equal to item `index` field after sorting; explicit mapping is required when crossing modules -> corresponds to Common Pattern #4.
