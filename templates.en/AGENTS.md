# AGENTS.md

This file is the project-level routing entry. Read it first for task-based direction, then open [docs/AGENTS.md](docs/AGENTS.md) and any enabled capability documents.

> **Phase**: ACTIVE
> **Focus**: Git / GitHub / Documentation Governance
> **Status Snapshot**: [docs/product-specs/project-status.md](docs/product-specs/project-status.md)
> **Rule**: Follow this file and `docs/` rules

## Directory Index

The directory index for this level must be kept in sync when directories, files, or capability deployment manifests change.

- [AGENTS.md](AGENTS.md) - Current index
- [CLAUDE.md](CLAUDE.md) - Task routing entry
- [docs/AGENTS.md](docs/AGENTS.md) - Documentation directory index
- [docs/harness/AGENTS.md](docs/harness/AGENTS.md) - Governance rules, feedback checks, maintenance workflow
- [docs/design-docs/AGENTS.md](docs/design-docs/AGENTS.md) - Default: ADRs and design decisions
- [docs/exec-plans/AGENTS.md](docs/exec-plans/AGENTS.md) - Execution plans
- [docs/generated/AGENTS.md](docs/generated/AGENTS.md) - Auto-generated material index
- [docs/product-specs/AGENTS.md](docs/product-specs/AGENTS.md) - Default: product specs and project context
- [docs/references/AGENTS.md](docs/references/AGENTS.md) - Default: external references and research index
- [docs/troubleshooting/AGENTS.md](docs/troubleshooting/AGENTS.md) - Default: troubleshooting knowledge base
- [docs/archive/AGENTS.md](docs/archive/AGENTS.md) - Default: historical archive
- `.husky/` - Default: local Git hooks
- `.github/` - Optional: GitHub workflows, rulesets, and helper scripts
- `*` - Default: commitlint, .gitignore; Optional: ESLint, Prettier, release-please, etc. (examples only)

## Mechanized Checks

- Documentation governance integrity diagnosis: `docs/harness/sensors/scripts/audit.sh`
- Post-change health check: `docs/harness/sensors/scripts/validate.sh`
- AGENTS index consistency check: `docs/harness/sensors/scripts/check-consistency.sh`

## Reading Order

- Project entry: this file
- Docs index: [docs/AGENTS.md](docs/AGENTS.md)
- Harness governance entry: [docs/harness/AGENTS.md](docs/harness/AGENTS.md)
- Guide index (pre-action rules): [docs/harness/guides/AGENTS.md](docs/harness/guides/AGENTS.md)
- Sensor checks index (post-action checks): [docs/harness/sensors/AGENTS.md](docs/harness/sensors/AGENTS.md)
- Documentation maintenance: [docs/harness/maintenance.md](docs/harness/maintenance.md)

## Before Commit

> Trigger: before every `git commit` or when a hook rejects a commit.
- Read `docs/harness/guides/commit-guidelines.md`
- Read `docs/harness/guides/ai-execution.md`
- Generate fixed-format commit messages with `docs/harness/sensors/scripts/dayu-format.mjs commit-message ...` or a CLI such as Commitizen/cz-git instead of free-form model text

## Before PR Create/Update

> Trigger: creating a PR, editing PR content, or when CI feedback fails.
- When the PR governance guide exists, read `docs/harness/guides/pr-guidelines.md`
- When the fixed-format PR body generator exists, render the PR body with `docs/harness/sensors/scripts/dayu-format.mjs pr-body ...`, then pass it through `gh pr create --body-file`
- Close linked issues with GitHub closing keyword trailers, e.g. `Closes #123`

## During Release, PR Review, and Troubleshooting

> Trigger: branch release, reviewing changes, process/environment issues.
- When the Git main-branch protection guide exists, read `docs/harness/guides/branch-protection.md`
- When the release versioning and tag protection guide exists, read `docs/harness/guides/release-versioning.md`
- When the automated version release guide exists, read `docs/harness/guides/release-please.md`
- When the PR review checklist exists, read `docs/harness/sensors/reviews/code-review-checklist.md`
- When the development quality guide exists, read `docs/harness/guides/dev-hygiene.md`

## During AI-led Execution

> Trigger: AI takes over implementation or execution.
- Read `docs/harness/guides/ai-execution.md`
- Read `docs/harness/guides/ai-memory.md`
- When the testing strategy guide exists, read `docs/harness/guides/testing-strategy.md`

## Reviewing Knowledge and Project Context

> Trigger: understanding context, troubleshooting, tech trade-offs, project documentation.
- Open `docs/design-docs/`, `docs/troubleshooting/`, `docs/references/research/`
- Open `docs/product-specs/` or `docs/archive/`
- Place auto-generated materials in `docs/generated/`, then confirm and promote to long-term locations.

## Documentation and Constraint Maintenance

> Trigger: creating, changing, or deleting documentation/constraints.
- First read [docs/harness/maintenance.md](docs/harness/maintenance.md)
