# GitHub Repository Settings

> Optional capability: `github.repository-settings`

This file explains how repository-level PR settings stay aligned with project governance assets. After the user chooses Enable in the `/dayu-harness` Q&A flow, `scaffold.sh --apply` directly calls the GitHub API to modify the target remote repository settings; `--dry-run` only previews the operation.

## Deployed Files

- `.github/repository/pull-request-settings.json`: repository PR settings policy.

The current policy is locked to:

```json
{
  "allow_merge_commit": true,
  "allow_squash_merge": false,
  "allow_rebase_merge": false,
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
```

## Remote Apply Behavior

When `github.repository-settings` is enabled, the scaffold apply step automatically performs the equivalent operation:

```bash
gh api -X PATCH "repos/<owner>/<repo>" \
  -F allow_merge_commit=true \
  -F allow_squash_merge=false \
  -F allow_rebase_merge=false \
  -F allow_auto_merge=true \
  -F delete_branch_on_merge=true
```

Before applying, these requirements must be met:

- `gh auth status` is authenticated for the target GitHub account.
- The current account has repository administration permission.
- release-please or other auto-merge flows use GitHub auto-merge instead of a manual label gate.
- The default-branch ruleset allows merge commits only; repository-level squash/rebase entry points should stay disabled to avoid bypassing release-please changelog deduplication.

The scaffold resolves the target repository in this order:

1. `DAYU_HARNESS_GITHUB_REPOSITORY=owner/repo`
2. The target project's GitHub `origin` remote
3. The current repository resolved by `gh repo view`

To manually replay the remote settings, run the `gh api` command above from the target project.

## Maintenance Rules

- This config expresses repository-level facts; it does not replace branch protection rulesets.
- After changing `.github/repository/pull-request-settings.json`, update this file too.
- Keep `allow_merge_commit=true`, `allow_squash_merge=false`, and `allow_rebase_merge=false` so the repository UI/API matches the default-branch merge-only ruleset.
- If release-please depends on auto-merge, keep `allow_auto_merge` set to `true`.
- If release branches should be cleaned up after merge, keep `delete_branch_on_merge` set to `true`.
