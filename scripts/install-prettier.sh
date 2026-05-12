#!/usr/bin/env bash
# install-prettier.sh — 安装 Prettier 配置
# 用法: install-prettier.sh <target-root> [--check|--apply merge|replace|skip]
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
    echo '{"status":"error","error":"usage: install-prettier.sh <target-root> [--check|--apply merge|replace|skip]"}' >&2
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

INCOMING_PATH="$SKILL_DIR/assets/prettier/.prettierrc"
PRETTIER_CANDIDATES=(".prettierrc" ".prettierrc.json" ".prettierrc.js" "prettier.config.js")

# Find existing prettier config
find_existing() {
    for f in "${PRETTIER_CANDIDATES[@]}"; do
        if [ -f "$TARGET/$f" ]; then
            echo "$f"
            return 0
        fi
    done
    echo ""
    return 1
}

# ===================== --check mode =====================
if [ "$MODE" = "check" ]; then
    if [ ! -f "$INCOMING_PATH" ]; then
        echo '{"status":"error","error":"Skill asset not found: assets/prettier/.prettierrc","items":[],"summary":"Skill asset missing.","description_nl":"The Prettier config template is missing from the Skill assets."}'
        exit 0
    fi

    EXISTING_FILE=$(find_existing) || true

    if [ -n "$EXISTING_FILE" ]; then
        EXISTING_FULL="$TARGET/$EXISTING_FILE"
        plan_json=$("$DIFF_HELPER" merge-plan "$EXISTING_FULL" "$INCOMING_PATH" 2>/dev/null) || {
            echo '{"status":"error","error":"merge-plan failed","items":[],"summary":"Error running diff analysis.","description_nl":"Failed to compare existing and incoming Prettier config files."}'
            exit 0
        }

        cat <<JSONEOF
{
  "status": "conflict",
  "items": [{"file":"$EXISTING_FILE","existing_also_found_at":"$EXISTING_FILE",$(echo "$plan_json" | sed 's/^{//')],
  "summary": "Existing Prettier config found: $EXISTING_FILE. Review merge plan.",
  "description_nl": "The project already has a Prettier configuration file ($EXISTING_FILE). The Skill provides a .prettierrc with standard formatting options. You can merge, replace, or skip."
}
JSONEOF
    else
        plan_json=$("$DIFF_HELPER" merge-plan "/nonexistent/.prettierrc" "$INCOMING_PATH" 2>/dev/null) || {
            plan_json="{\"status\":\"clean\",\"existing\":{\"exists\":false},\"incoming\":{\"lines\":$(wc -l < "$INCOMING_PATH" | tr -d ' ')},\"description_nl\":\"No Prettier config found. Ready for clean install.\"}"
        }
        cat <<JSONEOF
{
  "status": "clean",
  "items": [{"file":".prettierrc",$(echo "$plan_json" | sed 's/^{//')],
  "summary": "No existing Prettier config found. Ready for clean install.",
  "description_nl": "No Prettier configuration found in the project. The Skill can install .prettierrc with standard formatting options."
}
JSONEOF
    fi
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
        echo '{"status":"ok","action":"skip","detail":"Prettier config skipped per user request."}'
        exit 0
    fi

    if [ ! -f "$INCOMING_PATH" ]; then
        echo '{"status":"error","error":"Skill asset not found: assets/prettier/.prettierrc"}'
        exit 1
    fi

    DST_PATH="$TARGET/.prettierrc"

    case "$STRATEGY" in
        merge)
            if [ -f "$DST_PATH" ]; then
                echo '{"status":"ok","action":"merge","detail":".prettierrc already exists — merge not implemented for JSON configs. Existing file preserved."}'
            else
                cp "$INCOMING_PATH" "$DST_PATH"
                echo '{"status":"ok","action":"merge","detail":".prettierrc created (no existing file to merge)."}'
            fi
            ;;
        replace)
            cp "$INCOMING_PATH" "$DST_PATH"
            echo '{"status":"ok","action":"replace","detail":".prettierrc written."}'
            ;;
    esac
    exit 0
fi

# ===================== default mode (backward compat) =====================
echo "--- 安装 Prettier ---"

EXISTING_FILE=$(find_existing) || true

if [ -n "$EXISTING_FILE" ]; then
    echo "检测到已有 Prettier 配置: $EXISTING_FILE"
    echo "跳过安装。使用 --apply merge|replace 可处理已有配置，--check 可查看差异。"
    exit 0
fi

if [ ! -f "$TARGET/package.json" ]; then
    echo "跳过：目标项目无 package.json"
    exit 0
fi

cp "$INCOMING_PATH" "$TARGET/.prettierrc"
echo "  ✓ .prettierrc"

echo "提示：请安装 Prettier："
echo "  npm install -D prettier"
