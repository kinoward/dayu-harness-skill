# release-please Automated Releases

> Trigger: read when enabling or maintaining GitHub release-please automation.

## Workflow

release-please auto-generates release PRs, versions, and changelogs from Conventional Commits. Merging the release PR creates tags and GitHub Releases.

Deployment files:
- `.github/workflows/release-please.yml`
- `.github/release-please-policy.json`
- `release-please-config.json`
- `.release-please-manifest.json`
- `.github/scripts/release_please_policy.py`

## Prerequisites

- Enable `git.commit-format` so release-please can parse commit types
- Use `github.pr` for regular PR checks; allowed release-please PRs skip PR lint, while the release workflow and `release-please-policy` enforce release safety boundaries.
- Enable `release.versioning` so version and tag protection rules are explicit
- Enable `github.repository-settings` to complete repository-side policy prerequisites
- GitHub Actions workflow permissions must be `default_workflow_permissions=write` with `can_approve_pull_request_reviews=true`
- The release workflow uses `secrets.GITHUB_TOKEN`; no extra PAT secret is required

The workflow intentionally uses `GITHUB_TOKEN` so release PRs do not trigger Dayu-managed PR/Issue/TDD CI or token-derived follow-up workflow runs. The release workflow closes the loop by dispatching `workflow_dispatch mode=publish` after the release PR merges.

By default, release-please auto-merge and PR lint skip are allowed for:
- `github-actions[bot]`
- `release-please[bot]`

Regular PAT owners and extra actor variables are not valid release PR bypasses. The release PR must come from the same repository, target the default branch, match the `release-please--` branch prefix, and only modify release files allowed by `.github/release-please-policy.json`.

`release-please` no longer uses `autorelease` label-based bypassing, and `pull_request_target` + `labeled` label gates are intentionally not supported.

## Changelog Strategy

`release-please-config.json` keeps the full Conventional Commit type set visible by default:
- `feat`
- `fix`
- `perf`
- `refactor`
- `revert`
- `docs`
- `style`
- `test`
- `build`
- `ci`
- `chore`

Do not configure these sections as `hidden: true`. `release_please_policy.py` rejects hidden changelog sections so CHANGELOG and GitHub Release notes retain a complete historical record.

## Path Filter Strategy

`release-please` scope filtering is maintained in `.github/release-please-policy.json`. Path and package selection rules are configured in this policy file to avoid duplicating behavior in other release-please config.

## Issue Closing

Issue closing keywords belong in PR body only, not individual commit messages. For regular PRs, PR body validation checks `Closes #N` / `Fixes #N` / `Resolves #N`.
For allowed release-please PRs that skip PR lint, release safety is enforced by the release workflow and `release-please-policy`.
