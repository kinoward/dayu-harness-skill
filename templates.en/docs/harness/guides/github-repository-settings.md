# GitHub Repository Settings

> Optional capability: `github.repository-settings`

This file explains how repository-level PR settings stay aligned with project governance assets. The Skill only deploys configuration files and operational instructions; it does not automatically modify the GitHub remote repository.

## Deployed Files

- `.github/repository/pull-request-settings.json`: repository PR settings policy.

The current policy is locked to:

```json
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
```

## Apply to Remote

After confirming the repository owner/name, a maintainer can run this in the target project:

```bash
gh api -X PATCH "repos/<owner>/<repo>" \
  -F allow_auto_merge=true \
  -F delete_branch_on_merge=true
```

Before running it, confirm:

- `gh auth status` is authenticated for the target GitHub account.
- The current account has repository administration permission.
- release-please or other auto-merge flows use GitHub auto-merge instead of a manual label gate.

## Maintenance Rules

- This config expresses repository-level facts; it does not replace branch protection rulesets.
- After changing `.github/repository/pull-request-settings.json`, update this file too.
- If release-please depends on auto-merge, keep `allow_auto_merge` set to `true`.
- If release branches should be cleaned up after merge, keep `delete_branch_on_merge` set to `true`.
