#!/usr/bin/env bats
# 对话回放式 E2E：验证 AI 问答决策、capability 映射、部署和能力生效。

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TEST_ROOT="${BATS_TEST_DIRNAME}/.tmp/skill-e2e"
    mkdir -p "$TEST_ROOT"
    TEST_DIR="$(mktemp -d "$TEST_ROOT/run.XXXXXX")"
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

@test "conversation replay: empty project enables git constraints and non-GitHub capabilities" {
    local project_dir="$TEST_DIR/empty-nongithub"
    cp -R "$REPO_ROOT/tests/fixtures/skill-empty-template" "$project_dir"
    rm -f "$project_dir/.gitkeep"
    assert_empty_dir "$project_dir"

    # Simulated user answers:
    # - Git: enable commit constraints and language policy.
    # - GitHub: skip all GitHub capabilities.
    # - Knowledge/project governance: enable all non-GitHub documentation capabilities.
    local enabled="git.language,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project"

    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --dry-run --enable "$enabled"
    echo "$output" | jq -e '.status == "clean"'
    echo "$output" | jq -e '.capability_count == 10'
    echo "$output" | jq -e '.capabilities | map(.id) | sort == ["ai.collaboration","archive.project","core","git.commit","git.language","knowledge.adr","knowledge.research","knowledge.troubleshooting","project.docs","quality.tooling"]'

    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply --enable "$enabled" --strategy merge
    echo "$output" | jq -e '.status == "ok"'
    echo "$output" | jq -e '.applied_count == 35'
    echo "$output" | jq -e '.validation == "passed"'

    assert_path "$project_dir/.husky/commit-msg"
    assert_path "$project_dir/.husky/pre-commit"
    assert_path "$project_dir/.husky/pre-push"
    assert_path "$project_dir/commitlint.config.cjs"
    assert_path "$project_dir/eslint.config.js"
    assert_path "$project_dir/docs/references/research/AGENTS.md"
    assert_no_path "$project_dir/.github"
    assert_no_path "$project_dir/release-please-config.json"
    assert_no_path "$project_dir/.release-please-manifest.json"

    run_json "$project_dir/docs/harness/sensors/scripts/validate.sh" --json "$project_dir"
    json_from_output | jq -e '.summary.failed == 0'
    json_from_output | jq -e '.summary.passed == 7'

    run_json "$project_dir/docs/harness/sensors/scripts/audit.sh" --json "$project_dir"
    json_from_output | jq -e '.summary.failed == 0'
    json_from_output | jq -e '.summary.warnings == 0'

    run_json "$project_dir/docs/harness/sensors/scripts/check-consistency.sh" --json "$project_dir"
    json_from_output | jq -e '.summary.failed == 0'
    json_from_output | jq -e '.checks | all(.status == "pass")'

    write_file "$project_dir/.test-msg-cjk" "feat: 添加治理文档"
    run bash -c 'cd "$1" && .husky/commit-msg .test-msg-cjk' _ "$project_dir"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "commit message contains CJK characters" ]]

    write_file "$project_dir/.test-msg-issue" "feat: add governance docs" "" "Closes #123"
    run bash -c 'cd "$1" && .husky/commit-msg .test-msg-issue' _ "$project_dir"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Issue reference trailers" ]]

    run bash -c 'cd "$1" && printf "%s\n" "refs/heads/main 0000000000000000000000000000000000000000 refs/heads/main 1111111111111111111111111111111111111111" | .husky/pre-push' _ "$project_dir"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "禁止删除 main 分支" ]]
}

@test "conversation replay: messy project merges selected capabilities and fixes progressive docs indexes" {
    local project_dir="$TEST_DIR/messy-selected"
    cp -R "$REPO_ROOT/tests/fixtures/skill-messy-template" "$project_dir"

    run bash "$REPO_ROOT/templates/docs/harness/sensors/scripts/audit.sh" --json "$project_dir"
    [ "$status" -eq 1 ]
    json_from_output | jq -e '.summary.failed >= 1'
    json_from_output | jq -e '.summary.warnings >= 1'

    run_json bash "$REPO_ROOT/scripts/install-husky.sh" "$project_dir" --check
    echo "$output" | jq -e '.status == "conflict"'
    echo "$output" | jq -e '.items | any(.file == ".husky/commit-msg" and .recommendation == "merge")'

    # Simulated user answers:
    # - Enable Git, GitHub PR, branch protection, quality tooling and knowledge/project docs.
    # - Skip github.release-please.
    # - Merge existing Husky hooks and preserve existing config files.
    local enabled="git.language,github.pr,github.branch-release,quality.tooling,ai.collaboration,knowledge.adr,knowledge.troubleshooting,knowledge.research,project.docs,archive.project"

    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --dry-run --enable "$enabled"
    echo "$output" | jq -e '.status == "conflict"'
    echo "$output" | jq -e '.capability_count == 12'
    echo "$output" | jq -e '.capabilities | map(.id) | sort | index("github.release-please") | not'

    run_json bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply --enable "$enabled" --strategy merge
    echo "$output" | jq -e '.status == "partial"'
    echo "$output" | jq -e '.validation == "passed"'
    echo "$output" | jq -e '.files_existing == 5'

    # Simulated follow-up user approvals for semantic document fusion:
    # - Route CLAUDE.md to root AGENTS.md.
    # - Replace the stale release-notes link with the deployed branch/release guide.
    # - Index preserved loose docs so progressive disclosure can discover them.
    write_file "$project_dir/CLAUDE.md" "@AGENTS.md"
    perl -0pi -e 's#- 发布流程：\[docs/operations/release-notes.md\]\(docs/operations/release-notes.md\)#- 发布流程已迁移到：[docs/harness/guides/branch-and-release.md](docs/harness/guides/branch-and-release.md)#' "$project_dir/AGENTS.md"
    perl -0pi -e 's#(- 可选：`archive.project` \[archive/AGENTS.md\]\(archive/AGENTS.md\) - 历史归档\n)#$1- [notes/decision-log.md](notes/decision-log.md) - 迁移前保留的松散决策记录\n- [practices/commit-guidelines.md](practices/commit-guidelines.md) - 迁移前保留的旧提交规范\n#' "$project_dir/docs/AGENTS.md"

    assert_path "$project_dir/.github/workflows/pr-lint.yml"
    assert_path "$project_dir/.github/workflows/issue-lint.yml"
    assert_path "$project_dir/.github/rulesets/protect-main.json"
    assert_no_path "$project_dir/.github/workflows/release-please.yml"
    assert_no_path "$project_dir/release-please-config.json"
    assert_no_path "$project_dir/.release-please-manifest.json"

    run_json "$project_dir/docs/harness/sensors/scripts/validate.sh" --json "$project_dir"
    json_from_output | jq -e '.summary.failed == 0'
    json_from_output | jq -e '.summary.passed == 10'

    run_json "$project_dir/docs/harness/sensors/scripts/audit.sh" --json "$project_dir"
    json_from_output | jq -e '.summary.failed == 0'
    json_from_output | jq -e '.summary.warnings == 0'

    run_json "$project_dir/docs/harness/sensors/scripts/check-consistency.sh" --json "$project_dir"
    json_from_output | jq -e '.summary.failed == 0'
    json_from_output | jq -e '.checks | all(.status == "pass")'

    write_file "$project_dir/.test-msg-cjk" "feat: 添加治理文档"
    run bash -c 'cd "$1" && .husky/commit-msg .test-msg-cjk' _ "$project_dir"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "commit message contains CJK characters" ]]

    write_file "$project_dir/.test-msg-issue" "feat: add governance docs" "" "Closes #123"
    run bash -c 'cd "$1" && .husky/commit-msg .test-msg-issue' _ "$project_dir"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Issue reference trailers" ]]

    run bash -c 'cd "$1" && printf "%s\n" "refs/heads/main 0000000000000000000000000000000000000000 refs/heads/main 1111111111111111111111111111111111111111" | .husky/pre-push' _ "$project_dir"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "禁止删除 main 分支" ]]
}
