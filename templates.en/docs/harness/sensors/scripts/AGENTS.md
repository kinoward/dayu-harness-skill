# docs/harness/sensors/scripts/AGENTS.md

This directory contains maintenance scripts for the governance system. Scripts perform deterministic checks and output structured results; AI interprets those outputs and confirms outcomes with users.

## Directory Index

- [AGENTS.md](AGENTS.md) - Current index
- [audit.sh](audit.sh) - Governance integrity diagnostics
- [check-consistency.sh](check-consistency.sh) - AGENTS link checks, index checks, orphan file checks, and consistency checks
- [dayu-format.mjs](dayu-format.mjs) - Deterministic renderer for fixed-format PR, Issue, and commit content
- [diff-helper.sh](diff-helper.sh) - Change diff and merge-plan descriptions
- [validate.sh](validate.sh) - Post-installation / post-change smoke test

Keep this section synchronized when directories, files, or capability deployment manifests change.

## What to run next

- **Governance integrity** → `docs/harness/sensors/scripts/audit.sh --json <project-root>`
- **Post-change validation** → `docs/harness/sensors/scripts/validate.sh --json <project-root>`
- **AGENTS consistency check** → `docs/harness/sensors/scripts/check-consistency.sh --json <project-root>`
- **Fixed-format content generation** → `docs/harness/sensors/scripts/dayu-format.mjs pr-body|issue-body|commit-message ...`
- **Existing vs template diff** → `docs/harness/sensors/scripts/diff-helper.sh merge-plan <existing> <incoming>`
