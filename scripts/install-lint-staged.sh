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
    echo '{"status":"error","error":"usage: install-lint-staged.sh <target-root> [--check|--apply merge|replace|skip]","description_nl":"Usage requires target-root and optional strategy."}' >&2
    exit 2
fi
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
    echo '{"status":"error","error":"target not found","description_nl":"Unable to resolve target path."}'
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
    ITEMS=""
    TOP_STATUS="clean"

    if [ -n "$EXISTING_FILE" ]; then
        if echo "$EXISTING_FILE" | grep -q "package.json"; then
            ITEMS="{\"file\":\"package.json\",\"location\":\"lint-staged key\",\"status\":\"manual_required\",\"existing\":{\"path\":\"package.json\",\"exists\":true},\"incoming\":{\"path\":\".lintstagedrc.json\",\"lines\":$(wc -l < "$INCOMING_PATH" | tr -d ' ')},\"diff\":{\"added\":0,\"removed\":0},\"recommendation\":\"manual_required\",\"strategies\":[\"replace\",\"skip\"],\"description_nl\":\"lint-staged 配置位于 package.json，建议手动迁移到独立配置文件后再使用 replace。\"}"
            TOP_STATUS="manual_required"
        else
            EXISTING_FULL="$TARGET/$EXISTING_FILE"
            PLAN_JSON=$("$DIFF_HELPER" merge-plan "$EXISTING_FULL" "$INCOMING_PATH" 2>/dev/null) || {
                echo '{"status":"error","error":"merge-plan failed","items":[],"summary":"Error running diff analysis.","description_nl":"Failed to compare existing and incoming lint-staged config files."}'
                exit 0
            }
            ITEMS="{\"file\":\"$EXISTING_FILE\",$(echo "$PLAN_JSON" | sed 's/^{//')"
            if echo "$PLAN_JSON" | grep -q '"recommendation":"manual_required"'; then
                TOP_STATUS="manual_required"
            else
                TOP_STATUS="conflict"
            fi
        fi
        SUMMARY="Existing lint-staged config found: $EXISTING_FILE. Review merge plan."
        DESC_NL="The project already has a lint-staged configuration. The Skill provides a standalone .lintstagedrc.json and only replace/skip are allowed for existing complex configs."
        if [ "$TOP_STATUS" = "conflict" ]; then
            DESC_NL="The project already has a lint-staged configuration. You can replace it with the Skill version or skip for now."
        fi
    else
        PLAN_JSON=$("$DIFF_HELPER" merge-plan "/nonexistent/.lintstagedrc.json" "$INCOMING_PATH" 2>/dev/null) || PLAN_JSON='{"status":"clean","existing":{"path":"/nonexistent/.lintstagedrc.json","exists":false,"lines":0},"incoming":{"path":"'"$INCOMING_PATH"'","lines":'$(wc -l < "$INCOMING_PATH" | tr -d ' ')'},"diff":{"added":0,"removed":0},"recommendation":"merge","strategies":["merge","replace","skip"],"description_nl":"No lint-staged config found. Ready for clean install."}'
        ITEMS="{\"file\":\".lintstagedrc.json\",$(echo "$PLAN_JSON" | sed 's/^{//')"
        SUMMARY="No existing lint-staged config found. Ready for clean install."
        DESC_NL="No lint-staged configuration found in the project. The Skill can install .lintstagedrc.json with pre-commit formatting and linting commands."
        TOP_STATUS="clean"
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
            echo '{"status":"error","error":"--apply requires strategy: merge, replace, or skip","description_nl":"Choose one of merge, replace, or skip."}' >&2
            exit 2
            ;;
    esac

    if [ "$STRATEGY" = "skip" ]; then
        echo '{"status":"ok","action":"skip","detail":"lint-staged config skipped per user request.","description_nl":"No changes were made because skip was requested."}'
        exit 0
    fi

    if [ ! -f "$INCOMING_PATH" ]; then
        echo '{"status":"error","error":"Skill asset not found: assets/lint-staged/.lintstagedrc.json","description_nl":"Skill asset file is missing."}'
        exit 1
    fi

    EXISTING_FILE=$(find_existing) || true
    DST_PATH="$TARGET/.lintstagedrc.json"

    case "$STRATEGY" in
        merge)
            if [ -n "$EXISTING_FILE" ]; then
                echo '{"status":"manual_required","action":"merge","detail":"lint-staged configuration already exists in a complex/unsupported format. Merge is not safe; use replace or skip.","description_nl":"An existing lint-staged configuration was detected. Automatic merge is unsafe, so the request was blocked."}'
                exit 0
            fi
            cp "$INCOMING_PATH" "$DST_PATH"
            echo '{"status":"ok","action":"merge","detail":"Created .lintstagedrc.json (clean install).","description_nl":"No existing lint-staged config found, so merge copied the Skill template."}'
            ;;
        replace)
            cp "$INCOMING_PATH" "$DST_PATH"
            echo '{"status":"ok","action":"replace","detail":".lintstagedrc.json written.","description_nl":"Existing or missing lint-staged configuration was replaced with the Skill template."}'
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
