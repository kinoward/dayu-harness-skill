#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TEST_ROOT="${BATS_TEST_DIRNAME}/.tmp/github-remote"
    mkdir -p "$TEST_ROOT"
    TEST_DIR="$(mktemp -d "$TEST_ROOT/run.XXXXXX")"
    SCRIPT="$REPO_ROOT/scripts/github-remote.sh"
    export SCRIPT

    WRAPPER_DIR="$TEST_DIR/wrapper"
    mkdir -p "$WRAPPER_DIR"
    REAL_GIT="$(command -v git)"
    export REAL_GIT

cat > "$WRAPPER_DIR/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "-C" ]; then
  if [ "${3:-}" = "push" ]; then
    if [ -n "${DAYU_HARNESS_GIT_PUSH_LOG:-}" ]; then
      printf '%s\n' "${*:3}" >> "$DAYU_HARNESS_GIT_PUSH_LOG"
    fi
    exit 0
  fi
elif [ "${1:-}" = "push" ]; then
  if [ -n "${DAYU_HARNESS_GIT_PUSH_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$DAYU_HARNESS_GIT_PUSH_LOG"
  fi
  exit 0
fi

exec "$REAL_GIT" "$@"
EOF
    chmod +x "$WRAPPER_DIR/git"

    export PATH="$WRAPPER_DIR:$PATH"
}

teardown() {
    rm -rf "$TEST_DIR"
}

write_fake_gh() {
    local scenario="$1"
    cat > "$WRAPPER_DIR/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCENARIO="${DAYU_HARNESS_GH_SCENARIO:-default}"
REPO="${DAYU_HARNESS_GH_REPO:-kinoward/dayu-harness-skill-test}"
DEFAULT_BRANCH="${DAYU_HARNESS_GH_DEFAULT_BRANCH:-main}"

if [ -n "${DAYU_HARNESS_GH_CALL_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$DAYU_HARNESS_GH_CALL_LOG"
fi

if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then
    if [ "${DAYU_HARNESS_GH_AUTH_STATUS:-ok}" = "ok" ]; then
        exit 0
    fi
    exit 1
fi

if [ "${1:-}" = "repo" ]; then
    if [ "${2:-}" = "create" ]; then
        exit 0
    fi
    if [ "${2:-}" = "view" ]; then
        printf '%s\n' "$REPO"
        exit 0
    fi
    exit 0
fi

if [ "${1:-}" = "api" ]; then
    if [ "${2:-}" = "-X" ]; then
        exit 0
    fi
    PATH_ARG="${2:-}"
    case "$PATH_ARG" in
      "repos/$REPO")
        if [ "$SCENARIO" = "repo_missing" ]; then
          exit 1
        fi
        if [ "$SCENARIO" = "verify_missing" ]; then
          cat <<JSON
{"default_branch":"$DEFAULT_BRANCH","visibility":"public","allow_auto_merge":true,"delete_branch_on_merge":true}
JSON
        else
          cat <<JSON
{"default_branch":"$DEFAULT_BRANCH","visibility":"public","allow_auto_merge":true,"delete_branch_on_merge":true}
JSON
        fi
        exit 0
        ;;
      "repos/$REPO/branches")
        if [ "$SCENARIO" = "verify_missing" ]; then
          cat <<JSON
[{"name":"main"},{"name":"release"},{"name":"trunk"}]
JSON
        else
          cat <<JSON
[{"name":"main"},{"name":"release"},{"name":"trunk"}]
JSON
        fi
        exit 0
        ;;
      "repos/$REPO/rulesets")
        if [ "$SCENARIO" = "apply_actions" ]; then
          cat <<JSON
{"total_count":1,"rulesets":[{"id":42,"name":"protect-main","conditions":{"ref_name":{"include":["refs/heads/$DEFAULT_BRANCH"],"exclude":[]}}}]}
JSON
          exit 0
        fi
        if [ "$SCENARIO" = "verify_missing" ]; then
          cat <<JSON
{"total_count":1,"rulesets":[{"name":"protect-main","conditions":{"ref_name":{"include":["refs/heads/$DEFAULT_BRANCH"],"exclude":[]}}}]}
JSON
        else
          cat <<JSON
{"total_count":2,"rulesets":[{"name":"protect-main","conditions":{"ref_name":{"include":["refs/heads/$DEFAULT_BRANCH"],"exclude":[]}}},{"name":"protect-tags"}]}
JSON
        fi
        exit 0
        ;;
      "repos/$REPO/actions/secrets")
        if [ "$SCENARIO" = "verify_missing" ]; then
          cat <<JSON
{"total_count":0,"secrets":[]}
JSON
        else
          cat <<JSON
{"total_count":1,"secrets":[{"name":"RELEASE_TOKEN"}]}
JSON
        fi
        exit 0
        ;;
      "repos/$REPO/actions/variables")
        if [ "$SCENARIO" = "verify_missing" ]; then
          cat <<JSON
{"total_count":1,"variables":[{"name":"RELEASE_PLEASE_ALLOWED_ACTORS"}]}
JSON
        else
          cat <<JSON
{"total_count":1,"variables":[{"name":"RELEASE_PLEASE_ALLOWED_ACTORS"}]}
JSON
        fi
        exit 0
        ;;
    esac
fi

exit 0
EOF
    chmod +x "$WRAPPER_DIR/gh"
}

setup_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git init -q "$dir"
    git -C "$dir" config user.name "ci"
    git -C "$dir" config user.email "ci@example.com"
    git -C "$dir" checkout -b main >/dev/null 2>&1 || git -C "$dir" checkout master >/dev/null 2>&1
    echo "init" > "$dir/README.md"
    git -C "$dir" add README.md
    git -C "$dir" commit -q -m "init"
}

@test "github-remote --check reports not logged in when gh auth is missing" {
    local repo_dir="$TEST_DIR/unauthed"
    setup_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "https://github.com/acme/unauthed.git"

    export DAYU_HARNESS_GH_SCENARIO="repo_missing"
    export DAYU_HARNESS_GH_REPO="acme/unauthed"
    export DAYU_HARNESS_GH_AUTH_STATUS="unauthorized"
    unset DAYU_HARNESS_GITHUB_REPOSITORY
    write_fake_gh repo_missing

    run bash "$SCRIPT" "$repo_dir" --check
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "needs_user_action"'
    echo "$output" | jq -e '.repository == "acme/unauthed"'
    echo "$output" | jq -e '.items | map(select(.kind=="auth")) | length >= 1'
}

@test "github-remote --apply creates private repository when no origin is set" {
    local repo_dir="$TEST_DIR/apply-create"
    local push_log="$TEST_DIR/push.log"
    local call_log="$TEST_DIR/gh.log"
    mkdir -p "$TEST_DIR"
    setup_repo "$repo_dir"

    export DAYU_HARNESS_GH_SCENARIO="repo_missing"
    export DAYU_HARNESS_GH_REPO="acme/private-repo"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GH_CALL_LOG="$call_log"
    export DAYU_HARNESS_GIT_PUSH_LOG="$push_log"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/private-repo"
    export DAYU_HARNESS_GITHUB_VISIBILITY="private"
    write_fake_gh repo_missing

    run bash "$SCRIPT" "$repo_dir" --apply
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "ok"'
    echo "$output" | jq -e '.repository == "acme/private-repo"'
    echo "$output" | jq -e '.items | any(.action=="create" and .status=="ok")'
    grep -Fq "repo create acme/private-repo --private --source=. --remote=origin" "$call_log"
    grep -Fq "push -u origin main" "$push_log"
    origin_url="$(git -C "$repo_dir" remote get-url origin)"
    [ "$origin_url" = "https://github.com/acme/private-repo.git" ]
}

@test "github-remote --apply defaults new repository visibility to private" {
    local repo_dir="$TEST_DIR/apply-default-private"
    local push_log="$TEST_DIR/push-default-private.log"
    local call_log="$TEST_DIR/gh-default-private.log"
    setup_repo "$repo_dir"

    export DAYU_HARNESS_GH_SCENARIO="repo_missing"
    export DAYU_HARNESS_GH_REPO="acme/default-private"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GH_CALL_LOG="$call_log"
    export DAYU_HARNESS_GIT_PUSH_LOG="$push_log"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/default-private"
    unset DAYU_HARNESS_GITHUB_VISIBILITY
    write_fake_gh repo_missing

    run bash "$SCRIPT" "$repo_dir" --apply
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "ok"'
    grep -Fq "repo create acme/default-private --private --source=. --remote=origin" "$call_log"
    grep -Fq "push -u origin main" "$push_log"
}

@test "github-remote --apply binds existing repository when no origin is set" {
    local repo_dir="$TEST_DIR/apply-bind"
    local push_log="$TEST_DIR/push-bind.log"
    local call_log="$TEST_DIR/gh-bind.log"
    setup_repo "$repo_dir"

    export DAYU_HARNESS_GH_SCENARIO="default"
    export DAYU_HARNESS_GH_REPO="acme/existing-remote"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GH_CALL_LOG="$call_log"
    export DAYU_HARNESS_GIT_PUSH_LOG="$push_log"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/existing-remote"
    write_fake_gh default

    run bash "$SCRIPT" "$repo_dir" --apply
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "ok"'
    echo "$output" | jq -e '.items | any(.kind=="remote" and .action=="bind" and .status=="ok")'
    if grep -Fq "repo create" "$call_log"; then
      echo "repo create should not be called when remote repository exists"
      exit 1
    fi
    [ "$(git -C "$repo_dir" remote get-url origin)" = "https://github.com/acme/existing-remote.git" ]
    grep -Fq "push -u origin main" "$push_log"
}

@test "github-remote --apply blocks when origin and requested repository differ" {
    local repo_dir="$TEST_DIR/apply-mismatch"
    local call_log="$TEST_DIR/gh-mismatch.log"
    local push_log="$TEST_DIR/push-mismatch.log"
    setup_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "https://github.com/acme/origin-target.git"

    export DAYU_HARNESS_GH_SCENARIO="default"
    export DAYU_HARNESS_GH_REPO="acme/env-target"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GH_CALL_LOG="$call_log"
    export DAYU_HARNESS_GIT_PUSH_LOG="$push_log"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/env-target"
    write_fake_gh default

    run bash "$SCRIPT" "$repo_dir" --apply
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "needs_user_action"'
    echo "$output" | jq -e '.items | any(.kind=="repository" and .name=="origin" and .status=="needs_user_action")'
    if [ -s "$push_log" ]; then
      echo "push should not be reached when repository mismatch exists"
      exit 1
    fi
    if grep -Eq "api -X (PATCH|POST|PUT)" "$call_log"; then
      echo "write API should not be reached when repository mismatch exists"
      exit 1
    fi
}

@test "github-remote --apply keeps existing origin when one is already configured" {
    local repo_dir="$TEST_DIR/apply-existing-origin"
    local push_log="$TEST_DIR/push-existing.log"
    local call_log="$TEST_DIR/gh-existing.log"
    setup_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "https://github.com/acme/existing-origin.git"

    export DAYU_HARNESS_GH_SCENARIO="default"
    export DAYU_HARNESS_GH_REPO="acme/existing-origin"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GH_CALL_LOG="$call_log"
    export DAYU_HARNESS_GIT_PUSH_LOG="$push_log"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/existing-origin"
    export DAYU_HARNESS_GITHUB_VISIBILITY="public"
    write_fake_gh default

    run bash "$SCRIPT" "$repo_dir" --apply
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "ok"'
    echo "$output" | jq -e '.items | any(.action=="create" and (.description_nl | contains("检测到已存在 origin")) )'
    if grep -Fq "repo create" "$call_log"; then
      echo "repo create should not be called when origin exists"
      exit 1
    fi
    grep -Fq "push -u origin main" "$push_log"
}

@test "github-remote --apply patches repository settings and upserts rulesets" {
    local repo_dir="$TEST_DIR/apply-actions"
    local push_log="$TEST_DIR/push-actions.log"
    local call_log="$TEST_DIR/gh-actions.log"
    setup_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "https://github.com/acme/actions-target.git"
    mkdir -p "$repo_dir/.github/repository" "$repo_dir/.github/rulesets"
    cat > "$repo_dir/.github/repository/pull-request-settings.json" <<'JSON'
{"allow_auto_merge":true,"delete_branch_on_merge":true}
JSON
    cat > "$repo_dir/.github/rulesets/protect-main.json" <<'JSON'
{"name":"protect-main","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},"rules":[]}
JSON
    cat > "$repo_dir/.github/rulesets/protect-tags.json" <<'JSON'
{"name":"protect-tags","target":"tag","enforcement":"active","conditions":{"ref_name":{"include":["refs/tags/v*"],"exclude":[]}},"rules":[]}
JSON

    export DAYU_HARNESS_GH_SCENARIO="apply_actions"
    export DAYU_HARNESS_GH_REPO="acme/actions-target"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GH_CALL_LOG="$call_log"
    export DAYU_HARNESS_GIT_PUSH_LOG="$push_log"
    unset DAYU_HARNESS_GITHUB_REPOSITORY
    export DAYU_HARNESS_REMOTE_ACTIONS_JSON='[{"kind":"repository_settings"},{"kind":"ruleset","name":"protect-main"},{"kind":"ruleset","name":"protect-tags"}]'
    write_fake_gh apply_actions

    run bash "$SCRIPT" "$repo_dir" --apply
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "ok"'
    echo "$output" | jq -e '.repository == "acme/actions-target"'
    echo "$output" | jq -e '.items | any(.kind=="repository_settings" and .action=="patch" and .status=="ok")'
    echo "$output" | jq -e '.items | any(.kind=="ruleset" and .name=="protect-main" and .action=="update" and .status=="ok")'
    echo "$output" | jq -e '.items | any(.kind=="ruleset" and .name=="protect-tags" and .action=="create" and .status=="ok")'
    grep -Fq "api -X PATCH repos/acme/actions-target -F allow_auto_merge=true -F delete_branch_on_merge=true" "$call_log"
    grep -Fq "api -X PUT repos/acme/actions-target/rulesets/42 --input" "$call_log"
    grep -Fq "api -X POST repos/acme/actions-target/rulesets --input" "$call_log"
}

@test "github-remote --apply does not fallback to local remote assets without remote_actions" {
    local repo_dir="$TEST_DIR/apply-no-actions"
    local push_log="$TEST_DIR/push-no-actions.log"
    local call_log="$TEST_DIR/gh-no-actions.log"
    setup_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "https://github.com/acme/no-actions.git"
    mkdir -p "$repo_dir/.github/repository" "$repo_dir/.github/rulesets"
    cat > "$repo_dir/.github/repository/pull-request-settings.json" <<'JSON'
{"allow_auto_merge":true,"delete_branch_on_merge":true}
JSON
    cat > "$repo_dir/.github/rulesets/protect-main.json" <<'JSON'
{"name":"protect-main","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},"rules":[]}
JSON
    cat > "$repo_dir/.github/rulesets/protect-tags.json" <<'JSON'
{"name":"protect-tags","target":"tag","enforcement":"active","conditions":{"ref_name":{"include":["refs/tags/v*"],"exclude":[]}},"rules":[]}
JSON

    export DAYU_HARNESS_GH_SCENARIO="apply_actions"
    export DAYU_HARNESS_GH_REPO="acme/no-actions"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GH_CALL_LOG="$call_log"
    export DAYU_HARNESS_GIT_PUSH_LOG="$push_log"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/no-actions"
    unset DAYU_HARNESS_REMOTE_ACTIONS_JSON
    write_fake_gh apply_actions

    run bash "$SCRIPT" "$repo_dir" --apply
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "ok"'
    grep -Fq "push -u origin main" "$push_log"
    if grep -Eq "api -X (PATCH|POST|PUT) repos/acme/no-actions" "$call_log"; then
      echo "remote assets should not be applied without explicit remote_actions"
      exit 1
    fi
}

@test "github-remote --apply ignores invalid remote_actions instead of scanning local assets" {
    local repo_dir="$TEST_DIR/apply-invalid-actions"
    local push_log="$TEST_DIR/push-invalid-actions.log"
    local call_log="$TEST_DIR/gh-invalid-actions.log"
    setup_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "https://github.com/acme/invalid-actions.git"
    mkdir -p "$repo_dir/.github/repository" "$repo_dir/.github/rulesets"
    cat > "$repo_dir/.github/repository/pull-request-settings.json" <<'JSON'
{"allow_auto_merge":true,"delete_branch_on_merge":true}
JSON
    cat > "$repo_dir/.github/rulesets/protect-main.json" <<'JSON'
{"name":"protect-main","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},"rules":[]}
JSON

    export DAYU_HARNESS_GH_SCENARIO="apply_actions"
    export DAYU_HARNESS_GH_REPO="acme/invalid-actions"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GH_CALL_LOG="$call_log"
    export DAYU_HARNESS_GIT_PUSH_LOG="$push_log"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/invalid-actions"
    export DAYU_HARNESS_REMOTE_ACTIONS_JSON='{invalid json'
    write_fake_gh apply_actions

    run bash "$SCRIPT" "$repo_dir" --apply
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "ok"'
    grep -Fq "push -u origin main" "$push_log"
    if grep -Eq "api -X (PATCH|POST|PUT) repos/acme/invalid-actions" "$call_log"; then
      echo "invalid remote_actions should not fall back to local remote asset writes"
      exit 1
    fi
}

@test "github-remote --apply treats explicit empty remote_actions as no remote writes" {
    local repo_dir="$TEST_DIR/apply-empty-actions"
    local push_log="$TEST_DIR/push-empty-actions.log"
    local call_log="$TEST_DIR/gh-empty-actions.log"
    setup_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "https://github.com/acme/empty-actions.git"
    mkdir -p "$repo_dir/.github/repository" "$repo_dir/.github/rulesets"
    cat > "$repo_dir/.github/repository/pull-request-settings.json" <<'JSON'
{"allow_auto_merge":true,"delete_branch_on_merge":true}
JSON
    cat > "$repo_dir/.github/rulesets/protect-main.json" <<'JSON'
{"name":"protect-main","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},"rules":[]}
JSON

    export DAYU_HARNESS_GH_SCENARIO="apply_actions"
    export DAYU_HARNESS_GH_REPO="acme/empty-actions"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GH_CALL_LOG="$call_log"
    export DAYU_HARNESS_GIT_PUSH_LOG="$push_log"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/empty-actions"
    export DAYU_HARNESS_REMOTE_ACTIONS_JSON='[]'
    write_fake_gh apply_actions

    run bash "$SCRIPT" "$repo_dir" --apply
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "ok"'
    grep -Fq "push -u origin main" "$push_log"
    if grep -Eq "api -X (PATCH|POST|PUT) repos/acme/empty-actions" "$call_log"; then
      echo "empty remote_actions should not apply local remote asset writes"
      exit 1
    fi
}

@test "github-remote --check falls back to main in detached HEAD" {
    local repo_dir="$TEST_DIR/check-detached-head"
    setup_repo "$repo_dir"
    git -C "$repo_dir" checkout --detach HEAD >/dev/null

    export DAYU_HARNESS_GH_SCENARIO="default"
    export DAYU_HARNESS_GH_REPO="acme/detached-check"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    unset DAYU_HARNESS_GITHUB_REPOSITORY
    write_fake_gh default

    run bash "$SCRIPT" "$repo_dir" --check
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "needs_initialization"'
    echo "$output" | jq -e '.default_branch == "main"'
}

@test "github-remote --apply falls back to main in detached HEAD" {
    local repo_dir="$TEST_DIR/apply-detached-head"
    local push_log="$TEST_DIR/push-detached-head.log"
    local call_log="$TEST_DIR/gh-detached-head.log"
    setup_repo "$repo_dir"
    git -C "$repo_dir" checkout --detach HEAD >/dev/null

    export DAYU_HARNESS_GH_SCENARIO="repo_missing"
    export DAYU_HARNESS_GH_REPO="acme/detached-apply"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GH_CALL_LOG="$call_log"
    export DAYU_HARNESS_GIT_PUSH_LOG="$push_log"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/detached-apply"
    unset DAYU_HARNESS_GITHUB_VISIBILITY
    write_fake_gh repo_missing

    run bash "$SCRIPT" "$repo_dir" --apply
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "ok"'
    echo "$output" | jq -e '.default_branch == "main"'
    grep -Fq "repo create acme/detached-apply --private --source=. --remote=origin" "$call_log"
    grep -Fq "push -u origin main" "$push_log"
}

@test "github-remote --apply uses requested default branch and syncs remote default branch" {
    local repo_dir="$TEST_DIR/apply-default-branch"
    local push_log="$TEST_DIR/push-default-branch.log"
    local call_log="$TEST_DIR/gh-default-branch.log"
    setup_repo "$repo_dir"
    git -C "$repo_dir" checkout -b trunk >/dev/null
    git -C "$repo_dir" remote add origin "https://github.com/acme/default-branch-target.git"

    export DAYU_HARNESS_GH_SCENARIO="default"
    export DAYU_HARNESS_GH_REPO="acme/default-branch-target"
    export DAYU_HARNESS_GH_DEFAULT_BRANCH="main"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GH_CALL_LOG="$call_log"
    export DAYU_HARNESS_GIT_PUSH_LOG="$push_log"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/default-branch-target"
    export DAYU_HARNESS_DEFAULT_BRANCH="trunk"
    write_fake_gh default

    run bash "$SCRIPT" "$repo_dir" --apply
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "ok"'
    grep -Fq "push -u origin trunk" "$push_log"
    grep -Fq "api -X PATCH repos/acme/default-branch-target -F default_branch=trunk" "$call_log"
}

@test "github-remote --verify scopes checks to deployed repository settings" {
    local repo_dir="$TEST_DIR/verify-repo-settings-only"
    setup_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "https://github.com/acme/verify-settings.git"
    mkdir -p "$repo_dir/.github/repository"
    cat > "$repo_dir/.github/repository/pull-request-settings.json" <<'JSON'
{"allow_auto_merge":true,"delete_branch_on_merge":true}
JSON

    export DAYU_HARNESS_GH_SCENARIO="verify_missing"
    export DAYU_HARNESS_GH_REPO="acme/verify-settings"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/verify-settings"
    unset DAYU_HARNESS_REMOTE_ACTIONS_JSON
    write_fake_gh verify_missing

    run bash "$SCRIPT" "$repo_dir" --verify
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "ok"'
    echo "$output" | jq -e '.items | any(.kind=="repository_settings" and .status=="ok")'
    echo "$output" | jq -e '.items | all(.kind!="secrets" or .required == [])'
}

@test "github-remote --apply only applies selected remote actions" {
    local repo_dir="$TEST_DIR/apply-selected-actions"
    local push_log="$TEST_DIR/push-selected-actions.log"
    local call_log="$TEST_DIR/gh-selected-actions.log"
    setup_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "https://github.com/acme/selected-actions.git"
    mkdir -p "$repo_dir/.github/repository" "$repo_dir/.github/rulesets"
    cat > "$repo_dir/.github/repository/pull-request-settings.json" <<'JSON'
{"allow_auto_merge":true,"delete_branch_on_merge":true}
JSON
    cat > "$repo_dir/.github/rulesets/protect-main.json" <<'JSON'
{"name":"protect-main","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},"rules":[]}
JSON
    cat > "$repo_dir/.github/rulesets/protect-tags.json" <<'JSON'
{"name":"protect-tags","target":"tag","enforcement":"active","conditions":{"ref_name":{"include":["refs/tags/v*"],"exclude":[]}},"rules":[]}
JSON

    export DAYU_HARNESS_GH_SCENARIO="apply_actions"
    export DAYU_HARNESS_GH_REPO="acme/selected-actions"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GH_CALL_LOG="$call_log"
    export DAYU_HARNESS_GIT_PUSH_LOG="$push_log"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/selected-actions"
    export DAYU_HARNESS_REMOTE_ACTIONS_JSON='[{"kind":"repository_settings"}]'
    write_fake_gh apply_actions

    run bash "$SCRIPT" "$repo_dir" --apply
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "ok"'
    grep -Fq "api -X PATCH repos/acme/selected-actions -F allow_auto_merge=true -F delete_branch_on_merge=true" "$call_log"
    if grep -Eq "api -X (POST|PUT) repos/acme/selected-actions/rulesets" "$call_log"; then
      echo "rulesets should not be applied when remote_actions only requests repository settings"
      exit 1
    fi
}

@test "github-remote --verify reports requested default branch mismatch" {
    local repo_dir="$TEST_DIR/verify-default-branch-mismatch"
    setup_repo "$repo_dir"
    git -C "$repo_dir" checkout -b trunk >/dev/null
    git -C "$repo_dir" remote add origin "https://github.com/acme/verify-default-branch.git"

    export DAYU_HARNESS_GH_SCENARIO="default"
    export DAYU_HARNESS_GH_REPO="acme/verify-default-branch"
    export DAYU_HARNESS_GH_DEFAULT_BRANCH="main"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/verify-default-branch"
    export DAYU_HARNESS_DEFAULT_BRANCH="trunk"
    export DAYU_HARNESS_REMOTE_ACTIONS_JSON='[{"kind":"ruleset","name":"protect-main"}]'
    write_fake_gh default

    run bash "$SCRIPT" "$repo_dir" --verify
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "needs_user_action"'
    echo "$output" | jq -e '.items | any(.kind=="default_branch" and .status=="missing" and (.missing | index("trunk") != null))'
    echo "$output" | jq -e '.items | any(.kind=="rulesets" and .status=="missing" and (.missing | index("protect-main:refs/heads/trunk") != null))'
}

@test "github-remote --verify reports missing ruleset and secret" {
    local repo_dir="$TEST_DIR/verify-missing"
    local call_log="$TEST_DIR/verify.log"
    setup_repo "$repo_dir"
    git -C "$repo_dir" remote add origin "https://github.com/acme/verify-target.git"
    mkdir -p "$repo_dir/.github/rulesets" "$repo_dir/.github/workflows"
    cat > "$repo_dir/.github/rulesets/protect-main.json" <<'JSON'
{"name":"protect-main","target":"branch","conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},"rules":[]}
JSON
    cat > "$repo_dir/.github/rulesets/protect-tags.json" <<'JSON'
{"name":"protect-tags","target":"tag","conditions":{"ref_name":{"include":["refs/tags/v*"],"exclude":[]}},"rules":[]}
JSON
    touch "$repo_dir/.github/workflows/release-please.yml"

    export DAYU_HARNESS_GH_SCENARIO="verify_missing"
    export DAYU_HARNESS_GH_REPO="acme/verify-target"
    export DAYU_HARNESS_GH_AUTH_STATUS="ok"
    export DAYU_HARNESS_GH_CALL_LOG="$call_log"
    export DAYU_HARNESS_GITHUB_REPOSITORY="acme/verify-target"
    write_fake_gh verify_missing

    run bash "$SCRIPT" "$repo_dir" --verify
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "needs_user_action"'
    echo "$output" | jq -e '.repository == "acme/verify-target"'
    echo "$output" | jq -e '.items | any(.kind=="rulesets" and .status=="missing" and (.missing | index("protect-tags") != null))'
    echo "$output" | jq -e '.items | any(.kind=="secrets" and .status=="missing" and (.missing | index("RELEASE_TOKEN") != null))'
    echo "$output" | jq -e '.items | any(.kind=="variables" and .status=="ok")'
}
