#!/usr/bin/env bats
# 对话回放式 E2E：验证 AI 问答决策、capability 映射、部署和能力生效。

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TEST_ROOT="${BATS_TEST_DIRNAME}/.tmp/skill-e2e"
    mkdir -p "$TEST_ROOT"
    TEST_DIR="$(mktemp -d "$TEST_ROOT/run.XXXXXX")"

    WRAPPER_DIR="$TEST_DIR/wrapper"
    mkdir -p "$WRAPPER_DIR"
    cat > "$WRAPPER_DIR/node" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$WRAPPER_DIR/node"

    cat > "$WRAPPER_DIR/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "init" ]; then
  cat > package.json <<'JSON'
{"name":"dayu-harness-skill-test","version":"1.0.0","devDependencies":{}}
JSON
  exit 0
fi

if [ "${1:-}" = "install" ]; then
  cat > package.json <<'JSON'
{"name":"dayu-harness-skill-test","version":"1.0.0","devDependencies":{"@commitlint/cli":"0.0.0","@commitlint/config-conventional":"0.0.0","eslint":"0.0.0","@eslint/js":"0.0.0","prettier":"0.0.0","lint-staged":"0.0.0"}}
JSON
  exit 0
fi

exit 0
EOF
    chmod +x "$WRAPPER_DIR/npm"

    cat > "$WRAPPER_DIR/npx" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$WRAPPER_DIR/npx"

    cat > "$WRAPPER_DIR/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then
  exit 0
fi
if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ]; then
  printf '%s\n' "kinoward/dayu-harness-skill-test"
  exit 0
fi
if [ "${1:-}" = "api" ]; then
  if [ -n "${DAYU_HARNESS_GH_CALL_LOG:-}" ]; then
    printf '%s\n' "$*" >> "$DAYU_HARNESS_GH_CALL_LOG"
  fi
  if [ "${2:-}" = "-X" ] && [ "${3:-}" = "PATCH" ]; then
    printf '%s\n' '{"allow_merge_commit":true,"allow_squash_merge":false,"allow_rebase_merge":false,"allow_auto_merge":true,"delete_branch_on_merge":true}'
  fi
  exit 0
fi
exit 0
EOF
    chmod +x "$WRAPPER_DIR/gh"
    export DAYU_HARNESS_GH_CALL_LOG="$TEST_DIR/gh-calls.log"

    export PATH="$WRAPPER_DIR:$PATH"
}

teardown() {
    if [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

run_json() {
    run "$@"
    [ "$status" -eq 0 ]
}

write_file() {
    local file="$1"
    shift
    printf '%s\n' "$@" > "$file"
}

assert_no_path() {
    local target="$1"
    [ ! -e "$target" ] || {
        echo "unexpected path exists: $target"
        return 1
    }
}

assert_path() {
    local target="$1"
    [ -e "$target" ] || {
        echo "missing path: $target"
        return 1
    }
}

assert_empty_dir() {
    local target="$1"
    [ -d "$target" ] || {
        echo "missing directory: $target"
        return 1
    }
    [ -z "$(find "$target" -mindepth 1 -print -quit)" ] || {
        echo "directory is not empty: $target"
        find "$target" -mindepth 1 -maxdepth 2 -print | sort
        return 1
    }
}

json_from_output() {
    printf '%s\n' "$output" | awk 'BEGIN {emit=0} /^[[:space:]]*\{/ {emit=1} emit {print}'
}

	@test "conversation replay: empty project expands legacy aliases into split capabilities" {
    local project_dir="$TEST_DIR/empty-nongithub"
    cp -R "$REPO_ROOT/tests/fixtures/skill-empty-template" "$project_dir"
    rm -f "$project_dir/.gitkeep"
    assert_empty_dir "$project_dir"

    # Simulated user answers:
    # - Git: enable commit format constraints.
    # - GitHub: skip PR, branch protection, and release automation capabilities.
    # - Knowledge/project governance: enable all non-GitHub documentation capabilities.
    local enabled="git.commit,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project"

    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --dry-run --enable "$enabled"
    echo "$output" | jq -e '.status == "needs_initialization"'
    echo "$output" | jq -e '.environment.items | any(.action | startswith("git init"))'
    echo "$output" | jq -e '.environment.items | any(.action == "npm init -y")'
    echo "$output" | jq -e '.capability_count == 13'
    echo "$output" | jq -e '.capabilities | map(.id) | sort == ["ai.execution","ai.memory","core","git.commit-format","git.hooks","knowledge.adr","knowledge.archive","knowledge.research","knowledge.troubleshooting","project.context","project.gitignore","quality.node-tooling","quality.practices"]'

    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply --enable "$enabled" --strategy merge
    echo "$output" | jq -e '.status == "ok"'
    echo "$output" | jq -e '.applied_count == 36'
    echo "$output" | jq -e '.validation == "passed"'
    echo "$output" | jq -e '.post_apply_checks.status == "passed"'
    echo "$output" | jq -e '.post_apply_checks.checks | map(.name) == ["validate","audit","check-consistency","capability-smoke"]'
    echo "$output" | jq -e '.post_apply_checks.checks[] | select(.name=="capability-smoke") | .details.items | any(.capability=="project.gitignore" and .name=="gitignore-rules" and .status=="passed")'
    echo "$output" | jq -e '.post_apply_checks.checks[] | select(.name=="capability-smoke") | .details.items | any(.capability=="git.commit-format" and .name=="commitlint-cli" and .status=="passed")'
    echo "$output" | jq -e '.post_apply_checks.checks[] | select(.name=="capability-smoke") | .details.items | any(.capability=="git.commit-format" and .name=="commit-msg-hook" and .status=="passed")'
    echo "$output" | jq -e '.post_apply_checks.checks[] | select(.name=="capability-smoke") | .details.items | any(.capability=="quality.node-tooling" and .name=="tooling-cli" and .status=="passed")'
    echo "$output" | jq -e '.post_apply_checks.checks[] | select(.name=="capability-smoke") | .details.items | any(.capability=="quality.node-tooling" and .name=="pre-commit-hook" and .status=="passed")'
    echo "$output" | jq -e '.managed_paths | index("package-lock.json")'
    echo "$output" | jq -e '.managed_paths | index(".claude/") | not'
    echo "$output" | jq -e '.managed_paths | index("skills-lock.json") | not'
    echo "$output" | jq -e '.staging_policy.forbidden | index("git add .")'
    echo "$output" | jq -e '.staging_policy.excluded == [".claude/","skills-lock.json"]'

    assert_path "$project_dir/.husky/commit-msg"
    assert_path "$project_dir/.husky/pre-commit"
    assert_no_path "$project_dir/.husky/pre-push"
    assert_path "$project_dir/package.json"
    assert_path "$project_dir/README.md"
    assert_path "$project_dir/VERSION"
    assert_path "$project_dir/CHANGELOG.md"
    [ "$(cat "$project_dir/VERSION")" = "0.1.0" ]
    grep -Fq "## 0.1.0" "$project_dir/CHANGELOG.md"
    jq -e '.version == "0.1.0"' "$project_dir/package.json"
    assert_path "$project_dir/package-lock.json"
    jq -e '.version == "0.1.0" and .packages[""].version == "0.1.0"' "$project_dir/package-lock.json"
    assert_path "$project_dir/commitlint.config.cjs"
    assert_path "$project_dir/eslint.config.cjs"
    assert_path "$project_dir/docs/harness/sensors/scripts/dayu-format.mjs"
    assert_path "$project_dir/docs/references/research/AGENTS.md"
    assert_path "$project_dir/docs/product-specs/project-status.md"
    assert_no_path "$project_dir/.github/workflows/pr-lint.yml"
    assert_no_path "$project_dir/.github/rulesets"
	    assert_no_path "$project_dir/release-please-config.json"
	    assert_no_path "$project_dir/.release-please-manifest.json"

    run_json "$project_dir/docs/harness/sensors/scripts/validate.sh" --json "$project_dir"
    json_from_output | jq -e '.summary.failed == 0'

    run_json "$project_dir/docs/harness/sensors/scripts/audit.sh" --json "$project_dir"
    json_from_output | jq -e '.summary.failed == 0'
    json_from_output | jq -e '.summary.warnings == 0'

    run_json "$project_dir/docs/harness/sensors/scripts/check-consistency.sh" --json "$project_dir"
    json_from_output | jq -e '.summary.failed == 0'
    json_from_output | jq -e '.checks | all(.status == "pass")'

	    write_file "$project_dir/.test-msg-cjk" "feat: 提交治理文档"
	    run bash -c 'cd "$1" && .husky/commit-msg .test-msg-cjk' _ "$project_dir"
	    [ "$status" -eq 0 ]
	}

@test "conversation replay: dynamic gitignore merges language snapshots and keeps user rules" {
    local project_dir="$TEST_DIR/dynamic-gitignore"
    mkdir -p "$project_dir"
    write_file "$project_dir/package.json" '{"name":"dynamic-gitignore","version":"0.1.0"}'
    write_file "$project_dir/pyproject.toml" "[project]"
    write_file "$project_dir/go.mod" "module example.com/dynamic"
    write_file "$project_dir/Cargo.toml" "[package]"
    write_file "$project_dir/pom.xml" "<project></project>"
    write_file "$project_dir/app.csproj" "<Project></Project>"
    write_file "$project_dir/.gitignore" "custom-local-rule/"

    run_json bash "$REPO_ROOT/scripts/install-gitignore.sh" "$project_dir" --check
    echo "$output" | jq -e '.status == "conflict"'
    echo "$output" | jq -e '.detected_templates | sort == ["Go","Java","Node","Python","Rust","VisualStudio"]'

    run_json bash "$REPO_ROOT/scripts/install-gitignore.sh" "$project_dir" --apply merge
    echo "$output" | jq -e '.status == "ok" and .action == "merge" and .added_count > 0'

    grep -Fq "custom-local-rule/" "$project_dir/.gitignore"
    grep -Fq "node_modules/" "$project_dir/.gitignore"
    grep -Fq "__pycache__/" "$project_dir/.gitignore"
    grep -Fq "*.test" "$project_dir/.gitignore"
    grep -Fq "target/" "$project_dir/.gitignore"
    grep -Fq ".gradle/" "$project_dir/.gitignore"
    grep -Fq ".vs/" "$project_dir/.gitignore"
    grep -Fq ".claude/" "$project_dir/.gitignore"
    grep -Fq "skills-lock.json" "$project_dir/.gitignore"
}

	@test "conversation replay: empty project gitignore defaults to Node template" {
    local project_dir="$TEST_DIR/empty-gitignore-default"
    mkdir -p "$project_dir"

    run_json bash "$REPO_ROOT/scripts/install-gitignore.sh" "$project_dir" --check
    echo "$output" | jq -e '.status == "clean"'
    echo "$output" | jq -e '.detected_templates == ["Node"]'

    run_json bash "$REPO_ROOT/scripts/install-gitignore.sh" "$project_dir" --apply merge
    echo "$output" | jq -e '.status == "ok" and .action == "merge"'
    echo "$output" | jq -e '.detected_templates == ["Node"]'
    grep -Fq "node_modules/" "$project_dir/.gitignore"
    grep -Fq ".claude/" "$project_dir/.gitignore"
    grep -Fq "skills-lock.json" "$project_dir/.gitignore"
	}

	@test "conversation replay: manual npm init default version stays at 0.1.0 in dry-run" {
	    local project_dir="$TEST_DIR/manual-npm-init-default"
	    mkdir -p "$project_dir"
	    git -C "$project_dir" init -b main >/dev/null
	    write_file "$project_dir/package.json" '{"name":"manual-npm-init-default","version":"1.0.0","devDependencies":{}}'

	    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --dry-run --enable release.automated
	    echo "$output" | jq -e '.project_baseline.version == "0.1.0"'
	    echo "$output" | jq -e '.environment.items | any(.name=="package.version" and (.description_nl | contains("npm init 默认")))'
	}

	@test "conversation replay: github remote options are parsed as options not target paths" {
	    local project_dir="$TEST_DIR/github-remote-options"
	    mkdir -p "$project_dir"

	    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --dry-run --enable github.delivery --github-repository kinoward/dayu-harness-skill-test --visibility public
	    echo "$output" | jq -e '.github_remote.repository == "kinoward/dayu-harness-skill-test"'
	}

	@test "conversation replay: issue and PR workflows require remote sync for E2E" {
	    local project_dir="$TEST_DIR/github-issue-pr-remote-sync"
	    mkdir -p "$project_dir"

	    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --dry-run --enable github.issue,github.pr --github-repository kinoward/dayu-harness-skill-test
	    echo "$output" | jq -e '.github_remote.repository == "kinoward/dayu-harness-skill-test"'

	    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply --enable github.issue,github.pr --strategy merge --github-remote skip
	    echo "$output" | jq -e '.status == "ok"'
	    echo "$output" | jq -e '.github_e2e.status == "skipped"'
	    echo "$output" | jq -e '.github_e2e.description_nl | contains("--github-remote apply")'

	    local forced_dir="$TEST_DIR/github-issue-pr-forced-target"
	    mkdir -p "$forced_dir"
	    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$forced_dir" --apply --enable github.issue,github.pr --strategy merge --github-remote skip --github-e2e target
	    echo "$output" | jq -e '.status == "ok"'
	    echo "$output" | jq -e '.github_e2e.status == "skipped"'
	    echo "$output" | jq -e '.github_e2e.description_nl | contains("--github-remote apply or --github-remote verify")'
	}

	@test "conversation replay: GitHub target E2E is issue-first and creates lint-ready PR body" {
	    local issue_line pr_line
	    issue_line="$(grep -n 'gh issue create' "$REPO_ROOT/scripts/scaffold.sh" | sed -n '1s/:.*//p')"
	    pr_line="$(grep -n 'gh pr create' "$REPO_ROOT/scripts/scaffold.sh" | sed -n '1s/:.*//p')"

	    [ -n "$issue_line" ]
	    [ -n "$pr_line" ]
	    [ "$issue_line" -lt "$pr_line" ]
	    grep -Fq "render_dayu_pr_body" "$REPO_ROOT/scripts/scaffold.sh"
	    grep -Fq "Dayu Harness GitHub E2E verification" "$REPO_ROOT/scripts/scaffold.sh"
	    if grep -Fq 'title "test: verify Dayu Harness GitHub E2E"' "$REPO_ROOT/scripts/scaffold.sh"; then
	        echo "target E2E PR title must use natural language, not Conventional Commits"
	        exit 1
	    fi
	    if grep -Fq "gh issue close" "$REPO_ROOT/scripts/scaffold.sh"; then
	        echo "target E2E must not manually close issues"
	        exit 1
	    fi
	}

	@test "conversation replay: release settlement waits for init PR and validates origin default branch" {
	    grep -Fq 'github_remote_initialization_pr_pending "$apply_json"' "$REPO_ROOT/scripts/scaffold.sh"
	    grep -Fq 'Release post-remote revalidation waits until the initialization PR is merged' "$REPO_ROOT/scripts/scaffold.sh"
	    grep -Fq 'git -C "$TARGET" worktree add --detach "$tmp_worktree" "$remote_ref"' "$REPO_ROOT/scripts/scaffold.sh"
	    grep -Fq 'run_post_apply_checks_at_root "$RELEASE_VALIDATION_ROOT" "$@"' "$REPO_ROOT/scripts/scaffold.sh"
	    grep -Fq 'if [ "$local_head" = "$remote_head" ]; then' "$REPO_ROOT/scripts/scaffold.sh"
	    grep -Fq 'git -C "$TARGET" merge-base --is-ancestor HEAD "$remote_ref"' "$REPO_ROOT/scripts/scaffold.sh"
	    if grep -Fq 'refresh_status="skipped"' "$REPO_ROOT/scripts/scaffold.sh"; then
	        echo "release settlement must not pass by skipping remote default-branch refresh"
	        exit 1
	    fi
	}

	@test "conversation replay: initialization PR body follows Dayu PR template" {
	    grep -Fq "render_dayu_pr_body" "$REPO_ROOT/scripts/github-remote.sh"
	    grep -Fq "Initialize Dayu Harness governance" "$REPO_ROOT/scripts/github-remote.sh"
	    grep -Fq "Final PR: yes" "$REPO_ROOT/scripts/github-remote.sh"
	    if grep -Fq 'title "chore: initialize Dayu Harness"' "$REPO_ROOT/scripts/github-remote.sh"; then
	        echo "initialization PR title must use natural language, not Conventional Commits"
	        exit 1
	    fi
	}

	@test "conversation replay: no GitHub optional capabilities in default deployment" {
	    local project_dir="$TEST_DIR/default-no-github-optional"
	    cp -R "$REPO_ROOT/tests/fixtures/skill-empty-template" "$project_dir"
	    rm -f "$project_dir/.gitkeep"

	    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply --strategy merge
	    echo "$output" | jq -e '.status == "ok"'

	    assert_no_path "$project_dir/.github/workflows/pr-lint.yml"
	    assert_no_path "$project_dir/.github/workflows/issue-lint.yml"
	    assert_no_path "$project_dir/.github/rulesets/protect-main.json"
	    assert_no_path "$project_dir/.github/rulesets/protect-tags.json"
	    assert_no_path "$project_dir/release-please-config.json"
	    assert_no_path "$project_dir/.github/workflows/release-please.yml"
	    assert_no_path "$project_dir/.release-please-manifest.json"

	    run_json "$project_dir/docs/harness/sensors/scripts/validate.sh" --json "$project_dir"
	    json_from_output | jq -e '.summary.failed == 0'
	}

	@test "conversation replay: github.delivery deploys repository settings, PR lint, issue lint and rulesets" {
	    local project_dir="$TEST_DIR/enable-github-delivery"
	    cp -R "$REPO_ROOT/tests/fixtures/skill-empty-template" "$project_dir"
	    rm -f "$project_dir/.gitkeep"

	    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply --enable github.delivery --strategy merge
	    echo "$output" | jq -e '.status == "ok"'
	    echo "$output" | jq -e '.github_e2e.status == "skipped"'
	    echo "$output" | jq -e '.github_e2e.description_nl | contains("--github-remote apply")'
	    echo "$output" | jq -e '.capabilities[] | select(.id=="github.repository-settings") | .items | any(.kind=="remote_settings" and .status=="pending")'
	    ! grep -Fq 'api -X PATCH repos/kinoward/dayu-harness-skill-test -F allow_merge_commit=true -F allow_squash_merge=false -F allow_rebase_merge=false -F allow_auto_merge=true -F delete_branch_on_merge=true' "$DAYU_HARNESS_GH_CALL_LOG"

	    assert_path "$project_dir/.github/repository/pull-request-settings.json"
	    assert_path "$project_dir/.github/workflows/pr-lint.yml"
	    assert_path "$project_dir/.github/workflows/issue-lint.yml"
	    assert_path "$project_dir/.github/ISSUE_TEMPLATE/dayu-harness-issue.md"
	    assert_path "$project_dir/.github/pull_request_template.md"
	    assert_path "$project_dir/.github/rulesets/protect-main.json"
	    assert_no_path "$project_dir/.github/rulesets/protect-tags.json"
	    assert_path "$project_dir/docs/harness/guides/issue-guidelines.md"
	    assert_no_path "$project_dir/.github/workflows/release-please.yml"
	    assert_no_path "$project_dir/.github/release-please-policy.json"

	    run_json "$project_dir/docs/harness/sensors/scripts/validate.sh" --json "$project_dir"
	    json_from_output | jq -e '.summary.failed == 0'
	    run_json "$project_dir/docs/harness/sensors/scripts/check-consistency.sh" --json "$project_dir"
	    json_from_output | jq -e '.summary.failed == 0'
	}

	@test "conversation replay: release automation deploys release workflow, policy, and repo settings" {
	    local project_dir="$TEST_DIR/enable-release-automated"
	    cp -R "$REPO_ROOT/tests/fixtures/skill-empty-template" "$project_dir"
	    rm -f "$project_dir/.gitkeep"

	    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply --enable release.automated --strategy merge
	    echo "$output" | jq -e '.status == "ok"'
	    echo "$output" | jq -e '.capabilities[] | select(.id=="github.repository-settings") | .items | any(.kind=="remote_settings" and .status=="pending")'
	    ! grep -Fq 'api -X PATCH repos/kinoward/dayu-harness-skill-test -F allow_merge_commit=true -F allow_squash_merge=false -F allow_rebase_merge=false -F allow_auto_merge=true -F delete_branch_on_merge=true' "$DAYU_HARNESS_GH_CALL_LOG"

	    assert_path "$project_dir/.github/workflows/release-please.yml"
	    assert_path "$project_dir/.github/release-please-policy.json"
	    assert_path "$project_dir/.github/scripts/release_please_policy.py"
	    assert_path "$project_dir/release-please-config.json"
	    assert_path "$project_dir/.release-please-manifest.json"
	    assert_path "$project_dir/.github/repository/pull-request-settings.json"
	    [ "$(cat "$project_dir/VERSION")" = "0.1.0" ]
	    jq -e '."." == "0.1.0"' "$project_dir/.release-please-manifest.json"
	    jq -e '.version == "0.1.0"' "$project_dir/package.json"

	    assert_no_path "$project_dir/.github/workflows/issue-lint.yml"

	    run_json "$project_dir/docs/harness/sensors/scripts/validate.sh" --json "$project_dir"
	    json_from_output | jq -e '.summary.failed == 0'
	    run_json "$project_dir/docs/harness/sensors/scripts/audit.sh" --json "$project_dir"
	    json_from_output | jq -e '.summary.failed == 0'
	    run bash -c 'find "$1" -type d -name "__pycache__"' _ "$project_dir"
	    [ -z "$output" ]
	    run bash -c 'find "$1" -type f -name "*.pyc"' _ "$project_dir"
	    [ -z "$output" ]
	}

	@test "legacy language capability aliases remain rejected in e2e path" {
	    local project_dir="$TEST_DIR/legacy-language-capability-e2e"
	    mkdir -p "$project_dir"

	    run bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --dry-run --enable github.language
	    [ "$status" -eq 2 ]
	    [[ "$output" == *"unknown capability 'github.language'"* ]]
	}

	@test "conversation replay: zh-CN and English default deployments differ only by locale" {
    local zh_project_dir="$TEST_DIR/i18n-zh"
    local en_project_dir="$TEST_DIR/i18n-en"
    mkdir -p "$zh_project_dir" "$en_project_dir"

    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$zh_project_dir" --apply --strategy merge
    echo "$output" | jq -e '.status == "ok"'
    echo "$output" | jq -e '.validation == "passed"'

    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$en_project_dir" --apply --locale en --strategy merge
    echo "$output" | jq -e '.status == "ok"'
    echo "$output" | jq -e '.validation == "passed"'

    assert_path "$zh_project_dir/.husky/commit-msg"
    assert_path "$en_project_dir/.husky/commit-msg"
    assert_path "$zh_project_dir/commitlint.config.cjs"
    assert_path "$en_project_dir/commitlint.config.cjs"
    assert_no_path "$zh_project_dir/.github"
    assert_no_path "$en_project_dir/.github"

    run bash "$REPO_ROOT/tests/helpers/compare-i18n-deployments.sh" --json "$zh_project_dir" "$en_project_dir"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "pass"'
    echo "$output" | jq -e '.checks | any(.name == "No GitHub constraints" and .status == "pass")'
    echo "$output" | jq -e '.checks | any(.name == "Git constraints" and .status == "pass")'
    echo "$output" | jq -e '.checks | any(.name == "Artifact content parity" and .status == "pass")'
}

@test "manual Claude CLI bilingual deployment smoke test is opt-in" {
    local smoke_script="$REPO_ROOT/tests/smoke/claude-i18n-deploy-smoke.sh"
    [ -x "$smoke_script" ]

    run bash "$smoke_script" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"RUN_CLAUDE_I18N_SMOKE=1"* ]]
    [[ "$output" == *"/dayu-harness"* ]]

    if [ "${RUN_CLAUDE_I18N_SMOKE:-}" != "1" ]; then
        skip "set RUN_CLAUDE_I18N_SMOKE=1 to run the real Claude Code CLI smoke test"
    fi

    run bash "$smoke_script" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "pass"'
    echo "$output" | jq -e '.deployments.zh and .deployments.en'
}

@test "profiled Dayu Harness smoke test entrypoint exposes local and gated remote profiles" {
    local profile_script="$REPO_ROOT/tests/smoke/dayu-harness-profile.sh"
    [ -x "$profile_script" ]

    run bash "$profile_script" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"local-fast"* ]]
    [[ "$output" == *"remote-smoke"* ]]
    [[ "$output" == *"remote-release"* ]]
    grep -Fq "Depends on: #" "$profile_script"
    grep -Fq "createdAt" "$profile_script"

    run env RUN_DAYU_REMOTE_SMOKE=0 bash "$profile_script" --profile remote-smoke --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "skipped" and .profile == "remote-smoke"'

    run env RUN_DAYU_REMOTE_RELEASE=0 bash "$profile_script" --profile remote-release --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "skipped" and .profile == "remote-release"'
}

@test "conversation replay: messy project merges selected capabilities and fixes progressive docs indexes" {
    local project_dir="$TEST_DIR/messy-selected"
    cp -R "$REPO_ROOT/tests/fixtures/skill-messy-template" "$project_dir"

    run bash "$REPO_ROOT/templates/docs/harness/sensors/scripts/audit.sh" --json "$project_dir"
    [ "$status" -eq 1 ]
    json_from_output | jq -e '.summary.failed >= 1'
    json_from_output | jq -e '.summary.warnings >= 1'

    run_json env DAYU_HARNESS_CAPABILITY=git.commit-format bash "$REPO_ROOT/scripts/install-husky.sh" "$project_dir" --check
    echo "$output" | jq -e '.status == "conflict"'
    echo "$output" | jq -e '.items | any(.file == ".husky/commit-msg" and .recommendation == "merge")'

    # Simulated user answers:
    # - Enable Git, GitHub PR, branch protection, quality tooling and knowledge/project docs.
    # - Skip github.release-please.
    # - Merge existing Husky hooks and preserve existing config files.
    local enabled="git.commit,github.pr,github.branch-release,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project"

    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --dry-run --enable "$enabled"
    echo "$output" | jq -e '.status == "needs_initialization"'
    echo "$output" | jq -e '.environment.status == "needs_initialization"'
    echo "$output" | jq -e '.files_existing == 4'
    echo "$output" | jq -e '.capabilities | any(.status == "conflict")'
    # apply output is environment-centric in this branch and may omit capability_count.
    echo "$output" | jq -e '.capabilities | map(.id) | sort | index("github.release-please") | not'

    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply --enable "$enabled" --strategy merge
    echo "$output" | jq -e '.status == "partial"'
    echo "$output" | jq -e '.validation == "passed"'
    echo "$output" | jq -e '.files_existing == 4'

    # Simulated follow-up user approvals for semantic document fusion:
    # - Route CLAUDE.md to root AGENTS.md.
    # - Replace the stale release-notes link with the deployed release versioning guide.
    # - Index preserved loose docs so progressive disclosure can discover them.
    write_file "$project_dir/CLAUDE.md" "@AGENTS.md"
    perl -0pi -e 's#^\s*-\s*.*\(docs/operations/release-notes\.md\).*$#- [docs/harness/guides/release-versioning.md](docs/harness/guides/release-versioning.md)#mg' "$project_dir/AGENTS.md"
    perl -0pi -e 's#(- \[archive/AGENTS.md\]\(archive/AGENTS.md\) - 默认：历史归档\n)#$1- [notes/decision-log.md](notes/decision-log.md) - 迁移前保留的松散决策记录\n- [practices/commit-guidelines.md](practices/commit-guidelines.md) - 迁移前保留的旧提交规范\n#' "$project_dir/docs/AGENTS.md"
    ! grep -q '故意断链' "$project_dir/AGENTS.md"
    ! grep -q '需替换' "$project_dir/AGENTS.md"
    grep -Fq '[docs/harness/guides/release-versioning.md](docs/harness/guides/release-versioning.md)' "$project_dir/AGENTS.md"

    assert_path "$project_dir/.github/workflows/pr-lint.yml"
    assert_no_path "$project_dir/docs/harness/guides/git-language-policy.md"
    assert_no_path "$project_dir/.github/workflows/repo-language-pr-lint.yml"
    assert_no_path "$project_dir/.github/workflows/repo-language-issue-lint.yml"
    assert_path "$project_dir/.github/rulesets/protect-main.json"
    assert_path "$project_dir/.github/rulesets/protect-tags.json"
    assert_no_path "$project_dir/.github/workflows/release-please.yml"
    assert_no_path "$project_dir/release-please-config.json"
    assert_no_path "$project_dir/.release-please-manifest.json"

    run_json "$project_dir/docs/harness/sensors/scripts/validate.sh" --json "$project_dir"
    json_from_output | jq -e '.summary.failed == 0'

    run_json "$project_dir/docs/harness/sensors/scripts/audit.sh" --json "$project_dir"
    json_from_output | jq -e '.summary.failed == 0'
    json_from_output | jq -e '.summary.warnings == 0'

    run_json "$project_dir/docs/harness/sensors/scripts/check-consistency.sh" --json "$project_dir"
    json_from_output | jq -e '.summary.failed == 0'
    json_from_output | jq -e '.checks | all(.status == "pass")'

    write_file "$project_dir/.test-msg-cjk" "feat: 提交治理文档"
    run bash -c 'cd "$1" && .husky/commit-msg .test-msg-cjk' _ "$project_dir"
    [ "$status" -eq 0 ]

    run bash -c 'cd "$1" && printf "%s\n" "refs/heads/main 0000000000000000000000000000000000000000 refs/heads/main 1111111111111111111111111111111111111111" | .husky/pre-push' _ "$project_dir"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "deleting main is not allowed" ]]

    run bash -c 'cd "$1" && printf "%s\n" "refs/tags/v1.2.3 0000000000000000000000000000000000000000 refs/tags/v1.2.3 1111111111111111111111111111111111111111" | .husky/pre-push' _ "$project_dir"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "deleting release tag v1.2.3 is not allowed" ]]
}
