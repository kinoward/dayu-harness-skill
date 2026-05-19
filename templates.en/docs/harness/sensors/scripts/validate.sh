#!/usr/bin/env bash
# validate.sh — verification script run after installing/changing constraints
# Usage:
#   validate.sh [--json] [project_root]
# Exit codes: 0=all pass, 1=failures present, 2=script error
set -euo pipefail

JSON_MODE=false
PROJECT_ROOT="."

# Parse arguments
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

# Normalize project path
PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)" || {
    echo "Error: unable to resolve project path '$PROJECT_ROOT'" >&2
    exit 2
}

# ---- Result storage ----
CHECKS_JSON=""       # JSON object array fragment
PASSED=0
FAILED=0
SKIPPED=0
DESC_LINES=""        # Natural-language failure description

# ---- JSON escaping helper ----
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# ---- Check recording ----
# Parameters: item_name status detail
# status: pass | fail | skip
record_check() {
    local item="$1"
    local status="$2"
    local detail="$3"

    case "$status" in
        pass) PASSED=$((PASSED + 1)) ;;
        fail) FAILED=$((FAILED + 1)) ;;
        skip) SKIPPED=$((SKIPPED + 1)) ;;
    esac

    local escaped_item
    local escaped_detail
    escaped_item=$(json_escape "$item")
    escaped_detail=$(json_escape "$detail")

    if [ -n "$CHECKS_JSON" ]; then
        CHECKS_JSON+=","
    fi
    CHECKS_JSON+="{\"item\":\"${escaped_item}\",\"status\":\"${status}\",\"detail\":\"${escaped_detail}\"}"

    # Collect failed items for the natural-language summary.
    if [ "$status" = "fail" ]; then
        if [ -n "$DESC_LINES" ]; then
            DESC_LINES+=$'\n'
        fi
        DESC_LINES+="  ✗ ${item}: ${detail}"
    elif [ "$status" = "skip" ]; then
        if [ -n "$DESC_LINES" ]; then
            DESC_LINES+=$'\n'
        fi
        DESC_LINES+="  - ${item}: ${detail}"
    fi
}

# ---- Output helper ----
log_text() {
    if [ "$JSON_MODE" = false ]; then
        echo "$@"
    else
        echo "$@" >&2
    fi
}

# ---- Main logic ----

if [ "$JSON_MODE" = false ]; then
    echo "=== Dayu Harness Skill validation ==="
    echo "Project path: $PROJECT_ROOT"
    echo ""
fi

# 1. Validate husky hooks are executable + parseable
log_text "--- husky hooks ---"
HUSKY_HOOKS=(
    "commit-msg"
    "pre-commit"
    "pre-push"
)
for hook in "${HUSKY_HOOKS[@]}"; do
    hook_path="$PROJECT_ROOT/.husky/$hook"
    if [ -f "$hook_path" ]; then
        if [ -x "$hook_path" ]; then
            # Run bash syntax check if first line is a shell shebang.
            syn_ok=true
            if head -1 "$hook_path" 2>/dev/null | grep -qE '(sh|bash)'; then
                if bash -n "$hook_path" 2>/dev/null; then
                    syn_ok=true
                else
                    syn_ok=false
                fi
            fi

            if [ "$syn_ok" = true ]; then
                record_check "husky/$hook" "pass" "Executable and syntax is valid"
                log_text "  ✓ .husky/$hook executable and syntax-valid"
            else
                record_check "husky/$hook" "fail" "Executable but bash syntax check failed"
                log_text "  ✗ .husky/$hook executable but bash syntax check failed"
            fi
        else
            record_check "husky/$hook" "fail" "File exists but is not executable"
            log_text "  ✗ .husky/$hook not executable"
        fi
    else
        record_check "husky/$hook" "skip" ".husky/$hook not installed"
        log_text "  - .husky/$hook not installed"
    fi
done

# 2. Validate commitlint config
log_text "--- commitlint ---"
if [ -f "$PROJECT_ROOT/commitlint.config.cjs" ] || [ -f "$PROJECT_ROOT/commitlint.config.js" ]; then
    cl_path=""
    if [ -f "$PROJECT_ROOT/commitlint.config.cjs" ]; then
        cl_path="commitlint.config.cjs"
    else
        cl_path="commitlint.config.js"
    fi
    record_check "commitlint" "pass" "${cl_path} exists"
    log_text "  ✓ ${cl_path} exists"
else
    record_check "commitlint" "skip" "commitlint config file missing (possibly not enabled)"
    log_text "  - commitlint config file missing (possibly not enabled)"
fi

# 3. Validate GitHub workflows YAML syntax
log_text "--- GitHub workflows ---"
if [ -d "$PROJECT_ROOT/.github/workflows" ]; then
    has_python3=false
    if command -v python3 &>/dev/null; then
        # Check whether pyyaml is available.
        if python3 -c "import yaml" 2>/dev/null; then
            has_python3=true
        fi
    fi

    if [ "$has_python3" = false ]; then
        # If python3 or pyyaml unavailable, skip all workflow checks.
        for wf in "$PROJECT_ROOT/.github/workflows"/*.yml; do
            if [ -f "$wf" ]; then
                wf_name=$(basename "$wf")
                record_check "workflow/$wf_name" "skip" "skip YAML check (python3 or pyyaml unavailable)"
                log_text "  - $wf_name: skip YAML check (python3 or pyyaml unavailable)"
            fi
        done
    else
        for wf in "$PROJECT_ROOT/.github/workflows"/*.yml; do
            if [ -f "$wf" ]; then
                wf_name=$(basename "$wf")
                if python3 -c "import yaml; yaml.safe_load(open('$wf'))" 2>/dev/null; then
                    record_check "workflow/$wf_name" "pass" "YAML syntax valid"
                    log_text "  ✓ $wf_name YAML syntax valid"
                else
                    # Capture concrete parse error text.
                    yaml_err=$(python3 -c "import yaml; yaml.safe_load(open('$wf'))" 2>&1 | head -1 || true)
                    record_check "workflow/$wf_name" "fail" "YAML syntax error: ${yaml_err:-unknown}"
                    log_text "  ✗ $wf_name YAML syntax error: ${yaml_err:-unknown}"
                fi
            fi
        done
    fi
else
    record_check "workflow" "skip" ".github/workflows/ directory missing (CI may not be enabled)"
    log_text "  - .github/workflows/ directory missing (CI may not be enabled)"
fi

# 4. Validate ESLint config
log_text "--- ESLint ---"
eslint_found=false
eslint_file=""
for f in "eslint.config.cjs" "eslint.config.js" ".eslintrc.cjs" ".eslintrc.js" ".eslintrc.json" ".eslintrc"; do
    if [ -f "$PROJECT_ROOT/$f" ]; then
        eslint_found=true
        eslint_file="$f"
        break
    fi
done
if [ "$eslint_found" = true ]; then
    record_check "ESLint" "pass" "${eslint_file} exists"
    log_text "  ✓ ESLint config file exists (${eslint_file})"
else
    record_check "ESLint" "skip" "ESLint config file missing (possibly not enabled)"
    log_text "  - ESLint config file missing (possibly not enabled)"
fi

# 5. Validate Prettier config
log_text "--- Prettier ---"
prettier_found=false
prettier_file=""
for f in ".prettierrc" ".prettierrc.json" ".prettierrc.js" "prettier.config.js"; do
    if [ -f "$PROJECT_ROOT/$f" ]; then
        prettier_found=true
        prettier_file="$f"
        break
    fi
done
if [ "$prettier_found" = true ]; then
    record_check "Prettier" "pass" "${prettier_file} exists"
    log_text "  ✓ Prettier config file exists (${prettier_file})"
else
    record_check "Prettier" "skip" "Prettier config file missing (possibly not enabled)"
    log_text "  - Prettier config file missing (possibly not enabled)"
fi

# 6. Validate .gitignore
log_text "--- .gitignore ---"
if [ -f "$PROJECT_ROOT/.gitignore" ]; then
    record_check ".gitignore" "pass" ".gitignore exists"
    log_text "  ✓ .gitignore exists"
else
    record_check ".gitignore" "skip" ".gitignore missing (possibly not enabled)"
    log_text "  - .gitignore missing (possibly not enabled)"
fi

# 7. Generate description_nl
build_description_nl() {
    if [ "$FAILED" -eq 0 ] && [ "$SKIPPED" -eq 0 ]; then
        echo "All checks passed. Husky hooks, config files, and workflows are in a healthy state."
    elif [ "$FAILED" -eq 0 ]; then
        echo "Validation passed with ${SKIPPED} skipped item(s). Installed configuration is healthy.${DESC_LINES}"
    else
        echo "Found ${FAILED} failed check(s) (${PASSED} passed, ${SKIPPED} skipped). Needs remediation: ${DESC_LINES}"
    fi
}

DESC_NL=$(build_description_nl)

# 8. Output results
if [ "$JSON_MODE" = true ]; then
    cat <<JSONEOF
{
  "checks": [${CHECKS_JSON}],
  "summary": {"passed": ${PASSED}, "failed": ${FAILED}},
  "description_nl": "$(json_escape "$DESC_NL")"
}
JSONEOF
else
    echo ""
    echo "=== Validation Summary ==="
    echo "Passed: $PASSED"
    echo "Failed: $FAILED"
    echo "Skipped: $SKIPPED"

    if [ "$FAILED" -eq 0 ]; then
        echo "Status: pass"
        exit 0
    else
        echo "Status: fix required"
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
