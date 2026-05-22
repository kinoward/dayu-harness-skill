# Issue Governance Guide

> Trigger: read when `github.issue` is enabled or when GitHub Issue workflow is part of your project process.

## Goal

- Express issue dependencies in a structured way to reduce incorrect execution order.
- Let automation and AI use a consistent rule to understand handling priority.
- Keep issue metadata lightweight without relying on label taxonomy or bot comments.

## Dependency Convention

Issue bodies are fixed-format content. AI should extract structured fields such as summary, background, and depends-on issue numbers, then generate the body with deterministic tooling:

```bash
docs/harness/sensors/scripts/dayu-format.mjs issue-body \
  --summary "Problem or task to handle" \
  --background "Relevant context" \
  --depends-on 12
```

Use `Depends on: #N` to express ordering:

- `Depends on: #N` means the current issue should be handled after issue `#N`.
- This is an ordering hint only, not a hard blocker, and does not replace human risk assessment.
- AI/automation should use dependency direction for scheduling suggestions, while allowing parallel execution when review and context permit.

## Boundaries for Language and Automation Behavior

- **No labels**: this capability does not add or enforce issue labels automatically.
- **No auto comments**: this capability does not post comments automatically.
- **No language linting**: this capability does not validate issue body language.
- **Focus on pattern checks**: scripts validate only the strict single-line `Depends on: #N` format.

## Quick Checks

1. Verify `Depends on: #N` appears in issue body when used.
2. Supported strict format is `Depends on: #N` or `Depends on: #N, #M`, and at most one such line is allowed.
3. Report formatting errors only; it does not resolve or validate issue number existence.

## Coordination with PR and Release

- This rule complements PR closing trailers, but does not replace PR closing-location validation.
- PR trailer checks remain in the PR workflow capability (`github.pr`).
