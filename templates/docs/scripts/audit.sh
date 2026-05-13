#!/usr/bin/env bash
# audit.sh — 诊断脚本：检查项目治理体系的完整性
# 用法:
#   audit.sh [--json] [project_root]
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
    echo "=== docs-governance 诊断 ==="
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

    # 使用 POSIX 兼容正则提取 docs/ 开头的链接（macOS 兼容，不用 grep -P）
    # 将提取的链接保存到临时文件以避免 bash 数组在 set -u 下的兼容性问题
    _links_file="$PROJECT_ROOT/.docs-governance-audit-links.$$"
    : > "$_links_file"
    trap 'rm -f "$_links_file"' EXIT
    grep -oE '\[[^]]+\]\(docs/[^)]+\)' "$PROJECT_ROOT/AGENTS.md" 2>/dev/null | \
        sed 's/.*](\(docs\/[^)]*\)).*/\1/' > "$_links_file" || true

    if [ -s "$_links_file" ]; then
        while IFS= read -r link; do
            if [ -n "$link" ]; then
                if [ -f "$PROJECT_ROOT/$link" ] || [ -d "$PROJECT_ROOT/$link" ]; then
                    record_result "AGENTS.md 链接: $link" "pass" "链接有效: $link"
                    log_text "    ✓ $link"
                else
                    record_result "AGENTS.md 链接: $link" "fail" "断链: $link"
                    log_text "    ✗ 断链: $link"
                fi
            fi
        done < "$_links_file"
    fi
    rm -f "$_links_file"
    trap - EXIT
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
    "docs/practices"
    "docs/decisions"
    "docs/troubleshooting"
    "docs/research"
    "docs/project"
    "docs/archive"
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

check_script ".husky/commit-msg" "commit-msg hook"
check_script ".husky/pre-commit" "pre-commit hook"
check_script ".husky/pre-push" "pre-push hook"

# commitlint
if [ -f "$PROJECT_ROOT/commitlint.config.cjs" ]; then
    record_result "commitlint.config.cjs" "pass" "commitlint.config.cjs 存在"
    log_text "  ✓ commitlint.config.cjs 存在"
else
    record_result "commitlint.config.cjs" "warn" "commitlint.config.cjs 未安装"
    log_text "  - commitlint.config.cjs 未安装"
fi

# docs/scripts/ 维护脚本
for script in audit.sh validate.sh diff-helper.sh; do
    if [ -f "$PROJECT_ROOT/docs/scripts/$script" ]; then
        if [ -x "$PROJECT_ROOT/docs/scripts/$script" ]; then
            record_result "docs/scripts/$script" "pass" "docs/scripts/$script 已安装且可执行"
            log_text "  ✓ docs/scripts/$script"
        else
            record_result "docs/scripts/$script" "warn" "docs/scripts/$script 已安装但不可执行"
            log_text "  ⚠ docs/scripts/$script 已安装但不可执行"
        fi
    else
        record_result "docs/scripts/$script" "warn" "docs/scripts/$script 未安装"
        log_text "  - docs/scripts/$script 未安装"
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
    cat <<JSONEOF
{
  "results": [${RESULTS_JSON}],
  "summary": {"total": ${TOTAL}, "passed": ${PASSED}, "failed": ${FAILED}, "warnings": ${WARNINGS}},
  "description_nl": "$(json_escape "$DESC_NL")"
}
JSONEOF
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
