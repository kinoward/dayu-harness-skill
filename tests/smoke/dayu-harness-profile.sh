#!/usr/bin/env bash
# Profiled test entrypoint for Dayu Harness Skill maintenance.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROFILE="local-fast"
JSON_MODE=false

usage() {
    cat <<'EOF'
Usage: tests/smoke/dayu-harness-profile.sh [--profile local-fast|remote-smoke|remote-release] [--json]

Profiles:
  local-fast      Run local generation and validation checks only.
  remote-smoke    Opt-in disposable GitHub repo smoke for Issue -> PR flow.
  remote-release  Opt-in release-please remote flow; checks docs/chore negative gates and feat positive trigger.

Remote profiles are gated:
  RUN_DAYU_REMOTE_SMOKE=1 tests/smoke/dayu-harness-profile.sh --profile remote-smoke
  RUN_DAYU_REMOTE_RELEASE=1 tests/smoke/dayu-harness-profile.sh --profile remote-release
EOF
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

emit_json() {
    local status="$1"
    local profile="$2"
    local detail="$3"
    printf '{"status":"%s","profile":"%s","description_nl":"%s"}\n' \
        "$(json_escape "$status")" \
        "$(json_escape "$profile")" \
        "$(json_escape "$detail")"
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "required command missing: $cmd" >&2
        exit 2
    fi
}

github_owner() {
    if [ -n "${DAYU_REMOTE_OWNER:-}" ]; then
        printf '%s\n' "$DAYU_REMOTE_OWNER"
    else
        gh api user --jq .login
    fi
}

visibility_args() {
    case "${DAYU_REMOTE_VISIBILITY:-private}" in
        public) printf '%s\n' "--public" ;;
        private|"") printf '%s\n' "--private" ;;
        *)
            echo "DAYU_REMOTE_VISIBILITY must be private or public" >&2
            exit 2
            ;;
    esac
}

seed_project() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -b main >/dev/null 2>&1 || {
        git -C "$dir" init >/dev/null
        git -C "$dir" branch -M main
    }
    git -C "$dir" config user.name "dayu-harness-smoke"
    git -C "$dir" config user.email "dayu-harness-smoke@example.com"
    cat > "$dir/package.json" <<'JSON'
{"name":"dayu-harness-remote-smoke","version":"0.1.0","devDependencies":{"@commitlint/cli":"0.0.0","@commitlint/config-conventional":"0.0.0"}}
JSON
    printf '# dayu-harness remote smoke\n' > "$dir/README.md"
    printf '0.1.0\n' > "$dir/VERSION"
    printf '# Changelog\n\n## 0.1.0\n\n- Initial smoke baseline.\n' > "$dir/CHANGELOG.md"
}

cleanup_remote_repo() {
    local repo="$1"
    local dir="$2"
    if [ "${DAYU_KEEP_REMOTE_REPO:-}" != "1" ]; then
        gh repo delete "$repo" --yes >/dev/null 2>&1 || true
    fi
    rm -rf "$dir"
}

wait_issue_closed() {
    local repo="$1"
    local issue="$2"
    local deadline=$((SECONDS + ${DAYU_REMOTE_TIMEOUT_SECONDS:-600}))
    local state=""
    while [ "$SECONDS" -lt "$deadline" ]; do
        state="$(gh issue view "$issue" --repo "$repo" --json state --jq .state 2>/dev/null || true)"
        if [ "$state" = "CLOSED" ]; then
            return 0
        fi
        sleep 10
    done
    echo "issue #$issue did not close; last state: ${state:-unknown}" >&2
    return 1
}

wait_workflow_success() {
    local repo="$1"
    local workflow="$2"
    local head_sha="$3"
    local event_filter="${4:-push}"
    local created_after="${5:-}"
    local deadline=$((SECONDS + ${DAYU_REMOTE_TIMEOUT_SECONDS:-900}))
    local run_json status conclusion run_id event
    while [ "$SECONDS" -lt "$deadline" ]; do
        run_json="$(gh run list --repo "$repo" --workflow "$workflow" --json databaseId,headSha,status,conclusion,event,createdAt --limit 20 2>/dev/null | jq -c --arg sha "$head_sha" --arg event "$event_filter" --arg after "$created_after" '[.[] | select(.headSha == $sha and .event == $event and ($after == "" or .createdAt >= $after))] | .[0] // empty' || true)"
        if [ -n "$run_json" ]; then
            status="$(printf '%s' "$run_json" | jq -r '.status // empty')"
            conclusion="$(printf '%s' "$run_json" | jq -r '.conclusion // empty')"
            run_id="$(printf '%s' "$run_json" | jq -r '.databaseId // empty')"
            event="$(printf '%s' "$run_json" | jq -r '.event // empty')"
            if [ "$status" = "completed" ]; then
                [ "$conclusion" = "success" ] && [ "$event" = "$event_filter" ] && return 0
                echo "$workflow run $run_id completed with conclusion ${conclusion:-unknown} and event ${event:-unknown}" >&2
                return 1
            fi
        fi
        sleep 15
    done
    echo "$workflow did not complete for $head_sha and event $event_filter" >&2
    return 1
}

run_remote_smoke() {
    require_cmd gh
    require_cmd git
    require_cmd jq
    gh auth status >/dev/null

    local owner repo tmp project vis bootstrap_issue_url bootstrap_issue_number issue_url issue_number issue_body issue_lint_after branch pr_url pr_number main_sha
    owner="$(github_owner)"
    repo="${DAYU_REMOTE_REPO:-$owner/dayu-harness-remote-smoke-$(date +%s)}"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/dayu-remote-smoke.XXXXXX")"
    project="$tmp/project"
    trap "cleanup_remote_repo '$repo' '$tmp'" EXIT

    seed_project "$project"
    bash "$REPO_ROOT/scripts/scaffold.sh" "$project" --apply --enable github.issue,github.pr --strategy merge --github-remote skip >/dev/null
    git -C "$project" add .
    git -C "$project" commit -m "chore: deploy dayu harness remote smoke" >/dev/null
    vis="$(visibility_args)"
    (cd "$project" && gh repo create "$repo" $vis --source=. --remote=origin >/dev/null)
    git -C "$project" push -u origin main >/dev/null
    main_sha="$(git -C "$project" rev-parse main)"

    bootstrap_issue_url="$(gh issue create --repo "$repo" --title "Remote smoke dependency" --body $'## Summary\n\n- Bootstrap dependency for remote smoke.\n\n## Background\n\n- Disposable remote-smoke repository.\n')"
    bootstrap_issue_number="${bootstrap_issue_url##*/}"
    wait_workflow_success "$repo" "issue-lint.yml" "$main_sha" "issues"
    issue_lint_after="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    issue_body="$(printf '## Summary\n\n- Verify Issue -> PR governance.\n\n## Background\n\n- Disposable remote-smoke repository.\n\nDepends on: #%s\n' "$bootstrap_issue_number")"
    issue_url="$(gh issue create --repo "$repo" --title "Remote smoke issue" --body "$issue_body")"
    issue_number="${issue_url##*/}"
    wait_workflow_success "$repo" "issue-lint.yml" "$main_sha" "issues" "$issue_lint_after"
    branch="fix/remote-smoke-$issue_number"
    git -C "$project" switch -c "$branch" >/dev/null
    mkdir -p "$project/src"
    printf 'remote smoke %s\n' "$issue_number" > "$project/src/remote-smoke.txt"
    git -C "$project" add src/remote-smoke.txt
    git -C "$project" commit -m "fix: remote smoke closes issue" >/dev/null
    git -C "$project" push -u origin "$branch" >/dev/null

    cat > "$tmp/pr-body.md" <<EOF
## Summary
<!-- dayu-harness:summary -->

- Verify remote Issue -> PR governance.

## Implementation notes
<!-- dayu-harness:implementation-notes -->

- Adds a disposable smoke marker file.

## Test plan
<!-- dayu-harness:test-plan -->

- [ ] \`gh pr checks\`

Closes #$issue_number
EOF
    pr_url="$(gh pr create --repo "$repo" --base main --head "$branch" --title "fix: remote smoke closes issue" --body-file "$tmp/pr-body.md")"
    pr_number="${pr_url##*/}"
    gh pr checks "$pr_number" --repo "$repo" --watch --fail-fast
    gh pr merge "$pr_number" --repo "$repo" --merge --delete-branch
    wait_issue_closed "$repo" "$issue_number"

    if [ "$JSON_MODE" = true ]; then
        emit_json "pass" "$PROFILE" "remote-smoke passed for $repo issue #$issue_number and PR #$pr_number."
    else
        echo "remote-smoke passed for $repo issue #$issue_number and PR #$pr_number."
    fi
}

run_remote_release() {
    require_cmd gh
    require_cmd git
    require_cmd jq
    gh auth status >/dev/null

    local owner repo tmp project vis docs_head_sha chore_head_sha head_sha release_pr_count
    owner="$(github_owner)"
    repo="${DAYU_REMOTE_REPO:-$owner/dayu-harness-remote-release-$(date +%s)}"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/dayu-remote-release.XXXXXX")"
    project="$tmp/project"
    trap "cleanup_remote_repo '$repo' '$tmp'" EXIT

    seed_project "$project"
    vis="$(visibility_args)"
    (cd "$project" && gh repo create "$repo" $vis --source=. --remote=origin >/dev/null)
    git -C "$project" add .
    git -C "$project" commit -m "chore: seed remote release smoke" >/dev/null
    git -C "$project" push -u origin main >/dev/null

    export DAYU_HARNESS_GITHUB_REPOSITORY="$repo"
    bash "$REPO_ROOT/scripts/scaffold.sh" "$project" --apply --enable release.automated --strategy merge --github-remote skip >/dev/null
    gh api -X PUT "repos/$repo/actions/permissions/workflow" -f default_workflow_permissions=write -F can_approve_pull_request_reviews=true >/dev/null

    mkdir -p "$project/src"
    printf 'remote release docs gate %s\n' "$(date +%s)" > "$project/src/remote-release.txt"
    git -C "$project" add .
    git -C "$project" commit -m "docs: remote release smoke must not publish" >/dev/null
    git -C "$project" push origin main >/dev/null
    docs_head_sha="$(git -C "$project" rev-parse HEAD)"

    wait_workflow_success "$repo" "release-please.yml" "$docs_head_sha" "push"
    release_pr_count="$(gh pr list --repo "$repo" --state open --json title --jq '[.[] | select(.title | test("^Release "))] | length')"
    if [ "$release_pr_count" -ne 0 ]; then
        echo "docs: commit unexpectedly created a Release PR." >&2
        exit 1
    fi

    printf 'remote release chore gate %s\n' "$(date +%s)" > "$project/src/remote-release.txt"
    git -C "$project" add src/remote-release.txt
    git -C "$project" commit -m "chore: remote release smoke must not publish" >/dev/null
    git -C "$project" push origin main >/dev/null
    chore_head_sha="$(git -C "$project" rev-parse HEAD)"

    wait_workflow_success "$repo" "release-please.yml" "$chore_head_sha" "push"
    release_pr_count="$(gh pr list --repo "$repo" --state open --json title --jq '[.[] | select(.title | test("^Release "))] | length')"
    if [ "$release_pr_count" -ne 0 ]; then
        echo "chore: commit unexpectedly created a Release PR." >&2
        exit 1
    fi

    printf 'remote release smoke %s\n' "$(date +%s)" > "$project/src/remote-release.txt"
    git -C "$project" add src/remote-release.txt
    git -C "$project" commit -m "feat: remote release smoke" >/dev/null
    git -C "$project" push origin main >/dev/null
    head_sha="$(git -C "$project" rev-parse HEAD)"

    wait_workflow_success "$repo" "release-please.yml" "$head_sha" "push"
    release_pr_count="$(gh pr list --repo "$repo" --state open --json title --jq '[.[] | select(.title | test("^Release "))] | length')"
    if [ "$release_pr_count" -lt 1 ]; then
        echo "release-please push workflow succeeded but no Release PR was found." >&2
        exit 1
    fi

    if [ "$JSON_MODE" = true ]; then
        emit_json "pass" "$PROFILE" "remote-release passed for $repo: docs/chore commits did not create Release PRs, and feat did."
    else
        echo "remote-release passed for $repo: docs/chore commits did not create Release PRs, and feat did."
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --profile)
            PROFILE="${2:-}"
            shift 2
            ;;
        --json)
            JSON_MODE=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$PROFILE" in
    local-fast|remote-smoke|remote-release) ;;
    *)
        echo "unsupported profile: $PROFILE" >&2
        exit 2
        ;;
esac

run_local_fast() {
    bash "$REPO_ROOT/scripts/check-i18n-drift.sh" --json >/dev/null
    bats "$REPO_ROOT/tests/unit/test-github-remote.bats"
    bats -f 'environment apply initializes new projects on main and creates baseline version files|environment apply preserves existing package version when creating VERSION|environment apply accepts formatted changelog version headings|environment apply skips unreleased changelog heading before version|environment apply skips linked unreleased changelog heading before version|scaffold renders existing default branch and project version into release assets|validate accepts formatted changelog version headings|validate skips unreleased changelog heading before version|validate skips linked unreleased changelog heading before version|validate en accepts formatted changelog version headings|validate en skips unreleased changelog heading before version|validate en skips linked unreleased changelog heading before version|validate reports release-please policy syntax errors and does not create bytecode|validate en reports release-please policy syntax errors and does not create bytecode' "$REPO_ROOT/tests/unit/test-architecture-contracts.bats"
    bats -f 'conversation replay: empty project expands legacy aliases into split capabilities|conversation replay: github.delivery deploys repository settings, PR lint, issue lint and rulesets|conversation replay: release automation deploys release workflow, policy, and repo settings' "$REPO_ROOT/tests/unit/test-skill-interaction-e2e.bats"
}

case "$PROFILE" in
    local-fast)
        run_local_fast
        if [ "$JSON_MODE" = true ]; then
            emit_json "pass" "$PROFILE" "local-fast profile passed."
        else
            echo "local-fast profile passed."
        fi
        ;;
    remote-smoke)
        if [ "${RUN_DAYU_REMOTE_SMOKE:-}" != "1" ]; then
            if [ "$JSON_MODE" = true ]; then
                emit_json "skipped" "$PROFILE" "remote-smoke is gated by RUN_DAYU_REMOTE_SMOKE=1."
            else
                echo "remote-smoke skipped; set RUN_DAYU_REMOTE_SMOKE=1."
            fi
            exit 0
        fi
        run_remote_smoke
        ;;
    remote-release)
        if [ "${RUN_DAYU_REMOTE_RELEASE:-}" != "1" ]; then
            if [ "$JSON_MODE" = true ]; then
                emit_json "skipped" "$PROFILE" "remote-release is gated by RUN_DAYU_REMOTE_RELEASE=1."
            else
                echo "remote-release skipped; set RUN_DAYU_REMOTE_RELEASE=1."
            fi
            exit 0
        fi
        run_remote_release
        ;;
esac
