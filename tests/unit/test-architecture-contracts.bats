#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    WORK_ROOT="${BATS_TEST_DIRNAME}/.tmp"
    mkdir -p "$WORK_ROOT"
    WORK_DIR="${WORK_ROOT}/contract_$$"
    mkdir -p "$WORK_DIR"

    # Provide a writable mktemp replacement for scripts that use hard-coded
    # POSIX mktemp behavior and would otherwise fail in this sandbox.
    WRAPPER_DIR="$WORK_DIR/wrapper"
    mkdir -p "$WRAPPER_DIR"
    mktemp_script="$WRAPPER_DIR/mktemp"
    cat > "$mktemp_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode="file"
root="${BATS_MKTEMP_ROOT:-$PWD/.bats_mktemp}"
prefix="tmp"

while [ $# -gt 0 ]; do
  case "$1" in
    -d)
      mode="dir"
      shift
      ;;
    -p)
      root="$2"
      shift 2
      ;;
    -t)
      prefix="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
      ;;
  esac
done

mkdir -p "$root"
path="$root/${prefix}_$$$RANDOM"

if [ "$mode" = "dir" ]; then
  mkdir -p "$path"
else
  : > "$path"
fi

printf '%s\n' "$path"
EOF
    chmod +x "$mktemp_script"

    export BATS_MKTEMP_ROOT="$WORK_DIR/.mktemp"
    mkdir -p "$BATS_MKTEMP_ROOT"
    export WRAPPER_BIN="$WRAPPER_DIR"

    FIXTURE_EMPTY="$WORK_DIR/empty"
    cp -R "$REPO_ROOT/tests/fixtures/empty-project/." "$FIXTURE_EMPTY"
}

teardown() {
    rm -rf "$WORK_DIR"
}

run_with_wrapper() {
    PATH="${WRAPPER_BIN}:$PATH" run "$@"
}

write_file() {
    local file="$1"
    shift
    printf '%s\n' "$@" > "$file"
}

has_commit_msg_cjk_support() {
    command -v perl >/dev/null 2>&1
}

@test "canonical SKILL.md uses Codex-compatible frontmatter" {
    ! grep -q '^disable-model-invocation:' "$REPO_ROOT/SKILL.md"
    grep -q '^metadata:' "$REPO_ROOT/SKILL.md"
    grep -q 'invocation_policy: "explicit-command-only"' "$REPO_ROOT/SKILL.md"
    grep -q 'command: "/docs-governance"' "$REPO_ROOT/SKILL.md"

    local quick_validate="${CODEX_QUICK_VALIDATE:-$HOME/.codex/skills/.system/skill-creator/scripts/quick_validate.py}"
    [ -f "$quick_validate" ] || skip "Codex quick_validate.py not available"

    run python3 "$quick_validate" "$REPO_ROOT"
    [ "$status" -eq 0 ]
}

@test "Codex sidecar disables implicit invocation" {
    [ -f "$REPO_ROOT/agents/openai.yaml" ]
    grep -q 'display_name: "Docs Governance"' "$REPO_ROOT/agents/openai.yaml"
    grep -q 'default_prompt: "Use $docs-governance' "$REPO_ROOT/agents/openai.yaml"
    grep -q '^  allow_implicit_invocation: false$' "$REPO_ROOT/agents/openai.yaml"
}

@test "agent compatibility reference is discoverable" {
    [ -f "$REPO_ROOT/references/agent-compatibility.md" ]
    grep -q 'references/agent-compatibility.md' "$REPO_ROOT/SKILL.md"
    grep -q 'references/agent-compatibility.md' "$REPO_ROOT/AGENTS.md"
}

@test "capability manifest source paths resolve" {
    while IFS= read -r source_path; do
        [ -e "$REPO_ROOT/$source_path" ] || {
            echo "missing manifest source: $source_path"
            return 1
        }
    done < <(jq -r '.template_files[]?.src, .asset_files[]?.src' "$REPO_ROOT"/capabilities/*.json)

    while IFS= read -r installer_script; do
        [ -z "$installer_script" ] && continue
        [ -f "$REPO_ROOT/scripts/$installer_script" ] || {
            echo "missing installer script: scripts/$installer_script"
            return 1
        }
    done < <(jq -r '.installer?.script // empty' "$REPO_ROOT"/capabilities/*.json)
}

@test "core capability deploys scripts AGENTS index" {
    jq -e '.template_files[] | select(.src == "templates/docs/scripts/AGENTS.md" and .dst == "docs/scripts/AGENTS.md")' "$REPO_ROOT/capabilities/core.json"
    jq -e '.acceptance | index("Maintenance scripts AGENTS index exists")' "$REPO_ROOT/capabilities/core.json"
}

@test "scaffold --dry-run default only includes core" {
    run_with_wrapper bash "$REPO_ROOT/scripts/scaffold.sh" "$FIXTURE_EMPTY" --dry-run

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.mode == "dry-run"'
    echo "$output" | jq -e '.capability_count == 1'
    echo "$output" | jq -e '.capabilities | length == 1'
    echo "$output" | jq -e '.capabilities[0].id == "core"'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/scripts/AGENTS.md")] | length == 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/practices/commit-guidelines.md")] | length == 0'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == ".github/workflows/pr-lint.yml")] | length == 0'
}

@test "scaffold --enable github.release-please resolves dependencies" {
    run_with_wrapper bash "$REPO_ROOT/scripts/scaffold.sh" "$FIXTURE_EMPTY" --dry-run --enable github.release-please

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.mode == "dry-run"'
    echo "$output" | jq -e '.capabilities | map(.id) | sort == ["core", "git.commit", "github.pr", "github.release-please"]'
    echo "$output" | jq -e '.capability_count == 4'
}

@test "scaffold apply does not overwrite existing target files" {
    local target="$WORK_DIR/overlap-target"
    mkdir -p "$target"
    cp -R "$REPO_ROOT/tests/fixtures/empty-project/." "$target"
    echo "KEEP_THIS_CONTENT" > "$target/CLAUDE.md"

    run_with_wrapper bash "$REPO_ROOT/scripts/scaffold.sh" "$target" --apply

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.mode == "apply" and .status == "partial"'
    echo "$output" | jq -e '.files_existing >= 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "CLAUDE.md" and .status == "skipped_existing")] | length >= 1'
    [ "$(cat "$target/CLAUDE.md")" = "KEEP_THIS_CONTENT" ]
}

@test "scaffold apply allows non-installer capabilities when installer strategy is missing" {
    local target="$WORK_DIR/strat-scoped-target"
    mkdir -p "$target"
    cp -R "$REPO_ROOT/tests/fixtures/empty-project/." "$target"
    rm -rf "$target/AGENTS.md" "$target/CLAUDE.md" "$target/docs" "$target/.github" "$target/commitlint.config.cjs" "$target/release-please-config.json" "$target/.release-please-manifest.json" 2>/dev/null || true

    run_with_wrapper bash "$REPO_ROOT/scripts/scaffold.sh" "$target" --apply --enable github.release-please

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "needs_strategy"'
    echo "$output" | jq -e '.capabilities[] | select(.id=="git.commit").status == "needs_strategy"'
    echo "$output" | jq -e '.capabilities[] | select(.id=="github.pr").status == "ok"'
    echo "$output" | jq -e '.capabilities[] | select(.id=="github.release-please").status == "ok"'
    [ -f "$target/.github/workflows/pr-lint.yml" ]
    [ -f "$target/.github/workflows/release-please.yml" ]
    [ ! -f "$target/commitlint.config.cjs" ]
}

@test "all install-*.sh --check endpoints return JSON contract" {
    for script in "$REPO_ROOT"/scripts/install-*.sh; do
        run_with_wrapper bash "$script" "$FIXTURE_EMPTY" --check
        [ "$status" -eq 0 ]
        echo "$output" | jq -e 'has("status") and (has("items") and (.items | type == "array") and has("summary") and has("description_nl"))'
        echo "$output" | jq -e '.status == "clean"'
    done
}

@test "audit --json returns expected schema" {
    run_with_wrapper bash -c '"$1" --json "$2" 2>/dev/null' _ "$REPO_ROOT/templates/docs/scripts/audit.sh" "$FIXTURE_EMPTY"

    [ "$status" -eq 1 ]
    echo "$output" | jq -e 'has("results") and has("summary") and has("description_nl")'
    echo "$output" | jq -e '.summary.failed | type == "number"'
    echo "$output" | jq -e '.summary.total | type == "number"'
}

@test "validate --json returns expected schema" {
    run_with_wrapper bash -c '"$1" --json "$2" 2>/dev/null' _ "$REPO_ROOT/templates/docs/scripts/validate.sh" "$FIXTURE_EMPTY"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'has("checks") and ( .checks | type == "array" ) and has("summary") and has("description_nl")'
    echo "$output" | jq -e '.summary.failed | type == "number"'
    echo "$output" | jq -e '.summary.passed | type == "number"'
}

@test "check-consistency --json returns expected schema" {
    run_with_wrapper bash "$REPO_ROOT/templates/docs/scripts/check-consistency.sh" --json "$FIXTURE_EMPTY"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'has("checks") and ( .checks | type == "array" and length == 4 ) and has("summary") and has("description_nl")'
    echo "$output" | jq -e '.summary.total == 4'
}

@test "diff-helper merge-plan returns merge schema for changed files" {
    local existing="$WORK_DIR/diff-existing.txt"
    local incoming="$WORK_DIR/diff-incoming.txt"
    echo "alpha" > "$existing"
    echo -e "alpha\nbeta" > "$incoming"

    run_with_wrapper bash "$REPO_ROOT/templates/docs/scripts/diff-helper.sh" merge-plan "$existing" "$incoming"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "conflict" and .existing.exists == true and .diff.added == 1 and .diff.removed == 0'
}

@test "PR body is validated as GitHub-native" {
    local body_file="$WORK_DIR/pr-body-valid.md"
    write_file "$body_file" \
        "## Summary" \
        "- add validation for scaffold checks" \
        "## Implementation notes" \
        "- [x] \`npm test\`" \
        "## Test plan" \
        "- [x] \`npm run lint\`" \
        "Closes #123"

    run python3 "$REPO_ROOT/assets/github/scripts/pr_body_structure.py" < "$body_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: PR body passes all structure checks."* ]]
}

@test "PR body fails when Test plan section is missing" {
    local body_file="$WORK_DIR/pr-body-missing-test-plan.md"
    write_file "$body_file" \
        "## Summary" \
        "- fix commit policy" \
        "## Implementation notes" \
        "- [x] \`npm test\`" \
        "Closes #456"

    run python3 "$REPO_ROOT/assets/github/scripts/pr_body_structure.py" < "$body_file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Missing required section in PR body: ## Test plan"* ]]
}

@test "PR body fails when using a ## Closes heading" {
    local body_file="$WORK_DIR/pr-body-bad-closes.md"
    write_file "$body_file" \
        "## Summary" \
        "- fix issue" \
        "## Implementation notes" \
        "- [x] \`npm test\`" \
        "## Test plan" \
        "- [x] \`pytest tests\`" \
        "## Closes" \
        "Closes #789"

    run python3 "$REPO_ROOT/assets/github/scripts/pr_body_structure.py" < "$body_file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Do not use a '## Closes' heading in PR body."* ]]
}

@test "PR body accepts Closes #N trailer" {
    local body_file="$WORK_DIR/pr-body-inline-closes.md"
    write_file "$body_file" \
        "## Summary" \
        "- update docs" \
        "## Implementation notes" \
        "- [x] \`npm test\`" \
        "## Test plan" \
        "- [x] \`npm run build\`" \
        "Closes #901"

    run python3 "$REPO_ROOT/assets/github/scripts/pr_body_structure.py" < "$body_file"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: PR body passes all structure checks."* ]]
}

@test "commit-msg hook honors skip-cjk-check marker" {
    local msg_file="$WORK_DIR/commit-msg-with-marker.txt"
    write_file "$msg_file" \
        "feat: add commit message policy checks" \
        "添加中文描述" \
        "<!-- skip-cjk-check -->"

    run bash -c 'cd "$1" && "$2" "$3"' _ "$WORK_DIR" "$REPO_ROOT/assets/husky/commit-msg" "$msg_file"
    [ "$status" -eq 0 ]
}

@test "commit-msg hook rejects CJK content when checker support is available" {
    if ! has_commit_msg_cjk_support; then
        skip "commit-msg CJK check requires perl support"
    fi

    local msg_file="$WORK_DIR/commit-msg-cjk.txt"
    write_file "$msg_file" "feat: 添加中文提交信息"

    run bash -c 'cd "$1" && "$2" "$3"' _ "$WORK_DIR" "$REPO_ROOT/assets/husky/commit-msg" "$msg_file"
    [ "$status" -eq 1 ]
}
