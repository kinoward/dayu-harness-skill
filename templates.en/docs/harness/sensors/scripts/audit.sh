#!/usr/bin/env bash
# audit.sh — governance diagnostic: validate completeness of project governance structure
# Usage:
#   audit.sh [--json] [project_root]
# Exit code: 0=all pass, 1=failures found, 2=script error
set -euo pipefail

JSON_MODE=false
PROJECT_ROOT="."
ALLOWED_OPTIONAL_CAPABILITIES=(
    "ai.execution"
    "ai.memory"
    "git.commit-format"
    "github.branch-protection"
    "github.pr"
    "github.release-please"
    "knowledge.archive"
    "knowledge.adr"
    "knowledge.research"
    "knowledge.troubleshooting"
    "project.context"
    "project.gitignore"
    "quality.node-tooling"
    "quality.practices"
    "release.versioning"
)

is_allowed_optional_capability() {
    local capability="$1"
    local item
    [ -z "$capability" ] && return 1

    for item in "${ALLOWED_OPTIONAL_CAPABILITIES[@]}"; do
        [ "$item" = "$capability" ] && return 0
    done
    return 1
}

extract_optional_capability() {
    local raw_line="$1"
    local capability=""
    local clean_line

    clean_line="${raw_line//\`/}"
    if [[ "$clean_line" =~ (可选|Optional)[：:][[:space:]]*([A-Za-z0-9._-]+) ]]; then
        capability="${BASH_REMATCH[2]}"
    fi

    printf '%s' "$capability"
}

is_directory_index_header() {
    local line="$1"
    [[ "$line" =~ ^[[:space:]]*#{1,6}[[:space:]]*(目录索引|Directory Index)[[:space:]]*$ ]]
}

is_external_link() {
    local path="$1"
    case "$path" in
        http://*|https://*|mailto:*|\#*) return 0 ;;
        *) return 1 ;;
    esac
}

# Parse parameters
while [ $# -gt 0 ]; do
    case "$1" in
        --json)
            JSON_MODE=true
            shift
            ;;
        *)
            PROJECT_ROOT="$1"
            shift
            ;;
    esac
done

# Normalize project root path
PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)" || {
    echo "Error: unable to resolve project path '$PROJECT_ROOT'" >&2
    exit 2
}

# ---- Result storage ----
RESULTS_JSON=""          # JSON object array fragment
PASSED=0
FAILED=0
WARNINGS=0
TOTAL=0
DESC_LINES=""            # Natural-language failure summary for description_nl

# ---- JSON escaping helper ----
# Escape a string so it can be safely embedded in JSON string values
json_escape() {
    local s="$1"
    # Escape backslashes and quotes first
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    # Newline / CR / tab
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

resolve_relative_path() {
    local base_dir="$1"
    local target="$2"

    # Strip URL fragment
    target="${target%%\#*}"

    [ -z "$target" ] && { echo ""; return; }

    case "$target" in
        /*)
            target="${target#/}"
            ;;
    esac

    if [ -f "$PROJECT_ROOT/$target" ] || [ -d "$PROJECT_ROOT/$target" ]; then
        echo "$target"
        return
    fi

    local combined
    if [ "$base_dir" = "." ]; then
        combined="$target"
    else
        combined="$base_dir/$target"
    fi

    while echo "$combined" | grep -q '/\.\./\|/\.\.$\|/\./\|/\.$'; do
        combined=$(echo "$combined" | sed 's|/\./|/|g; s|/\.$||')
        combined=$(echo "$combined" | sed 's|/[^/]*/\.\./|/|g; s|/[^/]*/\.\.$||')
    done

    echo "$combined"
}

extract_markdown_links() {
    local file="$1"
    [ -f "$file" ] || return 0

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
    }
    ' "$file"
}

# ---- Record check result ----
# Params: check_name status detail
record_result() {
    local check="$1"
    local status="$2"
    local detail="$3"
    TOTAL=$((TOTAL + 1))

    case "$status" in
        pass)  PASSED=$((PASSED + 1))   ;;
        fail)  FAILED=$((FAILED + 1))   ;;
        warn)  WARNINGS=$((WARNINGS + 1)) ;;
    esac

    local escaped_check
    local escaped_detail
    escaped_check=$(json_escape "$check")
    escaped_detail=$(json_escape "$detail")

    if [ -n "$RESULTS_JSON" ]; then
        RESULTS_JSON+=","
    fi
    RESULTS_JSON+="{\"check\":\"${escaped_check}\",\"status\":\"${status}\",\"detail\":\"${escaped_detail}\"}"

    # Collect failed items for human-readable summary
    if [ "$status" = "fail" ] || [ "$status" = "warn" ]; then
        if [ -n "$DESC_LINES" ]; then
            DESC_LINES+=$'\n'
        fi
        local tag="✗"
        [ "$status" = "warn" ] && tag="⚠"
        DESC_LINES+="  ${tag} ${check}: ${detail}"
    fi
}

# ---- Log helper ----
log_text() {
    if [ "$JSON_MODE" = false ]; then
        echo "$@"
    else
        echo "$@" >&2
    fi
}

# ---- Main flow ----

if [ "$JSON_MODE" = false ]; then
    echo "=== Dayu Harness Skill Audit ==="
    echo "Project path: $PROJECT_ROOT"
    echo ""
fi

# 1. CLAUDE.md check
if [ -f "$PROJECT_ROOT/CLAUDE.md" ]; then
    if grep -q '@AGENTS.md' "$PROJECT_ROOT/CLAUDE.md"; then
        record_result "CLAUDE.md" "pass" "CLAUDE.md exists and references @AGENTS.md"
        log_text "  ✓ CLAUDE.md exists and references @AGENTS.md"
    else
        record_result "CLAUDE.md" "warn" "CLAUDE.md exists but does not reference @AGENTS.md"
        log_text "  ⚠ CLAUDE.md exists but does not reference @AGENTS.md"
    fi
else
    record_result "CLAUDE.md" "fail" "CLAUDE.md does not exist"
    log_text "  ✗ CLAUDE.md does not exist"
fi

# 2. Root AGENTS.md check + link validity
if [ -f "$PROJECT_ROOT/AGENTS.md" ]; then
    record_result "AGENTS.md" "pass" "Root AGENTS.md exists"
    log_text "  ✓ Root AGENTS.md exists"

    while IFS=$'\t' read -r _line_no raw_link raw_line; do
        raw_link="${raw_link-}"
        raw_line="${raw_line-}"
        [ -z "$raw_link" ] && continue

        case "$raw_link" in
            docs/*|./docs/*)
                ;;
            *)
                continue
                ;;
        esac

        if is_external_link "$raw_link"; then
            continue
        fi

        link="$(resolve_relative_path "." "$raw_link")"
        [ -z "$link" ] && continue
        optional_capability="$(extract_optional_capability "$raw_line")"
        exists=false
        if [ -f "$PROJECT_ROOT/$link" ] || [ -d "$PROJECT_ROOT/$link" ]; then
            exists=true
            record_result "AGENTS.md link: ${raw_link}" "pass" "Link valid: ${raw_link}"
            log_text "    ✓ ${raw_link}"
            continue
        fi

        if [ -n "$optional_capability" ]; then
            if is_allowed_optional_capability "$optional_capability"; then
                record_result "AGENTS.md link: ${raw_link}" "pass" "Optional capability not enabled; skipping broken-link check: ${raw_link} (${optional_capability})"
                log_text "    ✅ Optional capability not enabled; skipping: ${raw_link} (${optional_capability})"
            else
                record_result "AGENTS.md link: ${raw_link}" "fail" "Optional capability not in allowlist: ${optional_capability}"
                log_text "    ✗ Optional capability not in allowlist: ${optional_capability} (${raw_link})"
            fi
            continue
        fi

        record_result "AGENTS.md link: ${raw_link}" "fail" "Broken link: ${raw_link}"
        log_text "    ✗ Broken link: ${raw_link}"
    done < <(extract_markdown_links "$PROJECT_ROOT/AGENTS.md")
else
    record_result "AGENTS.md" "fail" "Root AGENTS.md does not exist"
    log_text "  ✗ Root AGENTS.md does not exist"
fi

# 3. docs/AGENTS.md check
if [ -f "$PROJECT_ROOT/docs/AGENTS.md" ]; then
    record_result "docs/AGENTS.md" "pass" "docs/AGENTS.md exists"
    log_text "  ✓ docs/AGENTS.md exists"
else
    record_result "docs/AGENTS.md" "fail" "docs/AGENTS.md does not exist"
    log_text "  ✗ docs/AGENTS.md does not exist"
fi

# 4. Subdirectory AGENTS.md check
SUBDIRS=(
    "docs/harness"
    "docs/harness/guides"
    "docs/harness/sensors"
    "docs/harness/sensors/scripts"
    "docs/harness/sensors/reviews"
    "docs/exec-plans"
    "docs/exec-plans/active"
    "docs/exec-plans/completed"
    "docs/generated"
    "docs/design-docs"
    "docs/troubleshooting"
    "docs/references"
    "docs/references/research"
    "docs/product-specs"
    "docs/archive"
    "docs/archive/product-specs"
)
for dir in "${SUBDIRS[@]}"; do
    if [ -d "$PROJECT_ROOT/$dir" ]; then
        if [ -f "$PROJECT_ROOT/$dir/AGENTS.md" ]; then
            record_result "$dir/AGENTS.md" "pass" "$dir/AGENTS.md exists"
            log_text "  ✓ $dir/AGENTS.md"
        else
            record_result "$dir/AGENTS.md" "warn" "$dir directory exists but AGENTS.md is missing"
            log_text "  ⚠ $dir directory exists but AGENTS.md is missing"
        fi
    else
        record_result "$dir/AGENTS.md" "warn" "$dir directory does not exist (may be skipped)"
        log_text "  - $dir directory does not exist (may be skipped)"
    fi
done

# 5. Coupled script/config checks
check_script() {
    local path="$1"
    local name="$2"
    if [ -f "$PROJECT_ROOT/$path" ]; then
        if [ -x "$PROJECT_ROOT/$path" ]; then
            record_result "$name ($path)" "pass" "$path is installed and executable"
            log_text "  ✓ $name ($path) is installed and executable"
        else
            record_result "$name ($path)" "warn" "$path is installed but not executable"
            log_text "  ⚠ $name ($path) is installed but not executable"
        fi
    else
        record_result "$name ($path)" "warn" "$path is not installed"
        log_text "  - $name ($path) is not installed"
    fi
}

path_exists() {
    local path
    for path in "$@"; do
        [ -e "$PROJECT_ROOT/$path" ] && return 0
    done
    return 1
}

if path_exists ".husky/commit-msg" "docs/harness/guides/commit-guidelines.md"; then
    check_script ".husky/commit-msg" "commit-msg hook"
else
    log_text "  - commit-msg hook not enabled, skipping"
fi

if path_exists ".husky/pre-commit" ".lintstagedrc.json" "eslint.config.cjs" "eslint.config.js" ".prettierrc"; then
    check_script ".husky/pre-commit" "pre-commit hook"
else
    log_text "  - pre-commit hook not enabled, skipping"
fi

if path_exists ".husky/pre-push" "docs/harness/guides/branch-protection.md" "docs/harness/guides/release-versioning.md" ".github/rulesets/protect-main.json" ".github/rulesets/protect-tags.json"; then
    check_script ".husky/pre-push" "pre-push hook"
else
    log_text "  - pre-push hook not enabled, skipping"
fi

# commitlint
if [ -f "$PROJECT_ROOT/commitlint.config.cjs" ]; then
    record_result "commitlint.config.cjs" "pass" "commitlint.config.cjs exists"
    log_text "  ✓ commitlint.config.cjs exists"
elif path_exists "docs/harness/guides/commit-guidelines.md"; then
    record_result "commitlint.config.cjs" "warn" "Commit format governance is enabled, but commitlint.config.cjs is not installed"
    log_text "  - commitlint.config.cjs not installed"
else
    log_text "  - commitlint not enabled, skipping"
fi

# docs/harness/sensors/scripts/ maintenance scripts
for script in audit.sh validate.sh diff-helper.sh check-consistency.sh; do
    if [ -f "$PROJECT_ROOT/docs/harness/sensors/scripts/$script" ]; then
        if [ -x "$PROJECT_ROOT/docs/harness/sensors/scripts/$script" ]; then
            record_result "docs/harness/sensors/scripts/$script" "pass" "docs/harness/sensors/scripts/$script is installed and executable"
            log_text "  ✓ docs/harness/sensors/scripts/$script"
        else
            record_result "docs/harness/sensors/scripts/$script" "warn" "docs/harness/sensors/scripts/$script is installed but not executable"
            log_text "  ⚠ docs/harness/sensors/scripts/$script is installed but not executable"
        fi
    else
        record_result "docs/harness/sensors/scripts/$script" "warn" "docs/harness/sensors/scripts/$script is not installed"
        log_text "  - docs/harness/sensors/scripts/$script is not installed"
    fi
done

# 6. Build description_nl
build_description_nl() {
    if [ "$FAILED" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
        echo "Project governance audit passed for all checks. Checked ${TOTAL} items; no errors or warnings. CLAUDE.md, AGENTS.md, subdirectory indexes, and coupled scripts are compliant."
    elif [ "$FAILED" -eq 0 ]; then
        echo "Project governance is mostly complete with ${WARNINGS} warnings. Main issues: ${DESC_LINES}"
    else
        echo "Project governance has ${FAILED} failures and ${WARNINGS} warnings (checked ${TOTAL} items). Items to fix: ${DESC_LINES}"
    fi
}

DESC_NL=$(build_description_nl)

# 7. Output
if [ "$JSON_MODE" = true ]; then
    cat <<JSONEOF
{
  "results": [${RESULTS_JSON}],
  "summary": {"total": ${TOTAL}, "passed": ${PASSED}, "failed": ${FAILED}, "warnings": ${WARNINGS}},
  "description_nl": "$(json_escape "$DESC_NL")"
}
JSONEOF
else
    echo ""
    echo "=== Audit Result ==="
    echo "Failed: $FAILED"
    echo "Warnings: $WARNINGS"
    echo "Total: $TOTAL"

    if [ "$FAILED" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
        echo "Status: PASS"
        exit 0
    elif [ "$FAILED" -eq 0 ]; then
        echo "Status: PASS (warnings)"
        exit 0
    else
        echo "Status: NEEDS FIX"
        exit 1
    fi
fi

# Exit code for JSON mode
if [ "$JSON_MODE" = true ]; then
    if [ "$FAILED" -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
fi
