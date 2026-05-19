# Versioning and Tagging Protocol

> Trigger: read when assigning versions, creating release tags, cutting releases, or updating tag protection.

## Version Scheme

Follow Semantic Versioning 2.0.0:

```text
v<MAJOR>.<MINOR>.<PATCH>
```

| Change type | Bump | Meaning |
|---------|--------|------|
| BREAKING CHANGE | Major +1 | Incompatible API change |
| feat | Minor +1 | Backward-compatible feature |
| fix | Patch +1 | Backward-compatible bug fix |

Pre-release and build metadata should follow SemVer rules.

## Manual Release Procedure

When no automated release workflow exists:

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

Release notes should focus on user-visible changes; internal-only docs/CI/chore changes should not pollute user-facing changelogs.

## Tag Protection

Release tags:
- Use `v*` naming
- Do not delete
- Do not overwrite existing tags

Implementation:
- Local: release versioning snippet in `.husky/pre-push`
- Remote: GitHub ruleset `.github/rulesets/protect-tags.json`

### Ruleset Application

```bash
gh auth login
gh api -X POST "repos/$OWNER/$REPO/rulesets" --input .github/rulesets/protect-tags.json
```

Web UI: Settings → Rules → Rulesets → New ruleset → Import a ruleset → upload `protect-tags.json`.

On ruleset updates, re-import the new JSON to replace the version. Keep this file in version control for team reuse.
