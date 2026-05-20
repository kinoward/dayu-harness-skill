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

check_json_file() {
    local item="$1"
    local rel_path="$2"
    local required="${3:-optional}"
    local file_path="$PROJECT_ROOT/$rel_path"
    local err=""

    if [ -f "$file_path" ]; then
        if command -v jq >/dev/null 2>&1; then
            if jq -e . "$file_path" >/dev/null 2>&1; then
                record_check "$item" "pass" "${rel_path} JSON syntax is valid"
                log_text "  ✓ ${rel_path} JSON syntax is valid"
            else
                err="$(jq -e . "$file_path" 2>&1 | sed -n '1,1p' || true)"
                record_check "$item" "fail" "${rel_path} JSON syntax error: ${err:-unknown}"
                log_text "  ✗ ${rel_path} JSON syntax error: ${err:-unknown}"
            fi
        elif command -v python3 >/dev/null 2>&1; then
            if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$file_path" >/dev/null 2>&1; then
                record_check "$item" "pass" "${rel_path} JSON syntax is valid"
                log_text "  ✓ ${rel_path} JSON syntax is valid"
            else
                err="$(python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$file_path" 2>&1 | sed -n '1,1p' || true)"
                record_check "$item" "fail" "${rel_path} JSON syntax error: ${err:-unknown}"
                log_text "  ✗ ${rel_path} JSON syntax error: ${err:-unknown}"
            fi
        else
            record_check "$item" "skip" "Skip ${rel_path} JSON syntax check (missing jq/python3)"
            log_text "  - Missing jq/python3, skipping JSON syntax check for ${rel_path}"
        fi
    else
        if [ "$required" = "required" ]; then
            record_check "$item" "fail" "${rel_path} missing (required capability may not be fully deployed)"
            log_text "  ✗ ${rel_path} missing (required capability may not be fully deployed)"
        else
            record_check "$item" "skip" "${rel_path} not deployed (optional capability)"
            log_text "  - ${rel_path} not deployed (optional capability)"
        fi
    fi
}

check_pull_request_settings_json() {
    local item="$1"
    local rel_path="$2"
    local required="${3:-optional}"
    local file_path="$PROJECT_ROOT/$rel_path"

    if [ -f "$file_path" ]; then
        local allow_auto_merge
        local delete_branch_on_merge
        local parse_error=""

        if command -v jq >/dev/null 2>&1; then
            allow_auto_merge="$(jq -r '.allow_auto_merge // empty' "$file_path" 2>/dev/null || true)"
            delete_branch_on_merge="$(jq -r '.delete_branch_on_merge // empty' "$file_path" 2>/dev/null || true)"
            if ! jq -e . "$file_path" >/dev/null 2>&1; then
                parse_error="JSON parse error"
            fi
        elif command -v python3 >/dev/null 2>&1; then
            local settings_json
            settings_json="$(python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print("%s %s" % (str(data.get("allow_auto_merge")).lower(), str(data.get("delete_branch_on_merge")).lower()))' "$file_path" 2>/dev/null || true)"
            allow_auto_merge="$(echo "$settings_json" | awk '{print $1}')"
            delete_branch_on_merge="$(echo "$settings_json" | awk '{print $2}')"
            if [ -z "$settings_json" ]; then
                parse_error="JSON parse error"
            fi
        else
            record_check "$item" "skip" "Missing jq/python3, skipping strict pull-request settings check for ${rel_path}"
            log_text "  - Missing jq/python3, skipping strict pull-request settings check for ${rel_path}"
            return
        fi

        if [ -n "$parse_error" ]; then
            record_check "$item" "fail" "Failed to parse ${rel_path} settings (${parse_error})"
            log_text "  ✗ Failed to parse ${rel_path} settings (${parse_error})"
            return
        fi

        if [ "$allow_auto_merge" != "true" ] || [ "$delete_branch_on_merge" != "true" ]; then
            local failures=""
            [ "$allow_auto_merge" != "true" ] && failures="allow_auto_merge=true"
            [ "$delete_branch_on_merge" != "true" ] && failures="${failures:+$failures, }delete_branch_on_merge=true"
            record_check "$item" "fail" "${rel_path} does not satisfy required pull-request settings: ${failures}"
            log_text "  ✗ ${rel_path} does not satisfy required pull-request settings: ${failures}"
            return
        fi

        record_check "$item" "pass" "${rel_path} pull-request settings satisfy required automation flags"
        log_text "  ✓ ${rel_path} pull-request settings satisfy required automation flags"
    else
        if [ "$required" = "required" ]; then
            record_check "$item" "fail" "${rel_path} missing (required capability may not be fully deployed)"
            log_text "  ✗ ${rel_path} missing (required capability may not be fully deployed)"
        else
            record_check "$item" "skip" "${rel_path} not deployed (optional capability)"
            log_text "  - ${rel_path} not deployed (optional capability)"
        fi
    fi
}

check_python_script() {
    local item="$1"
    local rel_path="$2"
    local required="${3:-optional}"
    local file_path="$PROJECT_ROOT/$rel_path"

    if [ -f "$file_path" ]; then
        if command -v python3 >/dev/null 2>&1; then
            if python3 -m py_compile "$file_path" >/dev/null 2>&1; then
                record_check "$item" "pass" "${rel_path} Python syntax is valid"
                log_text "  ✓ ${rel_path} Python syntax is valid"
            else
                local err
                err="$(python3 -m py_compile "$file_path" 2>&1 | sed -n '1,1p' || true)"
                record_check "$item" "fail" "${rel_path} Python syntax error: ${err:-unknown}"
                log_text "  ✗ ${rel_path} Python syntax error: ${err:-unknown}"
            fi
        else
            record_check "$item" "skip" "Missing python3, skipping ${rel_path} syntax check"
            log_text "  - Missing python3, skipping ${rel_path} syntax check"
        fi
    else
        if [ "$required" = "required" ]; then
            record_check "$item" "fail" "${rel_path} missing (required capability may not be fully deployed)"
            log_text "  ✗ ${rel_path} missing (required capability may not be fully deployed)"
        else
            record_check "$item" "skip" "${rel_path} not deployed (optional capability)"
            log_text "  - ${rel_path} not deployed (optional capability)"
        fi
    fi
}

check_workflow_file() {
    local item="$1"
    local rel_path="$2"
    local required="${3:-optional}"
    local file_path="$PROJECT_ROOT/$rel_path"

    if [ -f "$file_path" ]; then
        if command -v python3 >/dev/null 2>&1; then
            if ! python3 -c "import yaml" >/dev/null 2>&1; then
                record_check "$item" "skip" "Skip ${rel_path} YAML syntax check (missing python3 yaml package)"
                log_text "  - Missing python3 yaml package, skipping ${rel_path} YAML syntax check"
                return
            fi

            if python3 -c "import yaml; yaml.safe_load(open('$file_path'))" >/dev/null 2>&1; then
                record_check "$item" "pass" "${rel_path} YAML syntax is valid"
                log_text "  ✓ ${rel_path} YAML syntax is valid"
            else
                local yaml_err
                yaml_err="$(python3 -c "import yaml; yaml.safe_load(open('$file_path'))" 2>&1 | sed -n '1,1p' || true)"
                record_check "$item" "fail" "${rel_path} YAML syntax error: ${yaml_err:-unknown}"
                log_text "  ✗ ${rel_path} YAML syntax error: ${yaml_err:-unknown}"
            fi
        else
            record_check "$item" "skip" "Missing python3, skipping ${rel_path} YAML syntax check"
            log_text "  - Missing python3, skipping ${rel_path} YAML syntax check"
        fi
    else
        if [ "$required" = "required" ]; then
            record_check "$item" "fail" "${rel_path} missing (required capability may not be fully deployed)"
            log_text "  ✗ ${rel_path} missing (required capability may not be fully deployed)"
        else
            record_check "$item" "skip" "${rel_path} not deployed (optional capability)"
            log_text "  - ${rel_path} not deployed (optional capability)"
        fi
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

# 4. Validate GitHub assets (JSON + script)
log_text "--- GitHub assets ---"
if [ -f "$PROJECT_ROOT/.github/workflows/issue-lint.yml" ] || [ -f "$PROJECT_ROOT/.github/scripts/issue_depends_on.py" ]; then
    check_workflow_file "repo-workflow/issue-lint" ".github/workflows/issue-lint.yml" required
    check_python_script "repo-script/issue_depends_on.py" ".github/scripts/issue_depends_on.py" required
else
    record_check "repo-workflow/issue-lint" "skip" "issue-lint workflow not deployed (optional capability skipped)"
    record_check "repo-script/issue_depends_on.py" "skip" "issue depends-on script not deployed (optional capability skipped)"
    log_text "  - issue-lint workflow and script are not deployed (optional capabilities)"
fi

if [ -f "$PROJECT_ROOT/.github/workflows/pr-lint.yml" ] || [ -f "$PROJECT_ROOT/.github/scripts/pr_body_structure.py" ]; then
    check_workflow_file "repo-workflow/pr-lint" ".github/workflows/pr-lint.yml" required
    check_python_script "repo-script/pr-body-structure.py" ".github/scripts/pr_body_structure.py" required
else
    record_check "repo-workflow/pr-lint" "skip" "pr-lint workflow not deployed (optional capability skipped)"
    record_check "repo-script/pr-body-structure.py" "skip" "PR body structure script not deployed (optional capability skipped)"
    log_text "  - pr-lint workflow and PR body structure script are not deployed (optional capabilities)"
fi

check_json_file "repo-config/pull-request-settings" ".github/repository/pull-request-settings.json"
check_pull_request_settings_json "repo-config/pull-request-settings-auto" ".github/repository/pull-request-settings.json"

if [ -f "$PROJECT_ROOT/.github/workflows/release-please.yml" ] || [ -f "$PROJECT_ROOT/.github/scripts/release_please_policy.py" ] || [ -f "$PROJECT_ROOT/.github/release-please-policy.json" ] || [ -f "$PROJECT_ROOT/release-please-config.json" ] || [ -f "$PROJECT_ROOT/.release-please-manifest.json" ]; then
    check_json_file "release/repository-settings-policy" ".github/release-please-policy.json" required
    check_json_file "release/release-please-config" "release-please-config.json" required
    check_json_file "release/release-please-manifest" ".release-please-manifest.json" required
    check_workflow_file "release/workflow" ".github/workflows/release-please.yml" required
    check_python_script "release/release-please-policy-script" ".github/scripts/release_please_policy.py" required
    if [ -f "$PROJECT_ROOT/.github/scripts/release_please_policy.py" ] && [ -f "$PROJECT_ROOT/.github/release-please-policy.json" ]; then
        if command -v python3 >/dev/null 2>&1; then
            if (cd "$PROJECT_ROOT" && python3 ".github/scripts/release_please_policy.py" ".github/release-please-policy.json" ".") >/dev/null 2>&1; then
                record_check "release/release-please-policy" "pass" "release-please policy validation passed"
                log_text "  ✓ release-please policy validation passed"
            else
                policy_err="$(cd "$PROJECT_ROOT" && python3 ".github/scripts/release_please_policy.py" ".github/release-please-policy.json" "." 2>&1 | sed -n '1,3p' | tr '\n' ' ' || true)"
                record_check "release/release-please-policy" "fail" "release-please policy validation failed: ${policy_err:-unknown}"
                log_text "  ✗ release-please policy validation failed: ${policy_err:-unknown}"
            fi
        else
            record_check "release/release-please-policy" "skip" "Missing python3, skipping release-please policy execution"
            log_text "  - Missing python3, skipping release-please policy execution"
        fi
    else
        record_check "release/release-please-policy" "fail" "release-please policy file or script is missing"
        log_text "  ✗ release-please policy file or script is missing"
    fi
else
    record_check "release/repository-settings-policy" "skip" "release-please policy not deployed (optional capability skipped)"
    record_check "release/release-please-config" "skip" "release-please config not deployed (optional capability skipped)"
    record_check "release/release-please-manifest" "skip" "release-please manifest not deployed (optional capability skipped)"
    record_check "release/workflow" "skip" "release-please workflow not deployed (optional capability skipped)"
    record_check "release/release-please-policy-script" "skip" "release-please policy script not deployed (optional capability skipped)"
    record_check "release/release-please-policy" "skip" "release-please policy execution not deployed (optional capability skipped)"
    log_text "  - release-please assets are not deployed (optional capability)"
fi

if [ -f "$PROJECT_ROOT/.github/dayu-harness/pr-tdd-policy.json" ] || [ -f "$PROJECT_ROOT/.github/scripts/pr_tdd_check.py" ]; then
    check_json_file "quality/pr-tdd-policy" ".github/dayu-harness/pr-tdd-policy.json" required
    check_python_script "quality/pr-tdd-check-script" ".github/scripts/pr_tdd_check.py" required
else
    record_check "quality/pr-tdd-policy" "skip" "TDD policy not deployed (optional capability skipped)"
    record_check "quality/pr-tdd-check-script" "skip" "TDD check script not deployed (optional capability skipped)"
    log_text "  - TDD policy and script are not deployed (optional capability)"
fi

# 5. Validate ESLint config
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
