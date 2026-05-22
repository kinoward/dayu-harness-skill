#!/usr/bin/env bash
# audit.sh — 诊断脚本：检查项目治理体系的完整性
# 用法:
#   audit.sh [--json] [project_root]
# 退出码: 0=全部通过, 1=存在失败项, 2=脚本错误
set -euo pipefail

JSON_MODE=false
PROJECT_ROOT="."
ALLOWED_OPTIONAL_CAPABILITIES=(
    "ai.execution"
    "ai.memory"
    "git.commit-format"
    "github.branch-protection"
    "github.pr"
    "github.repository-settings"
    "github.issue"
    "github.release-please"
    "quality.tdd"
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
RESULTS_JSON=""          # JSON 对象数组片段
PASSED=0
FAILED=0
WARNINGS=0
TOTAL=0
DESC_LINES=""            # 自然语言故障描述（用于 description_nl）

# ---- JSON 转义辅助函数 ----
# 转义字符串使其可安全嵌入 JSON 字符串值
json_escape() {
    local s="$1"
    # 反斜杠和双引号必须优先转义
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    # 换行、回车、制表符
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

resolve_relative_path() {
    local base_dir="$1"
    local target="$2"

    # 去掉 URL fragment
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

# ---- 检查结果记录 ----
# 参数: check_name status detail
# status: pass | fail | warn
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

    # 为自然语言描述收集失败的项
    if [ "$status" = "fail" ] || [ "$status" = "warn" ]; then
        if [ -n "$DESC_LINES" ]; then
            DESC_LINES+=$'\n'
        fi
        local tag="✗"
        [ "$status" = "warn" ] && tag="⚠"
        DESC_LINES+="  ${tag} ${check}: ${detail}"
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

# ---- 主逻辑 ----

if [ "$JSON_MODE" = false ]; then
    echo "=== 大禹治库 Skill 诊断 ==="
    echo "项目路径: $PROJECT_ROOT"
    echo ""
fi

# 1. CLAUDE.md 检查
if [ -f "$PROJECT_ROOT/CLAUDE.md" ]; then
    if grep -q '@AGENTS.md' "$PROJECT_ROOT/CLAUDE.md"; then
        record_result "CLAUDE.md" "pass" "CLAUDE.md 存在且引用 @AGENTS.md"
        log_text "  ✓ CLAUDE.md 存在且引用 @AGENTS.md"
    else
        record_result "CLAUDE.md" "warn" "CLAUDE.md 存在但未引用 @AGENTS.md"
        log_text "  ⚠ CLAUDE.md 存在但未引用 @AGENTS.md"
    fi
else
    record_result "CLAUDE.md" "fail" "CLAUDE.md 不存在"
    log_text "  ✗ CLAUDE.md 不存在"
fi

# 2. 根 AGENTS.md 检查 + 链接有效性
if [ -f "$PROJECT_ROOT/AGENTS.md" ]; then
    record_result "AGENTS.md" "pass" "根 AGENTS.md 存在"
    log_text "  ✓ 根 AGENTS.md 存在"

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
            record_result "AGENTS.md 链接: ${raw_link}" "pass" "链接有效: ${raw_link}"
            log_text "    ✓ ${raw_link}"
            continue
        fi

        if [ -n "$optional_capability" ]; then
            if is_allowed_optional_capability "$optional_capability"; then
                record_result "AGENTS.md 链接: ${raw_link}" "pass" "可选能力未部署，跳过断链检查: ${raw_link}（${optional_capability}）"
                log_text "    ✅ 可选能力未部署，跳过: ${raw_link} (${optional_capability})"
            else
                record_result "AGENTS.md 链接: ${raw_link}" "fail" "可选 capability 未在白名单: ${optional_capability}"
                log_text "    ✗ 可选 capability 未在白名单: ${optional_capability} (${raw_link})"
            fi
            continue
        fi

        record_result "AGENTS.md 链接: ${raw_link}" "fail" "断链: ${raw_link}"
        log_text "    ✗ 断链: ${raw_link}"
    done < <(extract_markdown_links "$PROJECT_ROOT/AGENTS.md")
else
    record_result "AGENTS.md" "fail" "根 AGENTS.md 不存在"
    log_text "  ✗ 根 AGENTS.md 不存在"
fi

# 3. docs/AGENTS.md 检查
if [ -f "$PROJECT_ROOT/docs/AGENTS.md" ]; then
    record_result "docs/AGENTS.md" "pass" "docs/AGENTS.md 存在"
    log_text "  ✓ docs/AGENTS.md 存在"
else
    record_result "docs/AGENTS.md" "fail" "docs/AGENTS.md 不存在"
    log_text "  ✗ docs/AGENTS.md 不存在"
fi

# 4. 子目录 AGENTS.md 检查
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
            record_result "$dir/AGENTS.md" "pass" "$dir/AGENTS.md 存在"
            log_text "  ✓ $dir/AGENTS.md"
        else
            record_result "$dir/AGENTS.md" "warn" "$dir/ 目录存在但缺少 AGENTS.md"
            log_text "  ⚠ $dir/ 存在但缺少 AGENTS.md"
        fi
    else
        record_result "$dir/AGENTS.md" "warn" "$dir/ 目录不存在（可能已跳过）"
        log_text "  - $dir/ 目录不存在（可能已跳过）"
    fi
done

# 5. 联动脚本与配置检查
check_script() {
    local path="$1"
    local name="$2"
    if [ -f "$PROJECT_ROOT/$path" ]; then
        if [ -x "$PROJECT_ROOT/$path" ]; then
            record_result "$name ($path)" "pass" "$path 已安装且可执行"
            log_text "  ✓ $name ($path) 已安装且可执行"
        else
            record_result "$name ($path)" "warn" "$path 已安装但不可执行"
            log_text "  ⚠ $name ($path) 已安装但不可执行"
        fi
    else
        record_result "$name ($path)" "warn" "$path 未安装"
        log_text "  - $name ($path) 未安装"
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
    log_text "  - commit-msg hook 未启用，跳过"
fi

if path_exists ".husky/pre-commit" ".lintstagedrc.json" "eslint.config.cjs" "eslint.config.js" ".prettierrc"; then
    check_script ".husky/pre-commit" "pre-commit hook"
else
    log_text "  - pre-commit hook 未启用，跳过"
fi

if path_exists ".husky/pre-push" "docs/harness/guides/branch-protection.md" "docs/harness/guides/release-versioning.md" ".github/rulesets/protect-main.json" ".github/rulesets/protect-tags.json"; then
    check_script ".husky/pre-push" "pre-push hook"
else
    log_text "  - pre-push hook 未启用，跳过"
fi

# commitlint
if [ -f "$PROJECT_ROOT/commitlint.config.cjs" ]; then
    record_result "commitlint.config.cjs" "pass" "commitlint.config.cjs 存在"
    log_text "  ✓ commitlint.config.cjs 存在"
elif path_exists "docs/harness/guides/commit-guidelines.md"; then
    record_result "commitlint.config.cjs" "warn" "已启用提交格式指南但 commitlint.config.cjs 未安装"
    log_text "  - commitlint.config.cjs 未安装"
else
    log_text "  - commitlint 未启用，跳过"
fi

# docs/harness/sensors/scripts/ 维护脚本
for script in audit.sh validate.sh diff-helper.sh check-consistency.sh; do
    if [ -f "$PROJECT_ROOT/docs/harness/sensors/scripts/$script" ]; then
        if [ -x "$PROJECT_ROOT/docs/harness/sensors/scripts/$script" ]; then
            record_result "docs/harness/sensors/scripts/$script" "pass" "docs/harness/sensors/scripts/$script 已安装且可执行"
            log_text "  ✓ docs/harness/sensors/scripts/$script"
        else
            record_result "docs/harness/sensors/scripts/$script" "warn" "docs/harness/sensors/scripts/$script 已安装但不可执行"
            log_text "  ⚠ docs/harness/sensors/scripts/$script 已安装但不可执行"
        fi
    else
        record_result "docs/harness/sensors/scripts/$script" "warn" "docs/harness/sensors/scripts/$script 未安装"
        log_text "  - docs/harness/sensors/scripts/$script 未安装"
    fi
done

# 6. 生成 description_nl
build_description_nl() {
    if [ "$FAILED" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
        echo "项目治理体系完整性检查全部通过。共检查 ${TOTAL} 项，无错误和警告。CLAUDE.md、AGENTS.md、子目录索引和联动脚本均符合规范。"
    elif [ "$FAILED" -eq 0 ]; then
        echo "项目治理体系基本完整，但存在 ${WARNINGS} 个警告项。主要问题：${DESC_LINES}"
    else
        echo "项目治理体系存在 ${FAILED} 个失败项和 ${WARNINGS} 个警告项（共检查 ${TOTAL} 项）。需要修复的问题：${DESC_LINES}"
    fi
}

DESC_NL=$(build_description_nl)

# 7. 结果输出
if [ "$JSON_MODE" = true ]; then
    printf '{\n'
    printf '  "results": [%s],\n' "$RESULTS_JSON"
    printf '  "summary": {"total": %s, "passed": %s, "failed": %s, "warnings": %s},\n' "$TOTAL" "$PASSED" "$FAILED" "$WARNINGS"
    printf '  "description_nl": "%s"\n' "$(json_escape "$DESC_NL")"
    printf '}\n'
else
    echo ""
    echo "=== 诊断结果 ==="
    echo "错误: $FAILED"
    echo "警告: $WARNINGS"
    echo "总计: $TOTAL"

    if [ "$FAILED" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
        echo "状态: 通过"
        exit 0
    elif [ "$FAILED" -eq 0 ]; then
        echo "状态: 通过（有警告）"
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
