# docs/harness/sensors/scripts/AGENTS.md

This directory contains maintenance scripts for the governance system. Scripts perform deterministic checks and output structured results; AI interprets those outputs and confirms outcomes with users.

## Directory Index

- [AGENTS.md](AGENTS.md) - Current index
- [audit.mjs](audit.mjs) - Governance integrity diagnostics
- [check-consistency.mjs](check-consistency.mjs) - AGENTS link checks, index checks, orphan file checks, and consistency checks
- [dayu-format.mjs](dayu-format.mjs) - Deterministic renderer for fixed-format PR, Issue, and commit content
- [diff-helper.mjs](diff-helper.mjs) - Change diff and merge-plan descriptions
- [validate.mjs](validate.mjs) - Post-installation / post-change smoke test

Keep this section synchronized when directories, files, or capability deployment manifests change.

## What to run next

- **Governance integrity** → `docs/harness/sensors/scripts/audit.mjs --json <project-root>`
- **Post-change validation** → `docs/harness/sensors/scripts/validate.mjs --json <project-root>`
- **AGENTS consistency check** → `docs/harness/sensors/scripts/check-consistency.mjs --json <project-root>`
- **Fixed-format content generation** → `docs/harness/sensors/scripts/dayu-format.mjs pr-body|issue-body|commit-message ...`
- **Existing vs template diff** → `docs/harness/sensors/scripts/diff-helper.mjs merge-plan <existing> <incoming>`
