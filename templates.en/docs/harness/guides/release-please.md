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
- Add `workflow.allowed_actors_variable` under `.github/release-please-policy.json` (default: `RELEASE_PLEASE_ALLOWED_ACTORS`)
- Configure `secrets.RELEASE_TOKEN` in the repository

Use a PAT (`secrets.RELEASE_TOKEN`) instead of default `GITHUB_TOKEN` because release-please-created PRs often need to trigger downstream CI checks.

By default, release-please auto-merge and PR lint skip are allowed for:
- `github-actions[bot]`
- `release-please[bot]`
- Only these default bot accounts, unless additional accounts are explicitly listed in `RELEASE_PLEASE_ALLOWED_ACTORS` (comma-separated usernames).

If a release PR author is a regular PAT owner (non-bot), you must configure `RELEASE_PLEASE_ALLOWED_ACTORS` in repository variables with comma-separated usernames. Without this configuration, release-please auto-merge and PR lint skip are not allowed for that actor.

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
