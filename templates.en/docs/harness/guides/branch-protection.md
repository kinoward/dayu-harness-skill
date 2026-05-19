# Branch Protection Protocol

> Trigger: read when creating/pushing branches, merging PRs, or adjusting repository branch protection.

## Branching Strategy

- Do not push directly to `main` / `master`.
- Create feature branches from the main branch with prefixes such as `feat/`, `fix/`, `docs/`, `chore/`.
- All changes must be merged into the main branch through PR.
- Branch names should follow Git conventions (printable characters, no spaces, no special characters); prefer tool-friendly slugs (for example, `feat/xxx`, `fix/xxx`).

Default GitHub Flow is recommended: main branch → short-lived feature branch → PR → merge → delete branch.

## Merge Strategy

| Strategy | Command | Use case |
|------|------|---------|
| merge commit | `gh pr merge --merge` | Team collaboration while keeping full commit history |
| squash | `gh pr merge --squash` | Small feature changes, squashed into one commit |
| rebase | `gh pr merge --rebase` | Personal projects, linear history |

Default is merge commit. If release-please is enabled, follow Conventional Commits for commit messages and use natural-language PR titles to avoid duplicate changelog entries.

## Post-merge Cleanup

```bash
git checkout main
git pull origin main
```

## Protection Rules

Main branch protection:
- No deletion
- No direct local pushes, including fast-forward and non-fast-forward
- Merge only through PR

Implementation:
- Local: `branch protection` snippet in `.husky/pre-push` blocks direct `main` / `master` pushes
- Remote: GitHub ruleset `.github/rulesets/protect-main.json`

### Ruleset Application

```bash
gh auth login
gh api -X POST "repos/$OWNER/$REPO/rulesets" --input .github/rulesets/protect-main.json
```

Web UI path: Settings → Rules → Rulesets → New ruleset → Import a ruleset → upload `protect-main.json`.

Keep this ruleset file under version control and re-import it after branch protection policy changes.
