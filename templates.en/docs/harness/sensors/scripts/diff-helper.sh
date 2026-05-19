#!/usr/bin/env bash
# Diff helper script: compare two files and produce a merge-plan-like result.
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
    echo "Usage:"
    echo "  diff-helper.sh diff <file1> <file2>        generate unified diff"
    echo "  diff-helper.sh describe <file1> <file2>     generate plain-text summary"
    echo "  diff-helper.sh check <file>                 check whether file exists"
    echo "  diff-helper.sh merge-plan <existing> <incoming>  generate structured merge plan (JSON)"
}

# Count added/removed lines in unified diff, excluding header lines
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

# Recommend merge strategy
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

# Build human-readable description
build_description() {
    local existing_path="$1"
    local existing_exists="$2"
    local incoming_path="$3"
    local added="$4"
    local removed="$5"
    local rec="$6"

    if [ "$rec" = "manual_required" ]; then
        if [ "$existing_exists" = "true" ]; then
            echo "Found existing ${existing_path}; file type/format requires manual merge. Merge manually, then use replace or skip."
        else
            echo "No corresponding ${incoming_path} in the target project. Safe to write directly (merge/replace outcomes are equivalent)."
        fi
    elif [ "$added" -eq 0 ] && [ "$removed" -eq 0 ]; then
        echo "No changes needed; file contents are identical."
    elif [ "$existing_exists" = "false" ]; then
        echo "Target project has no corresponding file. New install can complete in full (${added} added lines)."
    elif [ "$removed" -eq 0 ]; then
        echo "Existing ${existing_path} detected. Skill added ${added} lines without directly removing ${removed} lines. Auto-merge can be attempted."
    else
        echo "Existing ${existing_path} detected (${removed} lines will overlap with incoming additions). Please confirm manually before applying."
    fi
}

describe_diff() {
    local f1="$1"
    local f2="$2"

    if [ ! -f "$f1" ]; then
        echo "File not found: $f1"
        return 1
    fi
    if [ ! -f "$f2" ]; then
        echo "File not found: $f2"
        return 1
    fi

    local name1
    local name2
    name1="$(basename "$f1")"
    name2="$(basename "$f2")"

    echo "=== Change description ==="
    echo "File: $name1 → $name2"
    echo ""

    read -r added removed <<< "$(count_diff "$f1" "$f2")"

    if [ "$added" -eq 0 ] && [ "$removed" -eq 0 ]; then
        echo "No content changes."
    else
        echo "Added ${added} lines, removed ${removed} lines."
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
        echo "✓ Exists: $f"
        return 0
    else
        echo "✗ Missing: $f"
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
