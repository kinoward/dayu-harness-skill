#!/usr/bin/env bash
# install-gitignore.sh — 安装/合并 .gitignore
# 用法: install-gitignore.sh <target-root> [--check|--apply merge|replace|skip]
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIFF_HELPER="${SKILL_DIR}/templates/docs/scripts/diff-helper.sh"

# Parse mode
MODE="default"
STRATEGY=""
TARGET=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check) MODE="check"; shift ;;
        --apply) MODE="apply"; STRATEGY="${2:-}"; shift 2 ;;
        *) TARGET="$1"; shift ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo '{"status":"error","error":"usage: install-gitignore.sh <target-root> [--check|--apply merge|replace|skip]"}' >&2
    exit 2
fi
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
    echo '{"status":"error","error":"target not found"}' >&2
    exit 2
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

UNIVERSAL_PATH="$SKILL_DIR/assets/gitignore/universal.gitignore"
NODE_PATH="$SKILL_DIR/assets/gitignore/node.gitignore"
PYTHON_PATH="$SKILL_DIR/assets/gitignore/python.gitignore"
GITIGNORE_PATH="$TARGET/.gitignore"

# Find which language-specific gitignore templates are relevant
# (based on project files like package.json, requirements.txt, etc.)
detect_project_types() {
    local types="universal"
    if [ -f "$TARGET/package.json" ]; then
        types="$types node"
    fi
    if [ -f "$TARGET/requirements.txt" ] || [ -f "$TARGET/setup.py" ] || [ -f "$TARGET/pyproject.toml" ]; then
        types="$types python"
    fi
    echo "$types"
}

# Get missing patterns from template compared to existing .gitignore
find_missing_patterns() {
    local template="$1"
    local existing="$2"
    local missing=""

    if [ ! -f "$existing" ]; then
        # All patterns are missing
        cat "$template"
        return
    fi

    while IFS= read -r line; do
        # Skip empty lines and comment-only lines for comparison
        # But still include them as missing if they provide structure
        if ! grep -qF "$line" "$existing" 2>/dev/null && [ -n "$line" ]; then
            echo "$line"
        fi
    done < "$template"
}

# ===================== --check mode =====================
if [ "$MODE" = "check" ]; then
    PROJECT_TYPES=$(detect_project_types)
    ITEMS=""
    ANY_CONFLICT="false"
    TOTAL_MISSING=0
    ERROR_COUNT=0

    for type in $PROJECT_TYPES; do
        case "$type" in
            universal) template="$UNIVERSAL_PATH" ;;
            node) template="$NODE_PATH" ;;
            python) template="$PYTHON_PATH" ;;
            *) continue ;;
        esac

        if [ ! -f "$template" ]; then
            ERROR_COUNT=$((ERROR_COUNT + 1))
            [ -n "$ITEMS" ] && ITEMS+=","
            ITEMS+="{\"type\":\"$type\",\"status\":\"error\",\"error\":\"Template not found\"}"
            continue
        fi

        if [ -f "$GITIGNORE_PATH" ]; then
            ANY_CONFLICT="true"
            # Count missing patterns
            missing_count=$(find_missing_patterns "$template" "$GITIGNORE_PATH" | wc -l | tr -d ' ')
            TOTAL_MISSING=$((TOTAL_MISSING + missing_count))

            # Get a sample of missing patterns (first 10)
            missing_sample=$(find_missing_patterns "$template" "$GITIGNORE_PATH" | head -10 | while IFS= read -r p; do printf '%s, ' "$p"; done | sed 's/, $//')
            missing_sample_json=$(json_escape "$missing_sample")

            [ -n "$ITEMS" ] && ITEMS+=","
            ITEMS+="{\"type\":\"$type\",\"status\":\"conflict\",\"missing_count\":$missing_count,\"missing_sample\":\"$missing_sample_json\",\"description_nl\":\"$missing_count pattern(s) from $type.gitignore are missing from existing .gitignore.\"}"
        else
            # No existing .gitignore
            lines=$(wc -l < "$template" | tr -d ' ')
            [ -n "$ITEMS" ] && ITEMS+=","
            ITEMS+="{\"type\":\"$type\",\"status\":\"clean\",\"incoming_lines\":$lines,\"description_nl\":\"No existing .gitignore. All $lines patterns from $type.gitignore ready for install.\"}"
        fi
    done

    # Build top-level status
    if [ "$ERROR_COUNT" -gt 0 ]; then
        TOP_STATUS="error"
    elif [ "$ANY_CONFLICT" = "true" ]; then
        TOP_STATUS="conflict"
    else
        TOP_STATUS="clean"
    fi

    if [ "$TOP_STATUS" = "clean" ]; then
        SUMMARY="No existing .gitignore found. Ready for clean install."
        DESC_NL="The project has no .gitignore file. The Skill will create one using the universal template"
        if echo "$PROJECT_TYPES" | grep -q "node"; then
            DESC_NL="$DESC_NL plus Node.js-specific patterns"
        fi
        if echo "$PROJECT_TYPES" | grep -q "python"; then
            DESC_NL="$DESC_NL plus Python-specific patterns"
        fi
        DESC_NL="$DESC_NL."
    elif [ "$TOP_STATUS" = "conflict" ]; then
        SUMMARY="Existing .gitignore found with $TOTAL_MISSING missing pattern(s) across templates. Use 'merge' to append missing patterns."
        DESC_NL="The project already has a .gitignore file, but $TOTAL_MISSING pattern(s) from the Skill's templates are missing. You can merge (append missing patterns without duplicating), replace (overwrite entirely), or skip (keep existing)."
    else
        SUMMARY="Errors encountered during check."
        DESC_NL="Errors occurred while checking .gitignore templates."
    fi

    cat <<JSONEOF
{
  "status": "$TOP_STATUS",
  "items": [$ITEMS],
  "summary": "$(json_escape "$SUMMARY")",
  "description_nl": "$(json_escape "$DESC_NL")"
}
JSONEOF
    exit 0
fi

# ===================== --apply mode =====================
if [ "$MODE" = "apply" ]; then
    case "$STRATEGY" in
        merge|replace|skip) ;;
        *)
            echo '{"status":"error","error":"--apply requires strategy: merge, replace, or skip"}' >&2
            exit 2
            ;;
    esac

    if [ "$STRATEGY" = "skip" ]; then
        echo '{"status":"ok","action":"skip","detail":".gitignore skipped per user request."}'
        exit 0
    fi

    PROJECT_TYPES=$(detect_project_types)

    case "$STRATEGY" in
        replace)
            # Build combined gitignore from all relevant templates
            {
                for type in $PROJECT_TYPES; do
                    case "$type" in
                        universal) template="$UNIVERSAL_PATH" ;;
                        node) template="$NODE_PATH" ;;
                        python) template="$PYTHON_PATH" ;;
                        *) continue ;;
                    esac
                    if [ -f "$template" ]; then
                        echo ""
                        echo "# === $type.gitignore ==="
                        cat "$template"
                    fi
                done
            } > "$GITIGNORE_PATH"
            echo "{\"status\":\"ok\",\"action\":\"replace\",\"detail\":\".gitignore written with patterns: $PROJECT_TYPES.\"}"
            ;;
        merge)
            if [ ! -f "$GITIGNORE_PATH" ]; then
                # No existing file — just create from templates
                {
                    for type in $PROJECT_TYPES; do
                        case "$type" in
                            universal) template="$UNIVERSAL_PATH" ;;
                            node) template="$NODE_PATH" ;;
                            python) template="$PYTHON_PATH" ;;
                            *) continue ;;
                        esac
                        if [ -f "$template" ]; then
                            echo ""
                            echo "# === $type.gitignore ==="
                            cat "$template"
                        fi
                    done
                } > "$GITIGNORE_PATH"
                echo "{\"status\":\"ok\",\"action\":\"merge\",\"detail\":\".gitignore created from templates: $PROJECT_TYPES.\"}"
            else
                # Append missing patterns
                added_count=0
                for type in $PROJECT_TYPES; do
                    case "$type" in
                        universal) template="$UNIVERSAL_PATH" ;;
                        node) template="$NODE_PATH" ;;
                        python) template="$PYTHON_PATH" ;;
                        *) continue ;;
                    esac
                    if [ -f "$template" ]; then
                        {
                            echo ""
                            echo "# === Added by docs-governance: $type.gitignore ==="
                            find_missing_patterns "$template" "$GITIGNORE_PATH"
                        } >> "$GITIGNORE_PATH"
                        added_count=$((added_count + $(find_missing_patterns "$template" "$GITIGNORE_PATH" | wc -l | tr -d ' ')))
                    fi
                done
                echo "{\"status\":\"ok\",\"action\":\"merge\",\"detail\":\"Appended $added_count missing pattern(s) to .gitignore.\"}"
            fi
            ;;
    esac
    exit 0
fi

# ===================== default mode (backward compat) =====================
echo "--- 安装 .gitignore (universal) ---"

if [ -f "$GITIGNORE_PATH" ]; then
    echo "检测到已有 .gitignore"
    echo "--- 已有内容 (头20行) ---"
    head -20 "$GITIGNORE_PATH"
    echo "--- 建议新增 (来自 universal.gitignore) ---"
    find_missing_patterns "$UNIVERSAL_PATH" "$GITIGNORE_PATH"
    echo ""
    echo "使用 --apply merge 可自动追加缺失的 patterns，--check 可查看详细分析。"
    exit 0
fi

cp "$UNIVERSAL_PATH" "$GITIGNORE_PATH"
echo "  ✓ .gitignore"
