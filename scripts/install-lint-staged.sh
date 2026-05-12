#!/usr/bin/env bash
# install-lint-staged.sh — 安装 lint-staged 配置
# 用法: install-lint-staged.sh <target-root> [--check|--apply merge|replace|skip]
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
    echo '{"status":"error","error":"usage: install-lint-staged.sh <target-root> [--check|--apply merge|replace|skip]"}' >&2
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

INCOMING_PATH="$SKILL_DIR/assets/lint-staged/.lintstagedrc.json"
LINTSTAGED_CANDIDATES=(".lintstagedrc.json" ".lintstagedrc.js" ".lintstagedrc")

# Find existing lint-staged config
find_existing() {
    for f in "${LINTSTAGED_CANDIDATES[@]}"; do
        if [ -f "$TARGET/$f" ]; then
            echo "$f"
            return 0
        fi
    done

    # Also check package.json for lint-staged key
    if [ -f "$TARGET/package.json" ]; then
        if grep -q '"lint-staged"' "$TARGET/package.json" 2>/dev/null; then
            echo "package.json (lint-staged key)"
            return 0
        fi
    fi

    echo ""
    return 1
}

# ===================== --check mode =====================
if [ "$MODE" = "check" ]; then
    if [ ! -f "$INCOMING_PATH" ]; then
        echo '{"status":"error","error":"Skill asset not found: assets/lint-staged/.lintstagedrc.json","items":[],"summary":"Skill asset missing.","description_nl":"The lint-staged config template is missing from the Skill assets."}'
        exit 0
    fi

    EXISTING_FILE=$(find_existing) || true

    if [ -n "$EXISTING_FILE" ]; then
        # If config is in package.json, we can't easily diff it
        if echo "$EXISTING_FILE" | grep -q "package.json"; then
            cat <<JSONEOF
{
  "status": "conflict",
  "items": [{"file":"package.json","location":"lint-staged key","status":"conflict","existing":{"exists":true},"incoming":{"lines":$(wc -l < "$INCOMING_PATH" | tr -d ' ')","path":"$INCOMING_PATH"},"description_nl":"lint-staged config found in package.json. The Skill provides .lintstagedrc.json as a separate file. Manual review required."}],
  "summary": "Existing lint-staged config found in package.json. Manual review required.",
  "description_nl": "The project has lint-staged configuration inside package.json. The Skill provides a standalone .lintstagedrc.json file. You may want to extract the config from package.json into the standalone file, or skip."
}
JSONEOF
        else
            EXISTING_FULL="$TARGET/$EXISTING_FILE"
            plan_json=$("$DIFF_HELPER" merge-plan "$EXISTING_FULL" "$INCOMING_PATH" 2>/dev/null) || {
                echo '{"status":"error","error":"merge-plan failed","items":[],"summary":"Error running diff analysis.","description_nl":"Failed to compare existing and incoming lint-staged config files."}'
                exit 0
            }

            cat <<JSONEOF
{
  "status": "conflict",
  "items": [{"file":"$EXISTING_FILE","existing_also_found_at":"$EXISTING_FILE",$(echo "$plan_json" | sed 's/^{//')],
  "summary": "Existing lint-staged config found: $EXISTING_FILE. Review merge plan.",
  "description_nl": "The project already has a lint-staged configuration file ($EXISTING_FILE). The Skill provides .lintstagedrc.json with pre-commit formatting and linting commands. You can merge, replace, or skip."
}
JSONEOF
        fi
    else
        plan_json=$("$DIFF_HELPER" merge-plan "/nonexistent/.lintstagedrc.json" "$INCOMING_PATH" 2>/dev/null) || {
            plan_json="{\"status\":\"clean\",\"existing\":{\"exists\":false},\"incoming\":{\"lines\":$(wc -l < "$INCOMING_PATH" | tr -d ' ')},\"description_nl\":\"No lint-staged config found. Ready for clean install.\"}"
        }
        cat <<JSONEOF
{
  "status": "clean",
  "items": [{"file":".lintstagedrc.json",$(echo "$plan_json" | sed 's/^{//')],
  "summary": "No existing lint-staged config found. Ready for clean install.",
  "description_nl": "No lint-staged configuration found in the project. The Skill can install .lintstagedrc.json with pre-commit formatting and linting commands."
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
        echo '{"status":"ok","action":"skip","detail":"lint-staged config skipped per user request."}'
        exit 0
    fi

    if [ ! -f "$INCOMING_PATH" ]; then
        echo '{"status":"error","error":"Skill asset not found: assets/lint-staged/.lintstagedrc.json"}'
        exit 1
    fi

    DST_PATH="$TARGET/.lintstagedrc.json"

    case "$STRATEGY" in
        merge)
            if [ -f "$DST_PATH" ]; then
                echo '{"status":"ok","action":"merge","detail":".lintstagedrc.json already exists — merge not implemented for JSON configs. Existing file preserved."}'
            else
                cp "$INCOMING_PATH" "$DST_PATH"
                echo '{"status":"ok","action":"merge","detail":".lintstagedrc.json created (no existing file to merge)."}'
            fi
            ;;
        replace)
            cp "$INCOMING_PATH" "$DST_PATH"
            echo '{"status":"ok","action":"replace","detail":".lintstagedrc.json written."}'
            ;;
    esac
    exit 0
fi

# ===================== default mode (backward compat) =====================
echo "--- 安装 lint-staged ---"

EXISTING_FILE=$(find_existing) || true

if [ -n "$EXISTING_FILE" ]; then
    echo "检测到已有 lint-staged 配置: $EXISTING_FILE"
    echo "跳过安装。使用 --apply merge|replace 可处理已有配置，--check 可查看差异。"
    exit 0
fi

if [ ! -f "$TARGET/package.json" ]; then
    echo "跳过：目标项目无 package.json"
    exit 0
fi

cp "$INCOMING_PATH" "$TARGET/.lintstagedrc.json"
echo "  ✓ .lintstagedrc.json"

echo "提示：请安装 lint-staged："
echo "  npm install -D lint-staged"
