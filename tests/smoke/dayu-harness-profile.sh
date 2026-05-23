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

Remote profiles delete their disposable repositories after the run. They require
the GitHub CLI token scope delete_repo unless DAYU_KEEP_REMOTE_REPO=1 is set.
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

require_delete_repo_scope() {
    if [ "${DAYU_KEEP_REMOTE_REPO:-}" = "1" ]; then
        return 0
    fi

    local scopes
    scopes="$(gh api -i user 2>/dev/null | awk -F': ' 'tolower($1)=="x-oauth-scopes"{print $2; exit}' | tr -d '\r' || true)"
    if printf '%s' "$scopes" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -Fxq "delete_repo"; then
        return 0
    fi

    echo "remote profiles create disposable repositories and require GitHub token scope delete_repo for cleanup; run gh auth refresh -h github.com -s delete_repo, or set DAYU_KEEP_REMOTE_REPO=1 to opt into keeping the disposable repository." >&2
    exit 2
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
{"name":"dayu-harness-remote-smoke","version":"0.1.0"}
JSON
    printf '# dayu-harness remote smoke\n' > "$dir/README.md"
    printf '0.1.0\n' > "$dir/VERSION"
    printf '# Changelog\n\n## 0.1.0\n\n- Initial smoke baseline.\n' > "$dir/CHANGELOG.md"
}

cleanup_remote_repo() {
    local repo="$1"
    local dir="$2"
    if [ "${DAYU_KEEP_REMOTE_REPO:-}" != "1" ]; then
        gh repo delete "$repo" --yes >/dev/null
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

wait_workflow_conclusion() {
    local repo="$1"
    local workflow="$2"
    local head_sha="$3"
    local event_filter="${4:-push}"
    local created_after="${5:-}"
    local expected_conclusion="${6:-success}"
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
                [ "$conclusion" = "$expected_conclusion" ] && [ "$event" = "$event_filter" ] && return 0
                echo "$workflow run $run_id completed with conclusion ${conclusion:-unknown}, expected ${expected_conclusion}, and event ${event:-unknown}" >&2
                return 1
            fi
        fi
        sleep 15
    done
    echo "$workflow did not complete for $head_sha and event $event_filter with expected conclusion $expected_conclusion" >&2
    return 1
}

wait_workflow_success() {
    wait_workflow_conclusion "$1" "$2" "$3" "${4:-push}" "${5:-}" "success"
}

wait_workflow_failure() {
    wait_workflow_conclusion "$1" "$2" "$3" "${4:-push}" "${5:-}" "failure"
}

wait_remote_workflow_file() {
    local repo="$1"
    local workflow="$2"
    local deadline=$((SECONDS + ${DAYU_REMOTE_TIMEOUT_SECONDS:-900}))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if gh api "repos/$repo/contents/.github/workflows/$workflow?ref=main" >/dev/null 2>&1; then
            return 0
        fi
        sleep 10
    done
    echo "$workflow did not appear on remote main for $repo" >&2
    return 1
}

wait_release_version_advance() {
    local repo="$1"
    local project="$2"
    local previous_version="$3"
    local deadline=$((SECONDS + ${DAYU_REMOTE_TIMEOUT_SECONDS:-900}))
    local version manifest_version
    RELEASE_VERSION_RESULT=""

    while [ "$SECONDS" -lt "$deadline" ]; do
        git -C "$project" fetch origin main >/dev/null 2>&1 || true
        version="$(git -C "$project" show origin/main:VERSION 2>/dev/null | tr -d '\r\n' || true)"
        manifest_version="$(git -C "$project" show origin/main:.release-please-manifest.json 2>/dev/null | jq -r '."." // empty' 2>/dev/null || true)"
        if [ -n "$version" ] && [ "$version" != "$previous_version" ] && [ "$version" = "$manifest_version" ]; then
            RELEASE_VERSION_RESULT="$version"
            return 0
        fi
        sleep 15
    done

    echo "release version did not advance from ${previous_version:-unknown} for $repo" >&2
    return 1
}

wait_release_artifact() {
    local repo="$1"
    local version="$2"
    local tag="v$version"
    local deadline=$((SECONDS + ${DAYU_REMOTE_TIMEOUT_SECONDS:-900}))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if gh api "repos/$repo/git/ref/tags/$tag" >/dev/null 2>&1 && gh api "repos/$repo/releases/tags/$tag" >/dev/null 2>&1; then
            return 0
        fi
        sleep 15
    done
    echo "release artifact $tag was not published for $repo" >&2
    return 1
}

assert_no_open_release_prs_or_branches() {
    local repo="$1"
    local project="$2"
    local release_pr_count release_branch_count
    release_pr_count="$(gh pr list --repo "$repo" --state open --json title --jq '[.[] | select(.title | test("^Release "))] | length')"
    if [ "$release_pr_count" -ne 0 ]; then
        echo "open Release PRs remain after remote-release cycle." >&2
        return 1
    fi
    release_branch_count="$(git -C "$project" ls-remote --heads origin 'release-please--*' | wc -l | tr -d ' ')"
    if [ "${release_branch_count:-0}" -ne 0 ]; then
        echo "release-please branches remain after remote-release cycle." >&2
        return 1
    fi
}

assert_remote_branch_absent() {
    local repo="$1"
    local project="$2"
    local branch="$3"
    local deadline=$((SECONDS + ${DAYU_REMOTE_TIMEOUT_SECONDS:-900}))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if ! git -C "$project" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
            return 0
        fi
        sleep 10
    done
    echo "remote branch $branch still exists for $repo" >&2
    return 1
}

run_remote_smoke() {
    require_cmd gh
    require_cmd git
    require_cmd jq
    require_cmd node
    gh auth status >/dev/null
    require_delete_repo_scope

    local owner repo tmp project vis formatter bootstrap_issue_body bootstrap_issue_url bootstrap_issue_number bad_issue_after bad_issue_url bad_issue_number issue_url issue_number issue_body issue_lint_after bad_branch bad_pr_after bad_pr_url bad_pr_number bad_head_sha branch pr_url pr_number main_sha head_sha scaffold_json
    owner="$(github_owner)"
    repo="${DAYU_REMOTE_REPO:-$owner/dayu-harness-remote-smoke-$(date +%s)}"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/dayu-remote-smoke.XXXXXX")"
    project="$tmp/project"
    trap "cleanup_remote_repo '$repo' '$tmp'" EXIT
    export npm_config_cache="$tmp/npm-cache"

    seed_project "$project"
    scaffold_json="$(bash "$REPO_ROOT/scripts/scaffold.sh" "$project" --apply --enable github.issue,github.pr --strategy merge --github-remote skip)"
    if ! printf '%s' "$scaffold_json" | jq -e '.status == "ok"' >/dev/null; then
        printf '%s\n' "$scaffold_json" >&2
        exit 1
    fi
    git -C "$project" add .
    git -C "$project" commit -m "chore: deploy dayu harness remote smoke" >/dev/null
    vis="$(visibility_args)"
    (cd "$project" && gh repo create "$repo" $vis --source=. --remote=origin >/dev/null)
    git -C "$project" push -u origin main >/dev/null
    main_sha="$(git -C "$project" rev-parse main)"
    formatter="$project/docs/harness/sensors/scripts/dayu-format.mjs"
    wait_remote_workflow_file "$repo" "issue-lint.yml"
    wait_remote_workflow_file "$repo" "pr-lint.yml"

    bootstrap_issue_body="$(node "$formatter" issue-body --summary "Bootstrap dependency for remote smoke." --background "Disposable remote-smoke repository.")"
    issue_lint_after="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    bootstrap_issue_url="$(gh issue create --repo "$repo" --title "Remote smoke dependency" --body "$bootstrap_issue_body")"
    bootstrap_issue_number="${bootstrap_issue_url##*/}"
    wait_workflow_success "$repo" "issue-lint.yml" "$main_sha" "issues" "$issue_lint_after"

    bad_issue_after="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    bad_issue_url="$(gh issue create --repo "$repo" --title "Remote smoke invalid dependency issue" --body $'## Summary\n\n- This issue must be rejected by issue-lint.\n\nDepends on #1\n')"
    bad_issue_number="${bad_issue_url##*/}"
    wait_workflow_failure "$repo" "issue-lint.yml" "$main_sha" "issues" "$bad_issue_after"
    gh issue close "$bad_issue_number" --repo "$repo" --comment "remote-smoke negative issue-lint case complete." >/dev/null

    issue_lint_after="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    issue_body="$(node "$formatter" issue-body --summary "Verify Issue to PR governance." --background "Disposable remote-smoke repository." --depends-on "$bootstrap_issue_number")"
    issue_url="$(gh issue create --repo "$repo" --title "Remote smoke issue" --body "$issue_body")"
    issue_number="${issue_url##*/}"
    wait_workflow_success "$repo" "issue-lint.yml" "$main_sha" "issues" "$issue_lint_after"

    bad_branch="test/remote-smoke-reject-$issue_number"
    git -C "$project" switch -c "$bad_branch" main >/dev/null
    mkdir -p "$project/src"
    printf 'remote smoke rejected pr %s\n' "$issue_number" > "$project/src/remote-smoke-reject.txt"
    git -C "$project" add src/remote-smoke-reject.txt
    git -C "$project" commit -m "test: remote smoke rejected pr" >/dev/null
    git -C "$project" push -u origin "$bad_branch" >/dev/null
    bad_head_sha="$(git -C "$project" rev-parse HEAD)"

    cat > "$tmp/bad-pr-body.md" <<EOF
## Summary

- Missing required Dayu Harness PR sections and issue trailer.
EOF
    bad_pr_after="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    bad_pr_url="$(gh pr create --repo "$repo" --base main --head "$bad_branch" --title "test: invalid remote smoke PR" --body-file "$tmp/bad-pr-body.md")"
    bad_pr_number="${bad_pr_url##*/}"
    wait_workflow_failure "$repo" "pr-lint.yml" "$bad_head_sha" "pull_request" "$bad_pr_after"
    gh pr close "$bad_pr_number" --repo "$repo" --comment "remote-smoke negative pr-lint case complete." --delete-branch >/dev/null
    assert_remote_branch_absent "$repo" "$project" "$bad_branch"
    git -C "$project" switch main >/dev/null
    git -C "$project" branch -D "$bad_branch" >/dev/null

    branch="fix/remote-smoke-$issue_number"
    git -C "$project" switch -c "$branch" >/dev/null
    printf 'remote smoke %s\n' "$issue_number" > "$project/src/remote-smoke.txt"
    git -C "$project" add src/remote-smoke.txt
    git -C "$project" commit -m "fix: remote smoke closes issue" >/dev/null
    git -C "$project" push -u origin "$branch" >/dev/null
    head_sha="$(git -C "$project" rev-parse HEAD)"

    node "$formatter" pr-body \
        --summary "Verify remote Issue to PR governance." \
        --implementation "Adds a disposable smoke marker file." \
        --test-command "gh pr checks $branch --repo $repo" \
        --issue "$issue_number" \
        --final yes > "$tmp/pr-body.md"
    pr_url="$(gh pr create --repo "$repo" --base main --head "$branch" --title "Remote smoke closes issue" --body-file "$tmp/pr-body.md")"
    pr_number="${pr_url##*/}"
    gh pr checks "$pr_number" --repo "$repo" --watch --fail-fast
    wait_workflow_success "$repo" "pr-lint.yml" "$head_sha" "pull_request"
    gh pr merge "$pr_number" --repo "$repo" --merge --delete-branch
    wait_issue_closed "$repo" "$issue_number"
    assert_remote_branch_absent "$repo" "$project" "$branch"

    if [ "$JSON_MODE" = true ]; then
        emit_json "pass" "$PROFILE" "remote-smoke passed for $repo: invalid Issue #$bad_issue_number and PR #$bad_pr_number were rejected, valid Issue #$issue_number and PR #$pr_number merged and closed cleanly."
    else
        echo "remote-smoke passed for $repo: invalid Issue #$bad_issue_number and PR #$bad_pr_number were rejected, valid Issue #$issue_number and PR #$pr_number merged and closed cleanly."
    fi
}

run_remote_release() {
    require_cmd gh
    require_cmd git
    require_cmd jq
    gh auth status >/dev/null
    require_delete_repo_scope

    local owner repo tmp project vis docs_head_sha chore_head_sha head_sha release_pr_count previous_version first_version second_version scaffold_json
    owner="$(github_owner)"
    repo="${DAYU_REMOTE_REPO:-$owner/dayu-harness-remote-release-$(date +%s)}"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/dayu-remote-release.XXXXXX")"
    project="$tmp/project"
    trap "cleanup_remote_repo '$repo' '$tmp'" EXIT
    export npm_config_cache="$tmp/npm-cache"

    seed_project "$project"
    vis="$(visibility_args)"
    (cd "$project" && gh repo create "$repo" $vis --source=. --remote=origin >/dev/null)
    git -C "$project" add .
    git -C "$project" commit -m "chore: seed remote release smoke" >/dev/null
    git -C "$project" push -u origin main >/dev/null

    export DAYU_HARNESS_GITHUB_REPOSITORY="$repo"
    scaffold_json="$(bash "$REPO_ROOT/scripts/scaffold.sh" "$project" --apply --enable release.automated --strategy merge --github-remote skip)"
    if ! printf '%s' "$scaffold_json" | jq -e '.status == "ok"' >/dev/null; then
        printf '%s\n' "$scaffold_json" >&2
        exit 1
    fi
    git -C "$project" add .
    git -C "$project" commit -m "chore: deploy dayu harness release automation" >/dev/null
    git -C "$project" push origin main >/dev/null
    wait_remote_workflow_file "$repo" "release-please.yml"
    gh api -X PATCH "repos/$repo" \
        -F allow_merge_commit=true \
        -F allow_squash_merge=false \
        -F allow_rebase_merge=false \
        -F allow_auto_merge=true \
        -F delete_branch_on_merge=true >/dev/null
    gh api -X PUT "repos/$repo/actions/permissions/workflow" -f default_workflow_permissions=write -F can_approve_pull_request_reviews=true >/dev/null

    mkdir -p "$project/src"
    printf 'remote release docs gate %s\n' "$(date +%s)" > "$project/src/remote-release.txt"
    git -C "$project" add src/remote-release.txt
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

    previous_version="$(tr -d '\r\n' < "$project/VERSION")"
    printf 'remote release smoke %s\n' "$(date +%s)" > "$project/src/remote-release.txt"
    git -C "$project" add src/remote-release.txt
    git -C "$project" commit -m "feat: remote release smoke" >/dev/null
    git -C "$project" push origin main >/dev/null
    head_sha="$(git -C "$project" rev-parse HEAD)"

    wait_workflow_success "$repo" "release-please.yml" "$head_sha" "push"
    wait_release_version_advance "$repo" "$project" "$previous_version"
    first_version="$RELEASE_VERSION_RESULT"
    wait_release_artifact "$repo" "$first_version"
    assert_no_open_release_prs_or_branches "$repo" "$project"
    git -C "$project" pull --ff-only origin main >/dev/null

    printf 'remote release smoke second %s\n' "$(date +%s)" > "$project/src/remote-release.txt"
    git -C "$project" add src/remote-release.txt
    git -C "$project" commit -m "fix: remote release smoke second version" >/dev/null
    git -C "$project" push origin main >/dev/null
    head_sha="$(git -C "$project" rev-parse HEAD)"

    wait_workflow_success "$repo" "release-please.yml" "$head_sha" "push"
    wait_release_version_advance "$repo" "$project" "$first_version"
    second_version="$RELEASE_VERSION_RESULT"
    wait_release_artifact "$repo" "$second_version"
    assert_no_open_release_prs_or_branches "$repo" "$project"

    if [ "$JSON_MODE" = true ]; then
        emit_json "pass" "$PROFILE" "remote-release passed for $repo: docs/chore commits did not create Release PRs, then release-please published v$first_version and v$second_version with clean release branches."
    else
        echo "remote-release passed for $repo: docs/chore commits did not create Release PRs, then release-please published v$first_version and v$second_version with clean release branches."
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
    bats "$REPO_ROOT/tests/unit/test-github-helper-scripts.bats"
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
