# PR Submission Guidelines

> Trigger: read when creating a PR.

## PR Title

PR titles are readable summaries for humans and tools. Use Chinese, English, or project team language. Ensure the title is natural language, readable, and reflects the value of the change.

Requirements:
- At least 5 characters
- Use a natural-language descriptive title
- If release-please is enabled with merge commit strategy, avoid Conventional Commits format in PR titles to prevent duplicate changelog entries.

## PR Body Template

Three sections + issue trailer:

```markdown
## Summary
<!-- dayu-harness:summary -->

English/Chinese title is acceptable here; machine-check remains compatible with the legacy English format.

<!-- What does this PR do? 1-3 bullet points. -->

-

## Implementation notes
<!-- dayu-harness:implementation-notes -->

<!-- Key decisions, trade-offs, and discovered TODOs. -->

-

## Test plan
<!-- dayu-harness:test-plan -->

<!-- Each bullet MUST start with - [ ] and include an executable command in backticks
     on the same line. -->

- [ ] `command or inline check`

Closes #<issue-number>  # or Fixes/Resolves
```

Critical rules:
- **Keep sections or markers in order**: `## Summary` / `<!-- dayu-harness:summary -->`, `## Implementation notes` / `<!-- dayu-harness:implementation-notes -->`, `## Test plan` / `<!-- dayu-harness:test-plan -->`
- **Machine check compatibility**: both legacy English section titles and marker format are recognized.
- **One of** `Closes #N` / `Fixes #N` / `Resolves #N` must be on its own line.
- **At least one Test plan bullet**: each bullet must start with `- [ ]` and include an executable command in backticks on the same line.

## Prohibit AI Tool Signatures

PR body must not include AI tool watermark text:
- `Generated with [Claude Code]`
- `Co-Authored-By: Claude ...`
- `Generated with Cursor / Copilot / ...`

## Auto Retry on PR Creation Failure

When `gh pr create` fails:

1. Read the error output
2. Fix according to error type:
    - **Invalid title format** → rewrite to natural language descriptive title
    - **Title too short** → expand to at least 5 characters
    - **Branch not pushed** → `git push -u origin <branch>`
    - **Network/authentication error** → retry; report to user after 3 failed attempts
3. Re-run `gh pr create`

## After Creation

- Execute Test plan: if `ai.execution` is enabled, validate each Test plan item per AI execution rules.
- Merge strategy: if `github.branch-protection` is enabled, follow merge strategy in branch protection protocol.

## PR Merge

Use `gh pr merge <PR-number> --merge` (merge commit) to keep all child commits intact in main.

Post-merge cleanup:
```bash
git checkout main
git pull origin main
```

Auto-retry on merge failures:
1. **Merge conflict** → switch to PR branch, rebase main, resolve conflict, and re-push
2. **CI check failed** → wait or fix
3. **Permission denied** → report to user
4. **Network error** → retry; report to user after 3 failed attempts
