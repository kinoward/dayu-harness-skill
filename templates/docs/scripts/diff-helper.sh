#!/usr/bin/env bash
# 差异分析脚本：对比两个配置并生成结构化 merge plan
set -euo pipefail

MODE="${1:-diff}"
FILE1="${2:-}"
FILE2="${3:-}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"

usage() {
    echo "用法:"
    echo "  diff-helper.sh diff <file1> <file2>        生成 unified diff"
    echo "  diff-helper.sh describe <file1> <file2>     生成自然语言描述"
    echo "  diff-helper.sh check <file>                 检查文件是否存在"
    echo "  diff-helper.sh merge-plan <existing> <incoming>  生成结构化 merge plan (JSON)"
}

# 统计 unified diff 中的增减行数（排除 diff 头行）
count_diff() {
    local f1="$1"
    local f2="$2"
    local added=$(diff -u "$f1" "$f2" 2>/dev/null | grep -c '^+' | grep -cv '^+++' || echo 0)
    local removed=$(diff -u "$f1" "$f2" 2>/dev/null | grep -c '^-' | grep -cv '^---' || echo 0)
    echo "$added $removed"
}

# 生成推荐策略
recommend_strategy() {
    local added="$1"
    local removed="$2"
    if [ "$added" -eq 0 ] && [ "$removed" -eq 0 ]; then
        echo "skip"
    elif [ "$removed" -eq 0 ] && [ "$added" -gt 0 ]; then
        echo "merge"
    elif [ "$added" -gt 0 ] && [ "$removed" -gt 0 ]; then
        echo "merge"
    else
        echo "replace"
    fi
}

# 生成自然语言描述
gen_description() {
    local existing_name="$1"
    local incoming_name="$2"
    local added="$3"
    local removed="$4"
    local rec="$5"

    if [ "$added" -eq 0 ] && [ "$removed" -eq 0 ]; then
        echo "两个文件内容相同，无需变更。"
    elif [ ! -f "$FILE1" ]; then
        echo "目标项目中没有 $existing_name，将新建此文件（$added 行）。建议执行全新安装。"
    elif [ "$removed" -eq 0 ]; then
        echo "检测到已有 $existing_name。Skill 版本在此基础上新增了 $added 行内容，不影响现有 $removed 行。建议合并：保留现有配置，补充新增部分。"
    else
        echo "检测到已有 $existing_name（$removed 行将被替换为 $added 行）。两个版本存在差异。建议合并：逐项对比后决定保留哪些内容。"
    fi
}

describe_diff() {
    local f1="$1"
    local f2="$2"

    if [ ! -f "$f1" ]; then
        echo "文件不存在: $f1"
        return 1
    fi
    if [ ! -f "$f2" ]; then
        echo "文件不存在: $f2"
        return 1
    fi

    local name1=$(basename "$f1")
    local name2=$(basename "$f2")

    echo "=== 变更描述 ==="
    echo "文件: $name1 → $name2"
    echo ""

    read added removed <<< "$(count_diff "$f1" "$f2")"

    if [ "$added" -eq 0 ] && [ "$removed" -eq 0 ]; then
        echo "两个文件内容相同，无变更。"
    else
        echo "新增 $added 行，移除 $removed 行。"
        echo ""
        echo "--- diff ---"
        diff -u "$f1" "$f2" || true
    fi
}

merge_plan() {
    local existing="$1"
    local incoming="$2"

    if [ ! -f "$incoming" ]; then
        cat <<EOF
{"status":"error","error":"incoming file not found: $incoming"}
EOF
        return 2
    fi

    local existing_name=$(basename "$existing" 2>/dev/null || echo "$existing")
    local incoming_name=$(basename "$incoming")
    local existing_exists="false"
    local existing_lines=0

    if [ -f "$existing" ]; then
        existing_exists="true"
        existing_lines=$(wc -l < "$existing" | tr -d ' ')
    fi

    local added=0
    local removed=0
    if [ "$existing_exists" = "true" ]; then
        read added removed <<< "$(count_diff "$existing" "$incoming")"
    else
        added=$(wc -l < "$incoming" | tr -d ' ')
    fi

    local rec=$(recommend_strategy "$added" "$removed")
    local desc=$(gen_description "$existing_name" "$incoming_name" "$added" "$removed" "$rec")

    # 检查 incoming 中是否包含 CJK 检测逻辑
    local has_cjk="false"
    if grep -q 'CJK\|cjk\|\\p{Han}\|\\p{Katakana}\|\\p{Hiragana}' "$incoming" 2>/dev/null; then
        has_cjk="true"
    fi

    cat <<EOF
{
  "status": "$([ "$existing_exists" = "true" ] && echo "conflict" || echo "clean")",
  "existing": {
    "path": "$existing",
    "exists": $existing_exists,
    "lines": $existing_lines
  },
  "incoming": {
    "path": "$incoming",
    "lines": $(wc -l < "$incoming" | tr -d ' ')
  },
  "diff": {
    "added": $added,
    "removed": $removed
  },
  "has_cjk_detection": $has_cjk,
  "recommendation": "$rec",
  "description_nl": "$desc"
}
EOF
}

check_exists() {
    local f="$1"
    if [ -f "$f" ]; then
        echo "✓ 已存在: $f"
        return 0
    else
        echo "✗ 不存在: $f"
        return 1
    fi
}

case "$MODE" in
    diff)
        if [ -z "$FILE1" ] || [ -z "$FILE2" ]; then
            usage
            exit 2
        fi
        diff -u "$FILE1" "$FILE2" || true
        ;;
    describe)
        if [ -z "$FILE1" ] || [ -z "$FILE2" ]; then
            usage
            exit 2
        fi
        describe_diff "$FILE1" "$FILE2"
        ;;
    merge-plan)
        if [ -z "$FILE1" ] || [ -z "$FILE2" ]; then
            usage
            exit 2
        fi
        merge_plan "$FILE1" "$FILE2"
        ;;
    check)
        if [ -z "$FILE1" ]; then
            usage
            exit 2
        fi
        check_exists "$FILE1"
        ;;
    *)
        usage
        exit 2
        ;;
esac
