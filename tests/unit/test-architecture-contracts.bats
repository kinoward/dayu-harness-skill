#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TARGET_AGENTS_FILES=(
        "$REPO_ROOT/AGENTS.md"
        "$REPO_ROOT/docs/AGENTS.md"
        "$REPO_ROOT/templates/AGENTS.md"
        "$REPO_ROOT/templates/docs/AGENTS.md"
        "$REPO_ROOT/templates/docs/harness/AGENTS.md"
        "$REPO_ROOT/templates/docs/harness/guides/AGENTS.md"
        "$REPO_ROOT/templates/docs/harness/sensors/AGENTS.md"
        "$REPO_ROOT/templates/docs/harness/sensors/reviews/AGENTS.md"
        "$REPO_ROOT/templates/docs/harness/sensors/scripts/AGENTS.md"
        "$REPO_ROOT/templates/docs/exec-plans/AGENTS.md"
        "$REPO_ROOT/templates/docs/exec-plans/active/AGENTS.md"
        "$REPO_ROOT/templates/docs/exec-plans/completed/AGENTS.md"
        "$REPO_ROOT/templates/docs/generated/AGENTS.md"
        "$REPO_ROOT/templates/docs/design-docs/AGENTS.md"
        "$REPO_ROOT/templates/docs/product-specs/AGENTS.md"
        "$REPO_ROOT/templates/docs/archive/AGENTS.md"
        "$REPO_ROOT/templates/docs/archive/product-specs/AGENTS.md"
        "$REPO_ROOT/templates/docs/references/AGENTS.md"
        "$REPO_ROOT/templates/docs/references/research/AGENTS.md"
        "$REPO_ROOT/templates/docs/troubleshooting/AGENTS.md"
    )
    ALL_AGENTS_FILES=()
    while IFS= read -r agents_file; do
        ALL_AGENTS_FILES+=("$agents_file")
    done < <(
        find "$REPO_ROOT" \
            -path "$REPO_ROOT/.git" -prune \
            -o -path "$REPO_ROOT/tests/unit/.tmp" -prune \
            -o -name AGENTS.md -type f -print |
            sort
    )
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
{"name":"docs-governance-test","version":"1.0.0","devDependencies":{}}
JSON
  exit 0
fi

if [ "${1:-}" = "install" ]; then
  cat > package.json <<'JSON'
{"name":"docs-governance-test","version":"1.0.0","devDependencies":{"@commitlint/cli":"0.0.0","@commitlint/config-conventional":"0.0.0","eslint":"0.0.0","@eslint/js":"0.0.0","prettier":"0.0.0","lint-staged":"0.0.0"}}
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
exit 0
EOF
    chmod +x "$WRAPPER_DIR/gh"

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

extract_allowed_capabilities() {
    local script="$1"
    sed -n '/^ALLOWED_OPTIONAL_CAPABILITIES=(/,/^)/p' "$script" \
        | grep -oE '"[^"]+"' \
        | tr -d '"'
}

extract_markdown_links() {
    local file="$1"
    awk '
    {
        line = $0
        while (match(line, /\[[^]]+\]\([^)]*\)/)) {
            raw = substr(line, RSTART, RLENGTH)
            target = raw
            sub(/^.*\(/, "", target)
            sub(/\).*/, "", target)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", target)
            print NR "\t" target "\t" $0
            line = substr(line, RSTART + RLENGTH)
        }
    }' "$file"
}

extract_optional_capability() {
    local line="$1"
    local clean_line="${line//\`/}"
    if [[ "$clean_line" =~ 可选[：:][[:space:]]*([A-Za-z0-9._-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

is_external_link() {
    local path="$1"
    case "$path" in
        http://*|https://*|mailto:*|\#*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

resolve_relative_path() {
    local base_dir="$1"
    local target="$2"

    target="${target%%#*}"
    [ -z "$target" ] && { echo ""; return; }

    case "$target" in
        /*) target="${target#/}" ;;
    esac

    local combined="$target"
    [ "$base_dir" != "." ] && combined="$base_dir/$target"

    local resolved
    resolved="$(python3 -c 'import os,sys; print(os.path.normpath(sys.argv[1]).replace("\\\\", "/"))' "$combined")"
    resolved="${resolved#./}"

    echo "$resolved"
}

expected_agents_h1() {
    local file="$1"
    local relative="${file#"$REPO_ROOT/"}"

    if [ "$relative" = "AGENTS.md" ]; then
        echo "# AGENTS.md"
        return
    fi

    if [ "$relative" = "docs/AGENTS.md" ]; then
        echo "# docs/AGENTS.md"
        return
    fi

    if [[ "$relative" == templates/* ]]; then
        relative="${relative#templates/}"
        echo "# ${relative}"
        return
    fi

    if [[ "$relative" == tests/fixtures/* ]]; then
        local fixture_path="${relative#tests/fixtures/}"
        local fixture_suffix="${fixture_path#*/}"

        if [ "$fixture_path" = "$fixture_suffix" ]; then
            echo "# AGENTS.md"
        else
            echo "# ${fixture_suffix}"
        fi
        return
    fi

    echo "# ${relative}"
}

@test "canonical SKILL.md uses Codex-compatible frontmatter" {
    ! grep -q '^disable-model-invocation:' "$REPO_ROOT/SKILL.md"
    grep -q '^metadata:' "$REPO_ROOT/SKILL.md"
    grep -q 'invocation_policy: "explicit-command-only"' "$REPO_ROOT/SKILL.md"
    grep -q 'command: "/docs-governance"' "$REPO_ROOT/SKILL.md"

    local quick_validate="${CODEX_QUICK_VALIDATE:-$HOME/.codex/skills/.system/skill-creator/scripts/quick_validate.py}"
    [ -f "$quick_validate" ] || skip "Codex quick_validate.py not available"
    python3 -c 'import yaml' 2>/dev/null || skip "python yaml dependency not available"

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

@test "completion report template is a Skill-only runtime aid" {
    [ -f "$REPO_ROOT/docs/completion-report-template.md" ]
    grep -q 'docs/completion-report-template.md' "$REPO_ROOT/SKILL.md"
    grep -q 'docs/completion-report-template.md' "$REPO_ROOT/AGENTS.md"
    grep -q 'completion-report-template.md' "$REPO_ROOT/docs/AGENTS.md"
    ! jq -e -s 'any(.[]; any(.template_files[]?.src; . == "docs/completion-report-template.md") or any(.asset_files[]?.src; . == "docs/completion-report-template.md"))' "$REPO_ROOT"/capabilities/*.json >/dev/null
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

@test "core capability deploys harness indexes and scripts" {
    jq -e '.template_files[] | select(.src == "templates/docs/harness/maintenance.md" and .dst == "docs/harness/maintenance.md")' "$REPO_ROOT/capabilities/core.json"
    jq -e '.template_files[] | select(.src == "templates/docs/harness/AGENTS.md" and .dst == "docs/harness/AGENTS.md")' "$REPO_ROOT/capabilities/core.json"
    jq -e '.template_files[] | select(.src == "templates/docs/harness/sensors/scripts/AGENTS.md" and .dst == "docs/harness/sensors/scripts/AGENTS.md")' "$REPO_ROOT/capabilities/core.json"
    jq -e '.template_files[] | select(.src == "templates/docs/exec-plans/AGENTS.md" and .dst == "docs/exec-plans/AGENTS.md")' "$REPO_ROOT/capabilities/core.json"
    jq -e '.template_files[] | select(.src == "templates/docs/generated/AGENTS.md" and .dst == "docs/generated/AGENTS.md")' "$REPO_ROOT/capabilities/core.json"
    jq -e '.acceptance | index("Harness indexes exist")' "$REPO_ROOT/capabilities/core.json"
    jq -e '.acceptance | index("Generated docs index exists")' "$REPO_ROOT/capabilities/core.json"
    jq -e '.acceptance | index("Maintenance scripts AGENTS index exists")' "$REPO_ROOT/capabilities/core.json"
}

@test "scaffold --dry-run default includes mandatory governance and git capabilities" {
    run_with_wrapper bash "$REPO_ROOT/scripts/scaffold.sh" "$FIXTURE_EMPTY" --dry-run

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.mode == "dry-run"'
    echo "$output" | jq -e '.capability_count == 12'
    echo "$output" | jq -e '.capabilities | map(.id) | sort == ["ai.execution","ai.memory","core","git.commit-format","git.hooks","knowledge.adr","knowledge.archive","knowledge.research","knowledge.troubleshooting","project.context","project.gitignore","repo.language"]'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/harness/maintenance.md")] | length == 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/harness/AGENTS.md")] | length == 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/harness/guides/AGENTS.md")] | length == 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/harness/sensors/scripts/AGENTS.md")] | length == 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/generated/AGENTS.md")] | length == 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/harness/sensors/scripts/audit.sh")] | length == 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/harness/sensors/scripts/check-consistency.sh")] | length == 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/harness/sensors/scripts/diff-helper.sh")] | length == 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/harness/sensors/scripts/validate.sh")] | length == 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/harness/guides/commit-guidelines.md")] | length == 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/harness/guides/ai-execution.md")] | length == 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "docs/design-docs/AGENTS.md")] | length == 1'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == ".github/workflows/pr-lint.yml")] | length == 0'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == ".github/workflows/repo-language-pr-lint.yml")] | length == 0'
}

@test "environment preflight check script has machine-readable contract" {
    if [ ! -f "$REPO_ROOT/scripts/ensure-environment.sh" ]; then
        skip "ensure-environment.sh not available in this branch yet"
    fi

    run_with_wrapper bash "$REPO_ROOT/scripts/ensure-environment.sh" "$FIXTURE_EMPTY" --check --capabilities "core,git.hooks,git.commit-format,repo.language"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'has("status") and has("items") and ( .items | type == "array" ) and has("summary") and has("description_nl")'
    echo "$output" | jq -e 'has("missing_tools") and has("initializations") and has("installs") and has("user_actions") and has("errors")'
    echo "$output" | jq -e '.items | all(.status != null)'
    echo "$output" | jq -e '.status == "ok" or .status == "needs_initialization" or .status == "needs_install" or .status == "needs_user_action" or .status == "error"'
}

@test "environment preflight without explicit capabilities assumes mandatory defaults" {
    run_with_wrapper bash "$REPO_ROOT/scripts/ensure-environment.sh" "$FIXTURE_EMPTY" --check

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "needs_initialization"'
    echo "$output" | jq -e '.items | any(.kind == "tool" and .name == "node")'
    echo "$output" | jq -e '.items | any(.action == "git init")'
    echo "$output" | jq -e '.items | any(.action == "npm init -y")'
}

@test "environment preflight reports package dependency gaps as install work" {
    local target="$WORK_DIR/package-deps-target"
    mkdir -p "$target"
    git -C "$target" init >/dev/null
    git -C "$target" config core.hooksPath .husky
    write_file "$target/package.json" '{"name":"package-deps-target","version":"1.0.0","devDependencies":{}}'

    run_with_wrapper bash "$REPO_ROOT/scripts/ensure-environment.sh" "$target" --check --capabilities "git.commit-format"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "needs_install"'
    echo "$output" | jq -e '.initializations == 0'
    echo "$output" | jq -e '.installs == 1'
    echo "$output" | jq -e '.items | any(.kind == "npm_dependencies" and .status == "needs_install")'
}

@test "scaffold dry-run prioritizes mandatory environment blockers over file conflicts" {
    local target="$WORK_DIR/env-conflict-target"
    mkdir -p "$target"
    cp -R "$REPO_ROOT/tests/fixtures/empty-project/." "$target"
    write_file "$target/CLAUDE.md" "existing project entry"

    run_with_wrapper bash "$REPO_ROOT/scripts/scaffold.sh" "$target" --dry-run

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "needs_initialization"'
    echo "$output" | jq -e '.environment.status == "needs_initialization"'
    echo "$output" | jq -e '.files_existing >= 1'
}

@test "scaffold source references environment preflight integration point" {
    if [ ! -f "$REPO_ROOT/scripts/ensure-environment.sh" ]; then
        skip "ensure-environment.sh not available in this branch yet"
    fi

    run bash -c 'rg -n "ensure-environment\\.sh" "$1"' _ "$REPO_ROOT/scripts/scaffold.sh"
    [ "$status" -eq 0 ]
}

@test "environment preflight policy is documented across Q&A/Skill/README/maintenance" {
    grep -Eq 'ensure-environment\.sh .*--check|ensure-environment\.sh --check' "$REPO_ROOT/Q&A-TEMPLATE.md"
    grep -Eq 'ensure-environment\.sh .*--check|ensure-environment\.sh --check' "$REPO_ROOT/SKILL.md"
    grep -Eq 'ensure-environment\.sh .*--check|ensure-environment\.sh --check' "$REPO_ROOT/README.md"
    grep -Eq 'ensure-environment\.sh .*--check|ensure-environment\.sh --check' "$REPO_ROOT/templates/docs/harness/maintenance.md"
    grep -q -- '--capabilities' "$REPO_ROOT/Q&A-TEMPLATE.md"
    grep -q "缺失依赖" "$REPO_ROOT/templates/docs/harness/maintenance.md"
    grep -q "git init" "$REPO_ROOT/templates/docs/harness/maintenance.md"
    grep -q "npm init -y" "$REPO_ROOT/templates/docs/harness/maintenance.md"
}

@test "scaffold --enable github.release-please resolves dependencies" {
    run_with_wrapper bash "$REPO_ROOT/scripts/scaffold.sh" "$FIXTURE_EMPTY" --dry-run --enable github.release-please

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.mode == "dry-run"'
    echo "$output" | jq -e '.capabilities | map(.id) | sort == ["ai.execution","ai.memory","core","git.commit-format","git.hooks","github.pr","github.release-please","knowledge.adr","knowledge.archive","knowledge.research","knowledge.troubleshooting","project.context","project.gitignore","release.versioning","repo.language"]'
    echo "$output" | jq -e '.capability_count == 15'
}

@test "legacy capability ids and presets expand to new capability set" {
    run_with_wrapper bash "$REPO_ROOT/scripts/scaffold.sh" "$FIXTURE_EMPTY" --dry-run --enable git.commit,github.branch-release,quality.tooling,ai.collaboration,project.docs,archive.project

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.capabilities | map(.id) | sort == ["ai.execution","ai.memory","core","git.commit-format","git.hooks","github.branch-protection","knowledge.adr","knowledge.archive","knowledge.research","knowledge.troubleshooting","project.context","project.gitignore","quality.node-tooling","quality.practices","release.versioning","repo.language"]'

    run_with_wrapper bash "$REPO_ROOT/scripts/scaffold.sh" "$FIXTURE_EMPTY" --dry-run --enable github.delivery
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.capabilities | map(.id) | sort == ["ai.execution","ai.memory","core","git.commit-format","git.hooks","github.branch-protection","github.language","github.pr","knowledge.adr","knowledge.archive","knowledge.research","knowledge.troubleshooting","project.context","project.gitignore","repo.language"]'

    run_with_wrapper bash "$REPO_ROOT/scripts/scaffold.sh" "$FIXTURE_EMPTY" --dry-run --enable quality.standard
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.capabilities | map(.id) | sort == ["ai.execution","ai.memory","core","git.commit-format","git.hooks","knowledge.adr","knowledge.archive","knowledge.research","knowledge.troubleshooting","project.context","project.gitignore","quality.node-tooling","quality.practices","repo.language"]'
}

@test "split capabilities stay atomic in dry-run output" {
    run_with_wrapper bash "$REPO_ROOT/scripts/scaffold.sh" "$FIXTURE_EMPTY" --dry-run --enable git.commit-format
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == ".husky/pre-commit" or .dst == ".husky/pre-push")] | length == 0'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.capability == "git.commit-format" and .script == "install-husky.sh")] | length == 1'

    run_with_wrapper bash "$REPO_ROOT/scripts/scaffold.sh" "$FIXTURE_EMPTY" --dry-run --enable quality.practices
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '[.capabilities[].items[] | select(.dst == "eslint.config.js" or .dst == ".prettierrc" or .dst == ".lintstagedrc.json")] | length == 0'
    echo "$output" | jq -e '[.capabilities[].items[] | select(.capability == "quality.node-tooling" and .kind == "installer")] | length == 0'
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

@test "scaffold apply auto-merges clean installer capabilities when strategy is missing" {
    local target="$WORK_DIR/strat-scoped-target"
    mkdir -p "$target"
    cp -R "$REPO_ROOT/tests/fixtures/empty-project/." "$target"
    rm -rf "$target/AGENTS.md" "$target/CLAUDE.md" "$target/docs" "$target/.github" "$target/commitlint.config.cjs" "$target/release-please-config.json" "$target/.release-please-manifest.json" 2>/dev/null || true

    run_with_wrapper bash "$REPO_ROOT/scripts/scaffold.sh" "$target" --apply --enable github.release-please

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "ok"'
    echo "$output" | jq -e '.capabilities[] | select(.id=="git.commit-format").items[] | select(.kind=="installer").effective_strategy == "merge"'
    echo "$output" | jq -e '.capabilities[] | select(.id=="release.versioning").items[] | select(.kind=="installer").effective_strategy == "merge"'
    echo "$output" | jq -e '.capabilities[] | select(.id=="github.pr").status == "ok"'
    echo "$output" | jq -e '.capabilities[] | select(.id=="github.release-please").status == "ok"'
    [ -f "$target/.github/workflows/pr-lint.yml" ]
    [ -f "$target/.github/workflows/release-please.yml" ]
    [ -f "$target/commitlint.config.cjs" ]
}

@test "AGENTS.md uses directory index convention and avoids legacy structure marker" {
    for file in "${ALL_AGENTS_FILES[@]}"; do
        if [ ! -f "$file" ]; then
            echo "未发现 AGENTS 文件: $file"
            return 1
        fi
        first_line="$(sed -n '1p' "$file")"
        expected_h1="$(expected_agents_h1 "$file")"
        if [ "$first_line" != "$expected_h1" ]; then
            echo "AGENTS 标题不符合要求: $file"
            echo "  当前: $first_line"
            echo "  期望: $expected_h1"
            return 1
        fi
        grep -q '^## 目录索引$' "$file"
        grep -Fqx -- '- [AGENTS.md](AGENTS.md) - 当前索引' "$file"
        grep -q '目录索引变化时，必须同步更新本区块' "$file"
        ! grep -q '^## 目录结构' "$file"
    done
}

@test "optional capability ids align with manifest and script allowlist" {
    local expected="$WORK_DIR/expected_capabilities.txt"
    local check_list="$WORK_DIR/check_allowed.txt"
    local audit_list="$WORK_DIR/audit_allowed.txt"

    jq -r 'select(.id != "core" and (.internal != true)).id' "$REPO_ROOT/capabilities/"*.json | sort -u > "$expected"
    extract_allowed_capabilities "$REPO_ROOT/templates/docs/harness/sensors/scripts/check-consistency.sh" | sort -u > "$check_list"
    extract_allowed_capabilities "$REPO_ROOT/templates/docs/harness/sensors/scripts/audit.sh" | sort -u > "$audit_list"

    diff -u "$expected" "$check_list"
    diff -u "$expected" "$audit_list"

    is_allowed_capability() {
        local capability="$1"
        [ -z "$capability" ] && return 1
        grep -Fxq "$capability" "$expected" 2>/dev/null
    }

    for file in "${TARGET_AGENTS_FILES[@]}"; do
        while IFS=$'\t' read -r _line_no _target raw_line; do
            raw_line="${raw_line-}"
            opt="$(extract_optional_capability "$raw_line")"
            [ -n "$opt" ] || continue
            is_allowed_capability "$opt" || {
                echo "非法可选能力 id: $opt in $file"
                return 1
            }
        done < <(extract_markdown_links "$file")
    done
}

@test "AGENTS markdown optional links must match capability boundaries" {
    local path_capability_file="$WORK_DIR/path_capability.tsv"
    : > "$path_capability_file"

    lookup_capability() {
        local target="$1"
        awk -F'\t' -v target="$target" '$1 == target {print $2; exit}' "$path_capability_file"
    }

    lookup_capability_for_path() {
        local target="$1"
        local capability

        capability="$(lookup_capability "$target")"
        if [ -z "$capability" ]; then
            if [ "${target%/}" = "$target" ]; then
                capability="$(lookup_capability "$target/")"
            else
                capability="$(lookup_capability "${target%/}")"
            fi
        fi

        echo "$capability"
    }

    for manifest in "$REPO_ROOT"/capabilities/*.json; do
        cap_id="$(jq -r '.id' "$manifest")"
        while IFS= read -r src_path; do
            [ -z "$src_path" ] && continue
            printf '%s\t%s\n' "$src_path" "$cap_id" >> "$path_capability_file"

            dir_path="${src_path%/*}"
            while [ -n "$dir_path" ] && [ "$dir_path" != "." ]; do
                printf '%s\t%s\n' "$dir_path/" "$cap_id" >> "$path_capability_file"
                if [[ "$dir_path" == */* ]]; then
                    dir_path="${dir_path%/*}"
                else
                    break
                fi
            done
        done < <(jq -r '.template_files[]?.src' "$manifest")
    done

    allowed_file="$WORK_DIR/check_allowed.txt"
    default_file="$WORK_DIR/default_capabilities.txt"
    extract_allowed_capabilities "$REPO_ROOT/templates/docs/harness/sensors/scripts/check-consistency.sh" | sort -u > "$allowed_file"
    jq -r 'select(.default == true).id' "$REPO_ROOT/capabilities/"*.json | sort -u > "$default_file"
    is_allowed_capability() {
        local capability="$1"
        [ -z "$capability" ] && return 1
        grep -Fxq "$capability" "$allowed_file" 2>/dev/null
    }
    is_default_capability() {
        local capability="$1"
        [ -z "$capability" ] && return 1
        grep -Fxq "$capability" "$default_file" 2>/dev/null
    }

    for file in "${TARGET_AGENTS_FILES[@]}"; do
        relative="${file#$REPO_ROOT/}"
        base="${relative%/*}"
        [ "$base" = "$relative" ] && base="."
        current_capability="$(lookup_capability_for_path "$relative")"

        while IFS=$'\t' read -r _line_no target raw_line; do
            target="${target-}"
            raw_line="${raw_line-}"
            [ -z "$target" ] && continue
            is_external_link "$target" && continue

            resolved="$(resolve_relative_path "$base" "$target")"
            [ -z "$resolved" ] && continue

            optional_capability="$(extract_optional_capability "$raw_line")"
            target_capability="$(lookup_capability_for_path "$resolved")"

            if [ "$current_capability" = "core" ] && [ -n "$target_capability" ] && [ "$target_capability" != "core" ]; then
                if is_default_capability "$target_capability"; then
                    if [ -n "$optional_capability" ]; then
                        echo "核心 AGENTS 指向默认能力时不应标可选: $relative 链接 $resolved，能力 $target_capability"
                        return 1
                    fi
                elif [ -z "$optional_capability" ]; then
                    echo "核心 AGENTS 指向非 core 能力时必须标可选: $relative 链接 $resolved，期望 $target_capability"
                    return 1
                elif [ "$optional_capability" != "$target_capability" ]; then
                    echo "核心 AGENTS 的可选能力应匹配目标能力: $relative 链接 $resolved 标记 $optional_capability，期望 $target_capability"
                    return 1
                fi
            fi

            if [ -n "$current_capability" ] && [ "$current_capability" != "core" ] && [ -n "$target_capability" ] && [ "$target_capability" = "$current_capability" ] && [ -n "$optional_capability" ]; then
                echo "同一 capability 内部 AGENTS 不应标可选: $relative 链接 $resolved"
                return 1
            fi

            if [ ! -e "$REPO_ROOT/$resolved" ]; then
                if [ -z "$optional_capability" ]; then
                    echo "缺失可选标记导致断链: $relative -> $resolved"
                    return 1
                fi
                if ! is_allowed_capability "$optional_capability"; then
                    echo "非法可选 capability id: $optional_capability"
                    return 1
                fi

            fi
        done < <(extract_markdown_links "$file")
    done
}

@test "all manifest installer scripts --check endpoints return JSON contract" {
    local installer_scripts
    installer_scripts="$(jq -r 'select(.installer.script != null) | .installer.script' "$REPO_ROOT/capabilities/"*.json | sort -u)"
    while IFS= read -r installer_script; do
        [ -z "$installer_script" ] && continue
        local script="$REPO_ROOT/scripts/$installer_script"
        local capability
        capability="$(jq -r --arg script "$installer_script" 'select(.installer.script == $script) | .id' "$REPO_ROOT/capabilities/"*.json | head -n 1)"

        if [ ! -f "$script" ]; then
            echo "Manifest 引用的 installer 缺失：$installer_script"
            return 1
        fi

        if [ "$installer_script" = "install-husky.sh" ]; then
            run_with_wrapper env DOCS_GOVERNANCE_CAPABILITY="${capability:-git.commit-format}" bash "$script" "$FIXTURE_EMPTY" --check
        else
            run_with_wrapper bash "$script" "$FIXTURE_EMPTY" --check
        fi
        [ "$status" -eq 0 ]
        echo "$output" | jq -e 'has("status") and (has("items") and (.items | type == "array") and has("summary") and has("description_nl"))'
        echo "$output" | jq -e '.status == "clean"'
    done <<< "$installer_scripts"
}

@test "install-husky requires an explicit capability selection" {
    run_with_wrapper bash "$REPO_ROOT/scripts/install-husky.sh" "$FIXTURE_EMPTY" --check

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.status == "error"'
    echo "$output" | jq -e '.items | any(.capability == "<unset>")'
}

@test "audit --json returns expected schema" {
    run_with_wrapper bash -c '"$1" --json "$2" 2>/dev/null' _ "$REPO_ROOT/templates/docs/harness/sensors/scripts/audit.sh" "$FIXTURE_EMPTY"

    [ "$status" -eq 1 ]
    echo "$output" | jq -e 'has("results") and has("summary") and has("description_nl")'
    echo "$output" | jq -e '.summary.failed | type == "number"'
    echo "$output" | jq -e '.summary.total | type == "number"'
}

@test "validate --json returns expected schema" {
    run_with_wrapper bash -c '"$1" --json "$2" 2>/dev/null' _ "$REPO_ROOT/templates/docs/harness/sensors/scripts/validate.sh" "$FIXTURE_EMPTY"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'has("checks") and ( .checks | type == "array" ) and has("summary") and has("description_nl")'
    echo "$output" | jq -e '.summary.failed | type == "number"'
    echo "$output" | jq -e '.summary.passed | type == "number"'
}

@test "check-consistency --json returns expected schema" {
    run_with_wrapper bash "$REPO_ROOT/templates/docs/harness/sensors/scripts/check-consistency.sh" --json "$FIXTURE_EMPTY"

    [ "$status" -eq 0 ]
    echo "$output" | jq -e 'has("checks") and ( .checks | type == "array" and length == 4 ) and has("summary") and has("description_nl")'
    echo "$output" | jq -e '.summary.total == 4'
}

@test "diff-helper merge-plan returns merge schema for changed files" {
    local existing="$WORK_DIR/diff-existing.txt"
    local incoming="$WORK_DIR/diff-incoming.txt"
    echo "alpha" > "$existing"
    echo -e "alpha\nbeta" > "$incoming"

    run_with_wrapper bash "$REPO_ROOT/templates/docs/harness/sensors/scripts/diff-helper.sh" merge-plan "$existing" "$incoming"
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

@test "PR lint workflow explicitly skips release-please PRs" {
    grep -q 'Detect release-please PR' "$REPO_ROOT/assets/github/workflows/pr-lint.yml"
    grep -q 'release-please--' "$REPO_ROOT/assets/github/workflows/pr-lint.yml"
    grep -q "steps.detect-release-please.outputs.skip != 'true'" "$REPO_ROOT/assets/github/workflows/pr-lint.yml"
}

@test "GitHub workflows do not shell-interpolate user-controlled PR or issue text" {
    ! rg -n '\$\{\{ github\.event\.(pull_request|issue)\.(title|body)' "$REPO_ROOT/assets/github/workflows"
    grep -q 'jq -r' "$REPO_ROOT/assets/github/workflows/repo-language-pr-lint.yml"
    grep -q 'jq -r' "$REPO_ROOT/assets/github/workflows/repo-language-issue-lint.yml"
}

@test "commit-msg hook honors skip-cjk-check marker" {
    local target="$WORK_DIR/repo-language-skip"
    mkdir -p "$target"
    run_with_wrapper env DOCS_GOVERNANCE_CAPABILITY=repo.language bash "$REPO_ROOT/scripts/install-husky.sh" "$target" --apply merge
    [ "$status" -eq 0 ]

    local msg_file="$WORK_DIR/commit-msg-with-marker.txt"
    write_file "$msg_file" \
        "feat: add commit message policy checks" \
        "添加中文描述" \
        "<!-- skip-cjk-check -->"

    run bash -c 'cd "$1" && .husky/commit-msg "$2"' _ "$target" "$msg_file"
    [ "$status" -eq 0 ]
}

@test "commit-msg hook rejects CJK content when checker support is available" {
    if ! has_commit_msg_cjk_support; then
        skip "commit-msg CJK check requires perl support"
    fi

    local target="$WORK_DIR/repo-language-cjk"
    mkdir -p "$target"
    run_with_wrapper env DOCS_GOVERNANCE_CAPABILITY=repo.language bash "$REPO_ROOT/scripts/install-husky.sh" "$target" --apply merge
    [ "$status" -eq 0 ]

    local msg_file="$WORK_DIR/commit-msg-cjk.txt"
    write_file "$msg_file" "feat: 添加中文提交信息"

    run bash -c 'cd "$1" && .husky/commit-msg "$2"' _ "$target" "$msg_file"
    [ "$status" -eq 1 ]
}

@test "hook installer installs only selected capability snippets" {
    local target="$WORK_DIR/hook-atomicity"
    mkdir -p "$target"

    run_with_wrapper env DOCS_GOVERNANCE_CAPABILITY=git.commit-format bash "$REPO_ROOT/scripts/install-husky.sh" "$target" --apply merge
    [ "$status" -eq 0 ]
    [ -f "$target/.husky/commit-msg" ]
    [ ! -f "$target/.husky/pre-commit" ]
    [ ! -f "$target/.husky/pre-push" ]
    grep -q 'docs-governance:git.commit-format' "$target/.husky/commit-msg"
    ! grep -q 'docs-governance:repo.language' "$target/.husky/commit-msg"
}

@test "pre-push snippets can share the same hook stdin" {
    local target="$WORK_DIR/pre-push-snippets"
    mkdir -p "$target"

    run_with_wrapper env DOCS_GOVERNANCE_CAPABILITY=github.branch-protection bash "$REPO_ROOT/scripts/install-husky.sh" "$target" --apply merge
    [ "$status" -eq 0 ]
    run_with_wrapper env DOCS_GOVERNANCE_CAPABILITY=release.versioning bash "$REPO_ROOT/scripts/install-husky.sh" "$target" --apply merge
    [ "$status" -eq 0 ]

    run bash -c 'cd "$1" && printf "%s\n" "refs/heads/main 0000000000000000000000000000000000000000 refs/heads/main 1111111111111111111111111111111111111111" | .husky/pre-push' _ "$target"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "deleting main is not allowed" ]]

    run bash -c 'cd "$1" && printf "%s\n" "refs/heads/main 2222222222222222222222222222222222222222 refs/heads/main 1111111111111111111111111111111111111111" | .husky/pre-push' _ "$target"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "direct push to main is not allowed" ]]

    run bash -c 'cd "$1" && printf "%s\n" "refs/tags/v1.0.0 0000000000000000000000000000000000000000 refs/tags/v1.0.0 1111111111111111111111111111111111111111" | .husky/pre-push' _ "$target"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "deleting release tag v1.0.0 is not allowed" ]]
}
