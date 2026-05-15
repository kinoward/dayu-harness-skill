#!/usr/bin/env bash
# 差异分析脚本：对比两个配置并生成结构化 merge plan
set -euo pipefail

MODE="${1:-diff}"
FILE1="${2:-}"
FILE2="${3:-}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

is_manual_merge_required() {
    local target="$1"
    local base
    base="$(basename "$target")"

    case "$base" in
        .prettierrc|.prettierrc.js|.prettierrc.json|.prettierrc.json5) return 0 ;;
        .eslintrc|.eslintrc.js|.eslintrc.json|.eslintrc.cjs|eslint.config.js|eslint.config.cjs) return 0 ;;
        .lintstagedrc|.lintstagedrc.js|.lintstagedrc.json|commitlint.config.cjs|package.json) return 0 ;;
    esac

    case "$target" in
        *.yml|*.yaml|*.js|*.cjs|*.mjs|*.json|*.json5) return 0 ;;
        *) return 1 ;;
    esac
}

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

    if [ ! -f "$f1" ] && [ ! -f "$f2" ]; then
        echo "0 0"
        return 0
    fi

    if [ ! -f "$f1" ] && [ -f "$f2" ]; then
        echo "$(wc -l < "$f2" | tr -d ' ') 0"
        return 0
    fi

    if [ -f "$f1" ] && [ ! -f "$f2" ]; then
        echo "0 $(wc -l < "$f1" | tr -d ' ')"
        return 0
    fi

    local diff_output
    diff_output=$(diff -u "$f1" "$f2" 2>/dev/null || true)

    if [ -z "$diff_output" ]; then
        echo "0 0"
        return 0
    fi

    printf '%s\n' "$diff_output" | awk 'BEGIN { added=0; removed=0 }
        /^\+\+\+ / { next }
        /^--- / { next }
        /^\+/ { added += 1 }
        /^-/ { removed += 1 }
        END { printf "%d %d", added, removed }'
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
build_description() {
    local existing_path="$1"
    local existing_exists="$2"
    local incoming_path="$3"
    local added="$4"
    local removed="$5"
    local rec="$6"

    if [ "$rec" = "manual_required" ]; then
        if [ "$existing_exists" = "true" ]; then
            echo "检测到现有 ${existing_path}，文件类型/格式暂不支持自动合并。请手动合并内容后使用 replace 或 skip。"
        else
            echo "目标项目中暂无 ${incoming_path}。可安全写入（merge/replace 结果一致）。"
        fi
    elif [ "$added" -eq 0 ] && [ "$removed" -eq 0 ]; then
        echo "两个文件内容相同，无需变更。"
    elif [ "$existing_exists" = "false" ]; then
        echo "目标项目中没有对应文件，写入可完成全新安装（$added 行）。"
    elif [ "$removed" -eq 0 ]; then
        echo "检测到已有 ${existing_path}。Skill 版本新增 $added 行，不直接替换 $removed 行。可尝试自动合并。"
    else
        echo "检测到已有 ${existing_path}（$removed 行将与新增内容发生重叠）。建议在应用前人工确认。"
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

    local name1
    local name2
    name1="$(basename "$f1")"
    name2="$(basename "$f2")"

    echo "=== 变更描述 ==="
    echo "文件: $name1 → $name2"
    echo ""

    read -r added removed <<< "$(count_diff "$f1" "$f2")"

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

    local existing_exists="false"
    local existing_lines=0
    local incoming_lines=0
    local added=0
    local removed=0
    local status="clean"
    local rec="merge"
    local strategies='["merge", "replace", "skip"]'

    if [ -f "$existing" ]; then
        existing_exists="true"
        existing_lines=$(wc -l < "$existing" | tr -d ' ')
    fi

    if [ ! -f "$incoming" ]; then
        echo "diff-helper merge-plan: incoming file not found: $incoming" >&2
        status="error"
        rec="manual_required"
        strategies='["skip"]'
    elif [ "$existing_exists" = "true" ]; then
        read -r added removed <<< "$(count_diff "$existing" "$incoming")"
        if is_manual_merge_required "$incoming"; then
            status="manual_required"
            rec="manual_required"
            strategies='["replace", "skip"]'
        else
            status="conflict"
            rec=$(recommend_strategy "$added" "$removed")
        fi
    else
        read -r added removed <<< "$(count_diff "/dev/null" "$incoming")"
        incoming_lines=$(wc -l < "$incoming" | tr -d ' ')
    fi

    if [ -f "$incoming" ]; then
        incoming_lines=$(wc -l < "$incoming" | tr -d ' ')
    fi

    local desc
    if [ "$status" = "error" ]; then
        desc="Incoming file not found: $incoming."
    else
        desc=$(build_description "$existing" "$existing_exists" "$incoming" "$added" "$removed" "$rec")
    fi

    cat <<EOF
{
  "status": "$status",
  "existing": {
    "path": "$(json_escape "$existing")",
    "exists": $existing_exists,
    "lines": $existing_lines
  },
  "incoming": {
    "path": "$(json_escape "$incoming")",
    "lines": $incoming_lines
  },
  "diff": {
    "added": $added,
    "removed": $removed
  },
  "recommendation": "$rec",
  "strategies": $strategies,
  "description_nl": "$(json_escape "$desc")"
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
