#!/usr/bin/env bash
# validate.sh — 校验脚本：安装或修改约束后验证结果
# 用法:
#   validate.sh [--json] [project_root]
# 退出码: 0=全部通过, 1=存在失败项, 2=脚本错误
set -euo pipefail

JSON_MODE=false
PROJECT_ROOT="."

# 解析参数
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

# 规范化项目路径
PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)" || {
    echo "错误: 无法解析项目路径 '$PROJECT_ROOT'" >&2
    exit 2
}

# ---- 结果存储 ----
CHECKS_JSON=""       # JSON 对象数组片段
PASSED=0
FAILED=0
SKIPPED=0
DESC_LINES=""        # 自然语言故障描述

# ---- JSON 转义辅助函数 ----
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# ---- 检查结果记录 ----
# 参数: item_name status detail
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

    # 为自然语言描述收集失败的项
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

# ---- 辅助输出 ----
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
                record_check "$item" "pass" "${rel_path} JSON 语法有效"
                log_text "  ✓ ${rel_path} JSON 语法有效"
            else
                err="$(jq -e . "$file_path" 2>&1 | sed -n '1,1p' || true)"
                record_check "$item" "fail" "${rel_path} JSON 语法错误: ${err:-未知}"
                log_text "  ✗ ${rel_path} JSON 语法错误: ${err:-未知}"
            fi
        elif command -v python3 >/dev/null 2>&1; then
            if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$file_path" >/dev/null 2>&1; then
                record_check "$item" "pass" "${rel_path} JSON 语法有效"
                log_text "  ✓ ${rel_path} JSON 语法有效"
            else
                err="$(python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$file_path" 2>&1 | sed -n '1,1p' || true)"
                record_check "$item" "fail" "${rel_path} JSON 语法错误: ${err:-未知}"
                log_text "  ✗ ${rel_path} JSON 语法错误: ${err:-未知}"
            fi
        else
            record_check "$item" "skip" "缺少 jq/python3，跳过 ${rel_path} JSON 语法校验"
            log_text "  - 缺少 jq/python3，跳过 ${rel_path} JSON 语法校验"
        fi
    else
        if [ "$required" = "required" ]; then
            record_check "$item" "fail" "${rel_path} 缺失（功能可能未正确部署）"
            log_text "  ✗ ${rel_path} 缺失（功能可能未正确部署）"
        else
            record_check "$item" "skip" "${rel_path} 未部署（按可选能力处理）"
            log_text "  - ${rel_path} 未部署（按可选能力处理）"
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
                parse_error="JSON 语法错误"
            fi
        elif command -v python3 >/dev/null 2>&1; then
            local settings_json
            settings_json="$(python3 -c 'import json,sys; data=json.load(open(sys.argv[1])); print("%s %s" % (str(data.get("allow_auto_merge")).lower(), str(data.get("delete_branch_on_merge")).lower()))' "$file_path" 2>/dev/null || true)"
            allow_auto_merge="$(echo "$settings_json" | awk '{print $1}')"
            delete_branch_on_merge="$(echo "$settings_json" | awk '{print $2}')"
            if [ -z "$settings_json" ]; then
                parse_error="JSON 语法错误"
            fi
        else
            record_check "$item" "skip" "缺少 jq/python3，跳过 ${rel_path} 仓库设置严格校验"
            log_text "  - 缺少 jq/python3，跳过 ${rel_path} 仓库设置严格校验"
            return
        fi

        if [ -n "$parse_error" ]; then
            record_check "$item" "fail" "${rel_path} 配置解析失败（${parse_error}）"
            log_text "  ✗ ${rel_path} 配置解析失败（${parse_error}）"
            return
        fi

        if [ "$allow_auto_merge" != "true" ] || [ "$delete_branch_on_merge" != "true" ]; then
            local failures=""
            [ "$allow_auto_merge" != "true" ] && failures="allow_auto_merge=true"
            [ "$delete_branch_on_merge" != "true" ] && failures="${failures:+$failures, }delete_branch_on_merge=true"
            record_check "$item" "fail" "${rel_path} 未满足仓库级自动合并策略：${failures}"
            log_text "  ✗ ${rel_path} 未满足仓库级自动合并策略：${failures}"
            return
        fi

        record_check "$item" "pass" "${rel_path} 自动合并与删除分支设置正确"
        log_text "  ✓ ${rel_path} 自动合并与删除分支设置正确"
    else
        if [ "$required" = "required" ]; then
            record_check "$item" "fail" "${rel_path} 缺失（功能可能未正确部署）"
            log_text "  ✗ ${rel_path} 缺失（功能可能未正确部署）"
        else
            record_check "$item" "skip" "${rel_path} 未部署（按可选能力处理）"
            log_text "  - ${rel_path} 未部署（按可选能力处理）"
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
                record_check "$item" "pass" "${rel_path} Python 语法有效"
                log_text "  ✓ ${rel_path} Python 语法有效"
            else
                local err
                err="$(python3 -m py_compile "$file_path" 2>&1 | sed -n '1,1p' || true)"
                record_check "$item" "fail" "${rel_path} Python 语法错误: ${err:-未知}"
                log_text "  ✗ ${rel_path} Python 语法错误: ${err:-未知}"
            fi
        else
            record_check "$item" "skip" "缺少 python3，跳过 ${rel_path} 语法校验"
            log_text "  - 缺少 python3，跳过 ${rel_path} 语法校验"
        fi
    else
        if [ "$required" = "required" ]; then
            record_check "$item" "fail" "${rel_path} 缺失（功能可能未正确部署）"
            log_text "  ✗ ${rel_path} 缺失（功能可能未正确部署）"
        else
            record_check "$item" "skip" "${rel_path} 未部署（按可选能力处理）"
            log_text "  - ${rel_path} 未部署（按可选能力处理）"
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
                record_check "$item" "skip" "缺少 python3 yaml 库，跳过 ${rel_path} YAML 语法校验"
                log_text "  - 缺少 python3 yaml 库，跳过 ${rel_path} YAML 语法校验"
                return
            fi

            if python3 -c "import yaml; yaml.safe_load(open('$file_path'))" >/dev/null 2>&1; then
                record_check "$item" "pass" "${rel_path} YAML 语法有效"
                log_text "  ✓ ${rel_path} YAML 语法有效"
            else
                local yaml_err
                yaml_err="$(python3 -c "import yaml; yaml.safe_load(open('$file_path'))" 2>&1 | sed -n '1,1p' || true)"
                record_check "$item" "fail" "${rel_path} YAML 语法错误: ${yaml_err:-未知}"
                log_text "  ✗ ${rel_path} YAML 语法错误: ${yaml_err:-未知}"
            fi
        else
            record_check "$item" "skip" "缺少 python3，跳过 ${rel_path} YAML 语法校验"
            log_text "  - 缺少 python3，跳过 ${rel_path} YAML 语法校验"
        fi
    else
        if [ "$required" = "required" ]; then
            record_check "$item" "fail" "${rel_path} 缺失（功能可能未正确部署）"
            log_text "  ✗ ${rel_path} 缺失（功能可能未正确部署）"
        else
            record_check "$item" "skip" "${rel_path} 未部署（按可选能力处理）"
            log_text "  - ${rel_path} 未部署（按可选能力处理）"
        fi
    fi
}

# ---- 主逻辑 ----

if [ "$JSON_MODE" = false ]; then
    echo "=== 大禹治库 Skill 校验 ==="
    echo "项目路径: $PROJECT_ROOT"
    echo ""
fi

# 1. 校验 husky hooks 可执行性 + bash 语法检查
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
            # 进行 bash 语法检查（如果第一行是 shell）
            syn_ok=true
            if head -1 "$hook_path" 2>/dev/null | grep -qE '(sh|bash)'; then
                if bash -n "$hook_path" 2>/dev/null; then
                    syn_ok=true
                else
                    syn_ok=false
                fi
            fi

            if [ "$syn_ok" = true ]; then
                record_check "husky/$hook" "pass" "可执行且语法正确"
                log_text "  ✓ .husky/$hook 可执行且语法正确"
            else
                record_check "husky/$hook" "fail" "可执行但 bash 语法检查失败"
                log_text "  ✗ .husky/$hook 可执行但 bash 语法检查失败"
            fi
        else
            record_check "husky/$hook" "fail" "文件存在但不可执行"
            log_text "  ✗ .husky/$hook 不可执行"
        fi
    else
        record_check "husky/$hook" "skip" ".husky/$hook 未安装"
        log_text "  - .husky/$hook 未安装"
    fi
done

# 2. 校验 commitlint 配置
log_text "--- commitlint ---"
if [ -f "$PROJECT_ROOT/commitlint.config.cjs" ] || [ -f "$PROJECT_ROOT/commitlint.config.js" ]; then
    cl_path=""
    if [ -f "$PROJECT_ROOT/commitlint.config.cjs" ]; then
        cl_path="commitlint.config.cjs"
    else
        cl_path="commitlint.config.js"
    fi
    record_check "commitlint" "pass" "${cl_path} 存在"
    log_text "  ✓ ${cl_path} 存在"
else
    record_check "commitlint" "skip" "commitlint 配置文件不存在（可能未启用）"
    log_text "  - commitlint 配置文件不存在（可能未启用）"
fi

# 3. 校验 GitHub workflows YAML 语法
log_text "--- GitHub workflows ---"
if [ -d "$PROJECT_ROOT/.github/workflows" ]; then
    has_python3=false
    if command -v python3 &>/dev/null; then
        # 检查 pyyaml 是否可用
        if python3 -c "import yaml" 2>/dev/null; then
            has_python3=true
        fi
    fi

    if [ "$has_python3" = false ]; then
        # python3 不可用或缺少 pyyaml，标记所有 workflow 文件为 skip
        for wf in "$PROJECT_ROOT/.github/workflows"/*.yml; do
            if [ -f "$wf" ]; then
                wf_name=$(basename "$wf")
                record_check "workflow/$wf_name" "skip" "跳过 YAML 校验（python3 或 pyyaml 不可用）"
                log_text "  - $wf_name: 跳过 YAML 校验（python3 或 pyyaml 不可用）"
            fi
        done
    else
        for wf in "$PROJECT_ROOT/.github/workflows"/*.yml; do
            if [ -f "$wf" ]; then
                wf_name=$(basename "$wf")
                if python3 -c "import yaml; yaml.safe_load(open('$wf'))" 2>/dev/null; then
                    record_check "workflow/$wf_name" "pass" "YAML 语法有效"
                    log_text "  ✓ $wf_name YAML 语法有效"
                else
                    # 捕获具体错误信息
                    yaml_err=$(python3 -c "import yaml; yaml.safe_load(open('$wf'))" 2>&1 | head -1 || true)
                    record_check "workflow/$wf_name" "fail" "YAML 语法错误: ${yaml_err:-未知}"
                    log_text "  ✗ $wf_name YAML 语法错误: ${yaml_err:-未知}"
                fi
            fi
        done
    fi
else
    record_check "workflow" "skip" ".github/workflows/ 目录不存在（可能未启用 CI）"
    log_text "  - .github/workflows/ 目录不存在（可能未启用 CI）"
fi

# 4. 校验 GitHub 资产（JSON + 脚本）
log_text "--- GitHub assets ---"
if [ -f "$PROJECT_ROOT/.github/workflows/issue-lint.yml" ] || [ -f "$PROJECT_ROOT/.github/scripts/issue_depends_on.py" ]; then
    check_workflow_file "repo-workflow/issue-lint" ".github/workflows/issue-lint.yml" required
    check_python_script "repo-script/issue_depends_on.py" ".github/scripts/issue_depends_on.py" required
else
    record_check "repo-workflow/issue-lint" "skip" "issue-lint 工作流未部署（按可选能力处理）"
    record_check "repo-script/issue_depends_on.py" "skip" "issue 依赖检查脚本未部署（按可选能力处理）"
    log_text "  - issue-lint 工作流与脚本未部署（按可选能力处理）"
fi

if [ -f "$PROJECT_ROOT/.github/workflows/pr-lint.yml" ] || [ -f "$PROJECT_ROOT/.github/scripts/pr_body_structure.py" ]; then
    check_workflow_file "repo-workflow/pr-lint" ".github/workflows/pr-lint.yml" required
    check_python_script "repo-script/pr-body-structure.py" ".github/scripts/pr_body_structure.py" required
else
    record_check "repo-workflow/pr-lint" "skip" "pr-lint 工作流未部署（按可选能力处理）"
    record_check "repo-script/pr-body-structure.py" "skip" "PR body 结构检查脚本未部署（按可选能力处理）"
    log_text "  - pr-lint 工作流与 PR body 结构检查脚本未部署（按可选能力处理）"
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
                record_check "release/release-please-policy" "pass" "release-please 策略校验通过"
                log_text "  ✓ release-please 策略校验通过"
            else
                policy_err="$(cd "$PROJECT_ROOT" && python3 ".github/scripts/release_please_policy.py" ".github/release-please-policy.json" "." 2>&1 | sed -n '1,3p' | tr '\n' ' ' || true)"
                record_check "release/release-please-policy" "fail" "release-please 策略校验失败: ${policy_err:-未知}"
                log_text "  ✗ release-please 策略校验失败: ${policy_err:-未知}"
            fi
        else
            record_check "release/release-please-policy" "skip" "缺少 python3，跳过 release-please 策略执行校验"
            log_text "  - 缺少 python3，跳过 release-please 策略执行校验"
        fi
    else
        record_check "release/release-please-policy" "fail" "release-please 策略文件或脚本缺失"
        log_text "  ✗ release-please 策略文件或脚本缺失"
    fi
else
    record_check "release/repository-settings-policy" "skip" "release-please 策略未部署（按可选能力处理）"
    record_check "release/release-please-config" "skip" "release-please 配置未部署（按可选能力处理）"
    record_check "release/release-please-manifest" "skip" "release-please manifest 未部署（按可选能力处理）"
    record_check "release/workflow" "skip" "release-please 工作流未部署（按可选能力处理）"
    record_check "release/release-please-policy-script" "skip" "release-please 策略脚本未部署（按可选能力处理）"
    record_check "release/release-please-policy" "skip" "release-please 策略执行校验未部署（按可选能力处理）"
    log_text "  - release-please 相关资产未部署（按可选能力处理）"
fi

if [ -f "$PROJECT_ROOT/.github/dayu-harness/pr-tdd-policy.json" ] || [ -f "$PROJECT_ROOT/.github/scripts/pr_tdd_check.py" ]; then
    check_json_file "quality/pr-tdd-policy" ".github/dayu-harness/pr-tdd-policy.json" required
    check_python_script "quality/pr-tdd-check-script" ".github/scripts/pr_tdd_check.py" required
else
    record_check "quality/pr-tdd-policy" "skip" "TDD 策略未部署（按可选能力处理）"
    record_check "quality/pr-tdd-check-script" "skip" "TDD 检查脚本未部署（按可选能力处理）"
    log_text "  - TDD 策略与脚本未部署（按可选能力处理）"
fi

# 5. 校验 ESLint 配置
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
    record_check "ESLint" "pass" "${eslint_file} 存在"
    log_text "  ✓ ESLint 配置文件存在 (${eslint_file})"
else
    record_check "ESLint" "skip" "ESLint 配置文件不存在（可能未启用）"
    log_text "  - ESLint 配置文件不存在（可能未启用）"
fi

# 6. 校验 Prettier 配置
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
    record_check "Prettier" "pass" "${prettier_file} 存在"
    log_text "  ✓ Prettier 配置文件存在 (${prettier_file})"
else
    record_check "Prettier" "skip" "Prettier 配置文件不存在（可能未启用）"
    log_text "  - Prettier 配置文件不存在（可能未启用）"
fi

# 7. 校验 .gitignore
log_text "--- .gitignore ---"
if [ -f "$PROJECT_ROOT/.gitignore" ]; then
    record_check ".gitignore" "pass" ".gitignore 存在"
    log_text "  ✓ .gitignore 存在"
else
    record_check ".gitignore" "skip" ".gitignore 不存在（可能未启用）"
    log_text "  - .gitignore 不存在（可能未启用）"
fi

# 7. 生成 description_nl
build_description_nl() {
    if [ "$FAILED" -eq 0 ] && [ "$SKIPPED" -eq 0 ]; then
        echo "所有校验项均通过。husky hooks、配置文件和工作流均处于正常状态。"
    elif [ "$FAILED" -eq 0 ]; then
        echo "校验通过，但存在 ${SKIPPED} 个跳过项。已安装的配置均正常。${DESC_LINES}"
    else
        echo "存在 ${FAILED} 个校验失败项（通过 ${PASSED} 项，跳过 ${SKIPPED} 项）。需要修复：${DESC_LINES}"
    fi
}

DESC_NL=$(build_description_nl)

# 8. 结果输出
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
    echo "=== 校验结果 ==="
    echo "通过: $PASSED"
    echo "失败: $FAILED"
    echo "跳过: $SKIPPED"

    if [ "$FAILED" -eq 0 ]; then
        echo "状态: 通过"
        exit 0
    else
        echo "状态: 需要修复"
        exit 1
    fi
fi

# JSON 模式下的退出码
if [ "$JSON_MODE" = true ]; then
    if [ "$FAILED" -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
fi
