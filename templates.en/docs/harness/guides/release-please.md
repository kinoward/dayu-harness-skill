# release-please Automated Releases

> Trigger: read when enabling or maintaining GitHub release-please automation.

## Workflow

release-please auto-generates release PRs, versions, and changelogs from Conventional Commits. Merging the release PR creates tags and GitHub Releases.

Deployment files:
- `.github/workflows/release-please.yml`
- `release-please-config.json`
- `.release-please-manifest.json`

## Prerequisites

- Enable `git.commit-format` so release-please can parse commit types
- Enable `github.pr` so release PRs also follow PR structure and checks
- Enable `release.versioning` so version and tag protection rules are explicit
- Configure `secrets.RELEASE_TOKEN` in the repository

Use a PAT (`secrets.RELEASE_TOKEN`) instead of default `GITHUB_TOKEN` because release-please-created PRs often need to trigger downstream CI checks.

## Changelog Strategy

`release-please-config.json` should expose only user-visible release types by default:
- `feat`
- `fix`
- `perf`

Hide `docs`, `style`, `refactor`, `test`, `build`, `ci`, and `chore` by default to avoid internal maintenance noise.

## Issue Closing

Issue closing keywords belong in PR body only, not individual commit messages. If `github.pr` is enabled, PR body validation checks for `Closes #N` / `Fixes #N` / `Resolves #N`.
