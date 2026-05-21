# Git Commit Guidelines

> Trigger: read when creating or amending commits.

## Commit Message Format

Use Conventional Commits format:

```
type(scope): description
```

- **type** (required): `feat` | `fix` | `docs` | `style` | `refactor` | `perf` | `test` | `build` | `ci` | `chore` | `revert`
- **scope** (optional): module name
- **description**: keep it concise and readable; no required language or casing style.

Examples:
- `feat(transcribe): add YouTube auto-caption download`
- `fix: resolve encoding issue in subtitle output`
- `docs: update API usage instructions`
- `chore: add gitignore`

## Commit Principles

- Split commits by logical change; each commit should have a single purpose
- Do not commit directly to the default branch (`__DAYU_DEFAULT_BRANCH__`)
- Route all changes via feature branches + PR merge into the default branch (`__DAYU_DEFAULT_BRANCH__`)

## Automated Checks

Projects use husky + commitlint to block non-compliant commits locally.

- husky hook: `.husky/commit-msg`
- commitlint config: `commitlint.config.cjs`, using `@commitlint/config-conventional`

## Auto Retry on Commit Failures

When `git commit` is rejected by commitlint or commit-msg hook:

1. Read the error output
2. Correct based on error type:
   - **Format error** (invalid type / missing description) → rewrite to match Conventional Commits
   - **Format error** (empty subject / punctuation or blank-line issue) → adjust subject and body so commitlint passes
3. Re-run `git commit`
