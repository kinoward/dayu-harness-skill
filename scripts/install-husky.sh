#!/usr/bin/env bash
# install-husky.sh — 安装 husky hook snippets
# 用法: install-husky.sh <target-root> [--check|--apply merge|skip]
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

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
    echo '{"status":"error","error":"usage: install-husky.sh <target-root> [--check|--apply merge|skip]"}' >&2
    exit 2
fi
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
    echo '{"status":"error","error":"target not found"}' >&2
    exit 2
}

HOOKS_DIR="$TARGET/.husky"
CAPABILITY="${DAYU_HARNESS_CAPABILITY:-}"

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

fragment_entries() {
    case "$CAPABILITY" in
        ""|all)
            echo "error|${CAPABILITY:-<unset>}|"
            ;;
        git.commit-format)
            echo "commit-msg|git.commit-format|assets/husky/snippets/commit-format.sh"
            ;;
        quality.node-tooling)
            echo "pre-commit|quality.node-tooling|assets/husky/snippets/quality-node-tooling.sh"
            ;;
        github.branch-protection)
            echo "pre-push|github.branch-protection|assets/husky/snippets/branch-protection.sh"
            ;;
        release.versioning)
            echo "pre-push|release.versioning|assets/husky/snippets/release-versioning.sh"
            ;;
        git.hooks)
            ;;
        *)
            echo "error|$CAPABILITY|"
            ;;
    esac
}

ensure_hook_file() {
    local hook="$1"
    local dst="$HOOKS_DIR/$hook"
    if [ ! -f "$dst" ]; then
        mkdir -p "$HOOKS_DIR"
        {
            echo "#!/usr/bin/env bash"
            echo "# $hook hook managed by dayu-harness snippets"
            if [ "$hook" = "commit-msg" ]; then
                echo 'COMMIT_MSG_FILE="$1"'
            fi
            echo ""
        } > "$dst"
        chmod +x "$dst"
    fi
}

append_fragment() {
    local hook="$1"
    local id="$2"
    local src_rel="$3"
    local src="$SKILL_DIR/$src_rel"
    local dst="$HOOKS_DIR/$hook"
    local marker_start="# >>> dayu-harness:${id} >>>"
    local marker_end="# <<< dayu-harness:${id} <<<"

    [ -f "$src" ] || return 2
    ensure_hook_file "$hook"

    if grep -qF "$marker_start" "$dst" 2>/dev/null; then
        return 0
    fi

    {
        echo ""
        echo "$marker_start"
        echo "# The following snippet is added by dayu-harness."
        echo "# Remove this marked section to revert this capability."
        cat "$src"
        echo "$marker_end"
    } >> "$dst"
}

selected_hooks() {
    fragment_entries | awk -F'|' '$1 != "error" && $1 != "" {print $1}' | sort -u
}

if [ "$MODE" = "check" ]; then
    ITEMS=""
    ANY_CONFLICT="false"
    ERROR_COUNT=0
    TOTAL_EXISTING=0
    TOTAL_NEW=0

    while IFS='|' read -r hook id src_rel; do
        [ -n "$hook" ] || continue
        if [ "$hook" = "error" ]; then
            ERROR_COUNT=$((ERROR_COUNT + 1))
            [ -n "$ITEMS" ] && ITEMS+=","
            ITEMS+="{\"file\":\".husky\",\"capability\":\"$(json_escape "$id")\",\"status\":\"error\",\"recommendation\":\"skip\",\"strategies\":[\"skip\"],\"description_nl\":\"Unknown dayu-harness hook capability: $(json_escape "$id")\"}"
            continue
        fi

        src="$SKILL_DIR/$src_rel"
        if [ ! -f "$src" ]; then
            ERROR_COUNT=$((ERROR_COUNT + 1))
            [ -n "$ITEMS" ] && ITEMS+=","
            ITEMS+="{\"file\":\".husky/$hook\",\"capability\":\"$(json_escape "$id")\",\"status\":\"error\",\"recommendation\":\"skip\",\"strategies\":[\"skip\"],\"description_nl\":\"Skill hook snippet missing: $(json_escape "$src_rel")\"}"
            continue
        fi

        exists=false
        status="clean"
        recommendation="merge"
        description="New hook snippet ready for install."
        if [ -f "$HOOKS_DIR/$hook" ]; then
            exists=true
            ANY_CONFLICT="true"
            TOTAL_EXISTING=$((TOTAL_EXISTING + 1))
            if grep -qF "# >>> dayu-harness:${id} >>>" "$HOOKS_DIR/$hook"; then
                status="clean"
                description="Hook snippet already present."
            else
                status="conflict"
                description="Existing hook found; merge will append only the ${id} snippet."
            fi
        else
            TOTAL_NEW=$((TOTAL_NEW + 1))
        fi

        [ -n "$ITEMS" ] && ITEMS+=","
        ITEMS+="{\"file\":\".husky/$hook\",\"capability\":\"$(json_escape "$id")\",\"status\":\"$status\",\"exists\":$exists,\"recommendation\":\"$recommendation\",\"strategies\":[\"merge\",\"skip\"],\"description_nl\":\"$(json_escape "$description")\"}"
    done < <(fragment_entries)

    if [ "$ERROR_COUNT" -gt 0 ]; then
        TOP_STATUS="error"
    elif [ "$ANY_CONFLICT" = "true" ]; then
        TOP_STATUS="conflict"
    else
        TOP_STATUS="clean"
    fi

    if [ "$TOP_STATUS" = "clean" ]; then
        SUMMARY="${TOTAL_NEW} hook snippet(s) ready for clean install."
        DESC_NL="No conflicting husky hook snippets found for capability ${CAPABILITY}."
    elif [ "$TOP_STATUS" = "conflict" ]; then
        SUMMARY="Found existing hook(s). Review merge plan for capability ${CAPABILITY}."
        DESC_NL="Some husky hooks already exist. Merge appends only the selected dayu-harness snippet and preserves existing content."
    else
        SUMMARY="Errors encountered during hook check."
        DESC_NL="Errors occurred while checking husky hook snippets."
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

if [ "$MODE" = "apply" ]; then
    case "$STRATEGY" in
        merge|skip) ;;
        *)
            echo '{"status":"error","error":"--apply requires strategy: merge or skip"}' >&2
            exit 2
            ;;
    esac

    if [ "$STRATEGY" = "skip" ]; then
        echo '{"status":"ok","action":"skip","detail":"Husky hook snippets skipped per user request.","description_nl":"No hook snippets were installed because skip was requested."}'
        exit 0
    fi

    APPLIED=""
    ERRORS=""

    while IFS='|' read -r hook id src_rel; do
        [ -n "$hook" ] || continue
        if [ "$hook" = "error" ]; then
            ERRORS="${ERRORS}Unknown capability: $id; "
            continue
        fi
        if append_fragment "$hook" "$id" "$src_rel"; then
            APPLIED="${APPLIED}.husky/$hook:${id} "
        else
            ERRORS="${ERRORS}Failed to merge $id into .husky/$hook; "
        fi
    done < <(fragment_entries)

    while IFS= read -r hook; do
        dst="$HOOKS_DIR/$hook"
        if [ -f "$dst" ] && head -1 "$dst" 2>/dev/null | grep -qE '(sh|bash)'; then
            if ! bash -n "$dst" 2>/dev/null; then
                ERRORS="${ERRORS}bash syntax check failed for .husky/$hook; "
            fi
        fi
    done < <(selected_hooks)

    APPLIED=$(echo "$APPLIED" | xargs 2>/dev/null || true)
    ERRORS=$(echo "$ERRORS" | sed 's/; $//' 2>/dev/null || true)

    if [ -n "$ERRORS" ]; then
        echo "{\"status\":\"partial\",\"action\":\"$STRATEGY\",\"applied\":\"$(json_escape "$APPLIED")\",\"errors\":\"$(json_escape "$ERRORS")\",\"description_nl\":\"Some hook snippets failed to install.\"}"
    else
        echo "{\"status\":\"ok\",\"action\":\"$STRATEGY\",\"applied\":\"$(json_escape "$APPLIED")\",\"description_nl\":\"Selected hook snippets installed.\"}"
    fi
    exit 0
fi

echo "--- 安装 husky snippets ---"
echo "提示：请通过 DAYU_HARNESS_CAPABILITY 指定能力，再使用 --check 或 --apply merge。"
"$0" "$TARGET" --check
