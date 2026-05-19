# Documentation Maintenance Standard

> Trigger: read when adding, modifying, or deleting documentation or constraints. This file keeps the documentation system self-consistent—if the Skill is removed, AI should still execute maintenance operations using this file alone.

## AGENTS.md Hierarchy

```
CLAUDE.md              → Contains only @AGENTS.md reference; no direct content
AGENTS.md              → Project entry; routes by task type to docs and subdirectories
docs/AGENTS.md         → Docs-level index listing all subdirectory entries + standalone docs
docs/<subdir>/AGENTS.md → Subdirectory index for responsibilities and file list
```

### Directory Index Synchronization

Any `## Directory Index` / `## Structure` section present in `AGENTS.md` or `README.md` must be kept in sync when directories, files, or capability manifests change.
`AGENTS.md` should maintain only `## Directory Index` for this level and direct subdirectories; `README.md` may maintain `## Structure` for the project- or post-deployment-wide layout.

`Optional` markers in `AGENTS.md` should only be used for core indexes that reference undeployed non-default capabilities, and must include a valid `Optional: capability.id`. Capabilities with `default=true` must not be marked optional. Internal links inside the same capability should not be marked optional.
Glob patterns and placeholders (for example, `*.md`, `YYYY-MM-DD-vN/`) should not be written as Markdown links; use code text instead.

## Capability Deployment Model

In a target project, runtime authority is in `AGENTS.md`, `docs/`, `docs/harness/sensors/scripts/`, and deployed hook/CI/config assets. The Skill is only the source for initializing/upgrading those artifacts.

A target project defines capabilities by capability manifest and deploys them as `default + optional module`:

- `default`: required governance capabilities that do not require user selection, including `core`, Git commit/.gitignore constraints, AI execution/memory rules, ADR, troubleshooting, research, project context, and archive entrypoints
- `optional module`: optional governance modules deployed to the target project (GitHub CI, release-please, Node.js tooling, branch/tag protection, etc.)

Linked components are files, hooks, CI, and scripts deployed by governance capabilities.
When adding governance capabilities, update the capability manifest first; optional capabilities not enabled are not effective in the target project.
After deployment, target project behavior does not depend on internal Skill file paths; to add an uninstalled capability later, reinstall the Skill or manually bring in the corresponding module.

### Core Principles

- **One level only**: `AGENTS.md` lists files and direct subdirectory entries for its directory only.
- **Progressive navigation**: AI starts from root `AGENTS.md` and drills down by task type.
- **Subdirectories must have AGENTS.md**: every direct `docs/` subdirectory must contain its own entrypoint AGENTS.
- **Index-only indexing**: `AGENTS.md` should contain only heading + trigger + links; detailed content lives in standalone documents.
- **Index sync**: maintain directory lists, links, and `## Directory Index` together to avoid drift from real files or enabled capabilities.

### Trigger Block Format

Each root `AGENTS.md` section must include a blockquote that describes when to read it:

```markdown
## Section Title

> Trigger description

See [link](path).
```

## Docs Content Classification

The `docs/` tree is organized by purpose while preserving physical directories; do not split into `project-docs/` or `ai-docs/`.

| Type | Meaning | Directory |
|------|---------|-----------|
| **Governance constraints** | Rules AI must follow when collaborating with humans, feedback checks, and maintenance flow | `harness/`, `harness/guides/`, `harness/sensors/`, all `AGENTS.md` levels |
| **Project knowledge/experience** | Summarized decisions, troubleshooting knowledge, and research conclusions for reuse | `design-docs/`, `troubleshooting/`, `references/research/` |
| **Project content** | Project-specific specs, context, and background; not behavior rules | `product-specs/` |
| **Execution artifacts** | Execution plans, temporary reports, drafts, and generated materials | `exec-plans/`, `generated/` |
| **Archive** | Historical material no longer current authority | `archive/` |

Governance constraints define how AI should act. Project knowledge and experience explain why the project chose certain approaches and how issues are handled. Project content describes what the project is, what to build, and who it serves.

## Project Memory Boundary

In-project long-lived truth is `AGENTS.md` + `docs/`. AI or external tools may use agent memory, LangChain/LangGraph stores, vector databases, or product-internal memory for runtime retrieval, session recovery, and context recall. These do not replace repository documentation and are not authoritative governance rules.

Before writing to long-lived directories, summarize:
- reusable conclusions, assumptions, applicability, validation method, and expiry conditions
- avoid storing full chat transcripts, temporary hypotheses, unconfirmed proposals, repeated reasoning traces, or sensitive content
- place generated material first in `docs/generated/`, then promote to `design-docs/`, `troubleshooting/`, `references/research/`, `product-specs/`, or `harness/guides/` after confirmation
- value from external memory systems must be normalized into project docs and reflected in corresponding `AGENTS.md` index entries before being treated as long-term memory

## Constraint Lifecycle Management

### Add Constraint

1. Choose target directory: execution style docs to `harness/guides/`; architecture and decisions to `design-docs/`; troubleshooting to `troubleshooting/`; research outcomes to `references/research/`; project specs and context to `product-specs/`.
2. Create the document file using the naming and directory rules below.
3. If linked governance capabilities are affected, update the capability manifest and deploy associated modules.
4. Update the directory’s `AGENTS.md`, add file entries, and sync related `## Directory Index` sections (including `README.md` `## Structure`).
5. Update the "Document-Script Coupling" section if involved.
6. Validate navigation by walking from root `AGENTS.md` to the new document through each level.

### Modify Constraint

1. Locate affected docs and scripts (refer to the Document-Script Coupling section).
2. Edit documentation content.
3. If scripts change, update corresponding scripts too.
4. If index changes (file add/remove), update affected `AGENTS.md` and synchronize the related `## Directory Index` sections (and `README.md` `## Structure`).
5. Use `docs/harness/sensors/scripts/diff-helper.sh` to generate a change description: use `docs/harness/sensors/scripts/diff-helper.sh merge-plan <existing> <incoming>` when a source file exists. If there is no matching file, manually review against `scaffold.sh --dry-run`.
6. Run `docs/harness/sensors/scripts/validate.sh` if available.

### Remove Constraint

1. Analyze impact range by checking coupling entries in the Document-Script Coupling table.
2. List all affected documents and coupled components.
3. After user confirmation:
   - Remove document files
   - Remove linked coupled components
   - Update all affected `AGENTS.md` index sections and related `## Directory Index` blocks (including `README.md` `## Structure`)
   - Update coupling tables
4. Validate: ensure no dangling references remain.

## Diagnostics and Integrity Checks

### Automated Diagnostics

Prefer `docs/harness/sensors/scripts/audit.sh` when present. If unavailable, perform checks manually using the list below.

### Check List

1. **AGENTS.md Link Chain**
   - Root `CLAUDE.md` exists and contains `@AGENTS.md`
   - Root `AGENTS.md` exists and its links resolve
   - `docs/AGENTS.md` exists and listed subdirectories exist
   - Each subdirectory `AGENTS.md` exists and listed files actually exist
- `## Directory Index` in `AGENTS.md` and `## Structure` in `README.md` match real directories and deployed capabilities

2. **Index Consistency**
   - Files listed in each `AGENTS.md` match actual directory contents
   - Detect orphan files not referenced by any `AGENTS.md`
   - Detect broken references to non-existent files

3. **Coupled Constraint Completeness**
   - Coupled components are deployed and executable according to capability manifest
   - Each rule in coupling tables maps to both documentation and coupled components

4. **Naming Standards**
   - File names should be lowercase letters and hyphens
   - Versioned directories should use `YYYY-MM-DD-vN`

## Interactive Q&A Reference

These constraints feed interactive Q&A. `default=true` capabilities are not asked as enable/disable questions; they only affect merge behavior when existing content is detected. Optional capabilities appear as enable/skip choices.
Actual enabled items, dependencies, templates, assets, and acceptance checks follow the capability manifest. If any mismatch is found, update the manifest first, then this section.

### Git-related

| capability | Constraint | Implementation | Coupled components | Applicable when |
|---|------|---------|---------|---------|
| `git.commit-format` | Commit message format checks | husky snippet + commitlint | commit-msg snippet + commitlint config | Always on |
| `project.gitignore` | Ignore policy management | gitignore installer | .gitignore | Always on |

### GitHub and Release Optional Capabilities

| capability | Constraint | Implementation | Coupled components | Applicable when |
|---|------|---------|---------|---------|
| `github.pr` | PR workflow standards | Documentation rules + optional CI | pr-lint.yml (GitHub-only) | GitHub projects |
| `github.branch-protection` | Branch protection | Documentation rules + ruleset + hook snippet | protect-main ruleset + pre-push snippet | GitHub projects |
| `release.versioning` | Version and tag protection | Documentation rules + tag ruleset + hook snippet | protect-tags ruleset + pre-push snippet | Release-based projects |

### Code Quality

| capability | Constraint | Implementation | Coupled components | Applicable when |
|---|------|---------|---------|---------|
| `quality.practices` | Development discipline and testing strategy | Documentation guidance | dev-hygiene + testing-strategy | Code projects |
| `quality.node-tooling` | Node.js style and formatting | ESLint + Prettier + lint-staged + hook snippet | eslint config + prettier config + lint-staged config + pre-commit snippet | Node.js projects |

### Development Guidelines

| capability | Constraint | Implementation | Coupled components | Applicable when |
|---|------|---------|---------|---------|
| `quality.practices` | Development environment discipline | Documentation guidance + validate.sh | — | Code projects |
| `ai.execution` | AI execution style | Documentation rules | — | Always on |
| `ai.memory` | AI memory boundaries | Documentation rules | — | Always on |

### Knowledge Management

| capability | Constraint | Implementation | Coupled components | Applicable when |
|---|------|---------|---------|---------|
| `knowledge.adr` | Decision records (ADR) | `docs/design-docs/` directory + template | adr-template.md | Always on |
| `knowledge.troubleshooting` | Troubleshooting knowledge base | `docs/troubleshooting/` directory | — | Always on |
| `knowledge.research` | Versioned research | `docs/references/research/` directory | — | Always on |
| `project.context` | Project specs and context | `docs/product-specs/` directory | — | Always on |
| `knowledge.archive` | Historical archive | `docs/archive/` directory | — | Always on |

### Document-Script Coupling

| capability | Coupled components | Notes |
|------|---------|------|
| `git.commit-format` | commit-msg commitlint snippet + commitlint config | Enforces commit format validation only |
| `github.pr` | PR validation (`pr-lint.yml` + `pr_body_structure.py`) | GitHub CI integration only |
| `github.branch-protection` | protect-main ruleset + pre-push branch snippet | Double protection: remote GitHub ruleset + local pre-push snippet |
| `release.versioning` | protect-tags ruleset + pre-push tag snippet | Tag protection and version conventions |
| `quality.node-tooling` | ESLint + Prettier + lint-staged + pre-commit snippet | Complex configuration should still be reviewed by humans |
| `project.gitignore` | .gitignore installer | Merge universal/node/python templates by project type |
| `github.release-please` | release-please.yml + guide + config + manifest | GitHub-only; depends on `git.commit-format` + `github.pr`; requires PAT |
| `diagnostics` | audit.sh + check-consistency.sh | Automated documentation integrity checks |

> Document-only capabilities (`ai.execution`, `ai.memory`, knowledge directories) are enforced with `default=true` and are not asked in capability questions. Optional capabilities remain under manifest control.

## Compatibility Handling Workflow

When modifying existing configuration, use this flow (AI may drive this manually or with `diff-helper.sh`):

1. **Detect**: Check whether target config already exists (for example, `.husky/commit-msg`, `commitlint.config.cjs`).
2. **Analyze differences**: Evaluate coupled components one by one: for installer-backed components (for example, husky snippets and `.gitignore`), use the corresponding `--check` to get a structured merge plan; for static template/assets without an installer (for example, `commitlint.config.cjs`, `eslint.config.cjs`, `.prettierrc`, `.lintstagedrc.json`, GitHub workflows, and ruleset JSON), use `scaffold.sh --dry-run`; if an existing file can be paired with incoming config, add `diff-helper.sh merge-plan <existing> <incoming>`, otherwise continue manual review from `scaffold.sh --dry-run`.
3. **Describe changes**: Provide human-readable change text. Example: “Your project already has `.husky/commit-msg` with Conventional Commits checks. New content can co-exist and does not alter existing behavior.”
4. **User confirmation**: For existing config handling only offer [1] Keep existing [2] Replace [3] Merge [4] Skip. Default capabilities should not offer skip.
5. **Execute**: Apply based on user choice.
6. **Validate**: Verify results (hook executability and config syntax).

## Interactive Q&A Guidance

> When AI needs to guide users through initialization or expansion, follow this flow to preserve quality even without the Skill.

### Pre-check Steps

Before asking questions, assess the current project state:

1. Run `scripts/ensure-environment.sh <project-root> --check --capabilities "<resolved capability ids>"` to confirm environment and initialization state. If optional capabilities are not determined, omit `--capabilities` and check defaults.
2. Check whether `CLAUDE.md`, `AGENTS.md`, and `docs/` exist.
3. Check existing `.husky/`, `commitlint.config.cjs`, `.github/workflows/`.
4. Tailor questions based on detected state: default capabilities are not asked to enable/disable; existing files only ask whether to keep/extend/skip.

If pre-check indicates missing dependencies or missing Git:
- Ask user to run `git init` first.
- For Node-based governance tooling (husky/commitlint/lint-staged), ask for `npm init -y` first.
- If required dependencies are missing, ask user to run the `npm install --save-dev ...` command from script guidance.
- Clarify these dependencies are for governance tooling, not proof that the project must be a Node.js app; do not replace project initialization with a template `package.json`.
If initialization is refused, stop immediately and wait for the next user step.

### Question Templates

Ask in plain language, not only technical jargon:

| Constraint | Suggested wording |
|------|------------|
| Commit message format checks | “Each git commit will be automatically validated against Conventional Commits. Enabling this installs husky and commitlint as local checks.” |
| PR workflow standards | “Define PR title/body templates and test-plan format. If GitHub is used, you can also enable automated CI checks.” |
| Code quality practices | “You can enable core development/testing practices, and optionally add ESLint + Prettier + lint-staged for Node.js projects.” |
| AI execution and memory | “Define human-AI division of work, autonomous execution rules, and project-memory boundaries for experience capture.” |

### Confirmation Summary Format

After questions, show summary:

```
## Confirmation Summary

### Enabled Constraints
- Commit message format checks → install commit-msg commit-message check + commitlint
- AI execution and memory → deploy ai-execution.md and ai-memory.md
- Knowledge and project context → deploy ADR, troubleshooting, research, product specs, and archive entrypoints

### Coupled Components
- .husky/commit-msg
- commitlint.config.cjs
- .gitignore

### Skipped Items
- Coding quality and test discipline (user selected skip)
- GitHub PR / Issue workflow (user selected skip)

[1] Proceed [2] Roll back [3] Cancel
```

### Merge-mode Prompt Extension

When existing config is detected, ask:

> Your project already has `.husky/commit-msg` with Conventional Commits validation. How should we handle it?
> [1] Keep existing config untouched
> [2] Replace with new template
> [3] Merge — keep existing validation and show detailed changes (I will provide a diff summary)
> [4] Skip this item

## File Naming Rules

- Use lowercase kebab-case for file names (for example, `commit-guidelines.md`)
- Versioned directory format: `YYYY-MM-DD-vN` (for example, `2026-04-17-v3`)
- Chinese file names are only allowed in `product-specs/` and `archive/product-specs/`

## New Document Flow

1. Create `.md` files in the target directory. Governance and knowledge docs should use English naming by default; project specs/context may use Chinese naming.
2. Update that directory’s `AGENTS.md`, add file entries, and sync the directory `## Directory Index`.
3. If adding a new subdirectory, create its `AGENTS.md`, add the subdirectory entry to the parent `AGENTS.md`, and sync all affected `## Directory Index` sections (and `README.md` `## Structure`).
