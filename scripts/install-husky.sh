#!/usr/bin/env bash
# install-husky.sh — 安装 husky + git hooks
# 用法: install-husky.sh <target-root> [--check|--apply merge|replace|skip]
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIFF_HELPER="${SKILL_DIR}/templates/docs/harness/sensors/scripts/diff-helper.sh"

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
    echo '{"status":"error","error":"usage: install-husky.sh <target-root> [--check|--apply merge|replace|skip]"}' >&2
    exit 2
fi
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
    echo '{"status":"error","error":"target not found"}' >&2
    exit 2
}

HOOKS_DIR="$TARGET/.husky"
HOOKS=("commit-msg" "pre-commit" "pre-push")

# Helper: escape string for JSON string value
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Helper: merge hook content (append Skill additions after a marker)
merge_hook() {
    local src="$1"
    local dst="$2"
    local marker="# >>> docs-governance skill additions >>>"

    if [ ! -f "$dst" ]; then
        cp "$src" "$dst"
        chmod +x "$dst"
        return 0
    fi

    # If marker already exists, skip (already merged)
    if grep -qF "$marker" "$dst" 2>/dev/null; then
        return 0
    fi

    # Read the incoming file and find content beyond the first few lines (skip shebang)
    local body
    body=$(tail -n +2 "$src" 2>/dev/null || true)
    if [ -n "$body" ]; then
        {
            echo ""
            echo "$marker"
            echo "# The following is added by docs-governance skill."
            echo "# Remove this section to revert to original behavior."
            echo "$body"
            echo "# <<< docs-governance skill additions <<<"
        } >> "$dst"
    fi
}

# ===================== --check mode =====================
if [ "$MODE" = "check" ]; then
    ITEMS=""
    ANY_CONFLICT="false"
    ERROR_COUNT=0
    TOTAL_EXISTING=0
    TOTAL_NEW=0

    if [ -d "$HOOKS_DIR" ]; then
        for hook in "${HOOKS[@]}"; do
            local_existing="$HOOKS_DIR/$hook"
            local_incoming="$SKILL_DIR/assets/husky/$hook"

            if [ ! -f "$local_incoming" ]; then
                ERROR_COUNT=$((ERROR_COUNT + 1))
                [ -n "$ITEMS" ] && ITEMS+=","
                ITEMS+="{\"file\":\".husky/$hook\",\"status\":\"error\",\"strategies\":[\"skip\"],\"description_nl\":\"Skill asset missing: assets/husky/$hook\"}"
                continue
            fi

            plan_json=$("$DIFF_HELPER" merge-plan "$local_existing" "$local_incoming" 2>/dev/null) || {
                ERROR_COUNT=$((ERROR_COUNT + 1))
                [ -n "$ITEMS" ] && ITEMS+=","
                ITEMS+="{\"file\":\".husky/$hook\",\"status\":\"error\",\"strategies\":[\"skip\"],\"description_nl\":\"Unable to compute merge plan for this husky hook.\"}"
                continue
            }

            # Add file field to the plan
            plan_with_file="\"file\":\".husky/$hook\",$(echo "$plan_json" | sed 's/^{//' )"

            [ -n "$ITEMS" ] && ITEMS+=","
            ITEMS+="{${plan_with_file}"

            # Determine if this hook has existing content
            if echo "$plan_json" | grep -q '"exists": true'; then
                ANY_CONFLICT="true"
                TOTAL_EXISTING=$((TOTAL_EXISTING + 1))
            else
                TOTAL_NEW=$((TOTAL_NEW + 1))
            fi
        done
    else
        # No .husky dir at all — all hooks are new
        for hook in "${HOOKS[@]}"; do
            local_incoming="$SKILL_DIR/assets/husky/$hook"
            if [ -f "$local_incoming" ]; then
                lines=$(wc -l < "$local_incoming" | tr -d ' ')
                TOTAL_NEW=$((TOTAL_NEW + 1))
                plan_json=$("$DIFF_HELPER" merge-plan "/nonexistent/.husky/$hook" "$local_incoming" 2>/dev/null) || {
                    plan_json="{\"status\":\"clean\",\"existing\":{\"exists\":false},\"incoming\":{\"path\":\"$local_incoming\",\"lines\":$lines},\"diff\":{\"added\":$lines,\"removed\":0},\"recommendation\":\"merge\",\"strategies\":[\"merge\",\"replace\",\"skip\"],\"description_nl\":\"New hook file not yet present. Merge may write this file directly.\"}"
                }
                [ -n "$ITEMS" ] && ITEMS+=","
                ITEMS+="{\"file\":\".husky/$hook\",$(echo "$plan_json" | sed 's/^{//')"
            fi
        done
    fi

    # Build top-level status
    if [ "$ERROR_COUNT" -gt 0 ]; then
        TOP_STATUS="error"
    elif [ "$ANY_CONFLICT" = "true" ]; then
        TOP_STATUS="conflict"
    else
        TOP_STATUS="clean"
    fi

    # Build summary
    if [ "$TOP_STATUS" = "clean" ]; then
        SUMMARY="No existing .husky hooks found. ${TOTAL_NEW} hook(s) ready for clean install."
    elif [ "$TOP_STATUS" = "conflict" ]; then
        SUMMARY="Found ${TOTAL_EXISTING} existing hook(s), ${TOTAL_NEW} new hook(s). Review each hook's merge plan."
    else
        SUMMARY="Errors encountered during check."
    fi

    # Build description_nl
    if [ "$TOP_STATUS" = "clean" ]; then
        DESC_NL="No husky hooks currently installed. All ${TOTAL_NEW} hooks (commit-msg, pre-commit, pre-push) are ready for a clean install. No conflicts to resolve."
    elif [ "$TOP_STATUS" = "conflict" ]; then
        DESC_NL="Some husky hooks already exist in the project. Each hook with existing content is shown with a merge plan. You can choose 'merge' (append Skill additions), 'replace' (overwrite entirely), or 'skip' (keep existing) per hook."
    else
        DESC_NL="Errors occurred while checking husky hooks. Please verify that all assets are available."
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
        echo '{"status":"ok","action":"skip","detail":"Husky hooks skipped per user request."}'
        exit 0
    fi

    mkdir -p "$HOOKS_DIR"
    APPLIED=""
    ERRORS=""

    for hook in "${HOOKS[@]}"; do
        src="$SKILL_DIR/assets/husky/$hook"
        dst="$HOOKS_DIR/$hook"

        if [ ! -f "$src" ]; then
            ERRORS="${ERRORS}Missing asset: assets/husky/$hook; "
            continue
        fi

        case "$STRATEGY" in
            merge)
                if merge_hook "$src" "$dst"; then
                    APPLIED="${APPLIED}.husky/$hook "
                else
                    ERRORS="${ERRORS}Failed to merge .husky/$hook; "
                fi
                ;;
            replace)
                cp "$src" "$dst"
                chmod +x "$dst"
                APPLIED="${APPLIED}.husky/$hook "
                ;;
        esac

        # Syntax check
        if [ -f "$dst" ] && head -1 "$dst" 2>/dev/null | grep -qE '(sh|bash)'; then
            if ! bash -n "$dst" 2>/dev/null; then
                ERRORS="${ERRORS}bash syntax check failed for .husky/$hook; "
            fi
        fi
    done

    # Output result
    APPLIED=$(echo "$APPLIED" | xargs 2>/dev/null || true)
    ERRORS=$(echo "$ERRORS" | sed 's/; $//' 2>/dev/null || true)

    if [ -n "$ERRORS" ]; then
        echo "{\"status\":\"partial\",\"applied\":\"$(json_escape "$APPLIED")\",\"errors\":\"$(json_escape "$ERRORS")\"}"
    else
        echo "{\"status\":\"ok\",\"applied\":\"$(json_escape "$APPLIED")\"}"
    fi
    exit 0
fi

# ===================== default mode (backward compat) =====================
echo "--- 安装 husky ---"

if [ -d "$HOOKS_DIR" ]; then
    echo "检测到已有 .husky/ 目录"
    echo "警告：已有 husky 配置。使用 --apply merge 可合并，--apply replace 可覆盖。"
    echo "使用 --check 可查看详细差异分析。"
    exit 0
fi

if [ ! -f "$TARGET/package.json" ]; then
    echo "跳过：目标项目无 package.json（非 Node.js 项目）"
    exit 0
fi

if ! grep -q '"husky"' "$TARGET/package.json" 2>/dev/null; then
    echo "提示：请在项目中安装 husky："
    echo "  npm install -D husky"
    echo "  npx husky init"
fi

mkdir -p "$HOOKS_DIR"

for hook in "${HOOKS[@]}"; do
    if [ -f "$SKILL_DIR/assets/husky/$hook" ]; then
        cp "$SKILL_DIR/assets/husky/$hook" "$HOOKS_DIR/$hook"
        chmod +x "$HOOKS_DIR/$hook"
        echo "  ✓ .husky/$hook"
    else
        echo "  ✗ $hook 模板不存在"
    fi
done

echo "husky 安装完成。"
