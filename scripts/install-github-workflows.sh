#!/usr/bin/env bash
# install-github-workflows.sh — 安装 GitHub workflows, rulesets, scripts
# 用法: install-github-workflows.sh <target-root> [--check|--apply merge|replace|skip]
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
    echo '{"status":"error","error":"usage: install-github-workflows.sh <target-root> [--check|--apply merge|replace|skip]"}' >&2
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

WF_SRC_DIR="$SKILL_DIR/assets/github/workflows"
WF_DST_DIR="$TARGET/.github/workflows"
SCRIPTS_SRC="$SKILL_DIR/assets/github/scripts"
SCRIPTS_DST="$TARGET/.github/scripts"
RULESETS_SRC="$SKILL_DIR/assets/github/rulesets"
RULESETS_DST="$TARGET/.github/rulesets"

# ===================== --check mode =====================
if [ "$MODE" = "check" ]; then
    ITEMS=""
    ANY_CONFLICT="false"
    ERROR_COUNT=0
    NEW_COUNT=0
    EXISTING_COUNT=0

    # Check workflow files
    if [ -d "$WF_SRC_DIR" ]; then
        for wf_src in "$WF_SRC_DIR"/*.yml; do
            [ -f "$wf_src" ] || continue
            wf_name=$(basename "$wf_src")
            wf_dst="$WF_DST_DIR/$wf_name"

            plan_json=$("$DIFF_HELPER" merge-plan "$wf_dst" "$wf_src" 2>/dev/null) || {
                ERROR_COUNT=$((ERROR_COUNT + 1))
                [ -n "$ITEMS" ] && ITEMS+=","
                ITEMS+="{\"file\":\".github/workflows/$wf_name\",\"status\":\"error\",\"error\":\"merge-plan failed\"}"
                continue
            }

            [ -n "$ITEMS" ] && ITEMS+=","
            ITEMS+="{\"file\":\".github/workflows/$wf_name\",$(echo "$plan_json" | sed 's/^{//')"

            if echo "$plan_json" | grep -q '"exists": true'; then
                ANY_CONFLICT="true"
                EXISTING_COUNT=$((EXISTING_COUNT + 1))
            else
                NEW_COUNT=$((NEW_COUNT + 1))
            fi
        done
    fi

    # Check scripts
    if [ -d "$SCRIPTS_SRC" ]; then
        for scr_src in "$SCRIPTS_SRC"/*; do
            [ -f "$scr_src" ] || continue
            scr_name=$(basename "$scr_src")
            scr_dst="$SCRIPTS_DST/$scr_name"

            if [ -f "$scr_dst" ]; then
                ANY_CONFLICT="true"
                EXISTING_COUNT=$((EXISTING_COUNT + 1))
                [ -n "$ITEMS" ] && ITEMS+=","
                ITEMS+="{\"file\":\".github/scripts/$scr_name\",\"status\":\"conflict\",\"existing\":{\"exists\":true},\"incoming\":{\"lines\":$(wc -l < "$scr_src" | tr -d ' ')},\"description_nl\":\"Existing script found. Review before replacing.\"}"
            else
                NEW_COUNT=$((NEW_COUNT + 1))
                [ -n "$ITEMS" ] && ITEMS+=","
                ITEMS+="{\"file\":\".github/scripts/$scr_name\",\"status\":\"clean\",\"existing\":{\"exists\":false},\"incoming\":{\"lines\":$(wc -l < "$scr_src" | tr -d ' ')},\"description_nl\":\"New script ready for install.\"}"
            fi
        done
    fi

    # Check rulesets
    if [ -d "$RULESETS_SRC" ]; then
        for rs_src in "$RULESETS_SRC"/*.json; do
            [ -f "$rs_src" ] || continue
            rs_name=$(basename "$rs_src")
            rs_dst="$RULESETS_DST/$rs_name"

            if [ -f "$rs_dst" ]; then
                ANY_CONFLICT="true"
                EXISTING_COUNT=$((EXISTING_COUNT + 1))
                [ -n "$ITEMS" ] && ITEMS+=","
                ITEMS+="{\"file\":\".github/rulesets/$rs_name\",\"status\":\"conflict\",\"existing\":{\"exists\":true},\"incoming\":{\"lines\":$(wc -l < "$rs_src" | tr -d ' ')},\"description_nl\":\"Existing ruleset found. Review before replacing.\"}"
            else
                NEW_COUNT=$((NEW_COUNT + 1))
                [ -n "$ITEMS" ] && ITEMS+=","
                ITEMS+="{\"file\":\".github/rulesets/$rs_name\",\"status\":\"clean\",\"existing\":{\"exists\":false},\"incoming\":{\"lines\":$(wc -l < "$rs_src" | tr -d ' ')},\"description_nl\":\"New ruleset ready for install.\"}"
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

    if [ "$TOP_STATUS" = "clean" ]; then
        SUMMARY="No existing GitHub workflow files found. ${NEW_COUNT} item(s) ready for clean install."
        DESC_NL="The project has no GitHub workflows, scripts, or rulesets currently installed. All items from the Skill are ready for a clean install with no conflicts."
    elif [ "$TOP_STATUS" = "conflict" ]; then
        SUMMARY="Found ${EXISTING_COUNT} existing item(s), ${NEW_COUNT} new item(s). Review each item's merge plan."
        DESC_NL="Some GitHub workflow files, scripts, or rulesets already exist in the project. Each conflicting item is shown with details. Choose merge (keep both), replace (use Skill version), or skip (keep existing) per item."
    else
        SUMMARY="Errors encountered during check."
        DESC_NL="Errors occurred while checking GitHub workflow files. Please verify Skill assets are intact."
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
        echo '{"status":"ok","action":"skip","detail":"GitHub workflows skipped per user request."}'
        exit 0
    fi

    APPLIED=""
    ERRORS=""

    # Workflows
    if [ -d "$WF_SRC_DIR" ]; then
        mkdir -p "$WF_DST_DIR"
        for wf_src in "$WF_SRC_DIR"/*.yml; do
            [ -f "$wf_src" ] || continue
            wf_name=$(basename "$wf_src")
            wf_dst="$WF_DST_DIR/$wf_name"

            case "$STRATEGY" in
                merge)
                    if [ -f "$wf_dst" ]; then
                        # For YAML files, merge is not trivial; skip existing
                        APPLIED="${APPLIED}(skipped existing) .github/workflows/$wf_name "
                    else
                        cp "$wf_src" "$wf_dst"
                        APPLIED="${APPLIED}.github/workflows/$wf_name "
                    fi
                    ;;
                replace)
                    cp "$wf_src" "$wf_dst"
                    APPLIED="${APPLIED}.github/workflows/$wf_name "
                    ;;
            esac
        done
    fi

    # Scripts
    if [ -d "$SCRIPTS_SRC" ]; then
        mkdir -p "$SCRIPTS_DST"
        for scr_src in "$SCRIPTS_SRC"/*; do
            [ -f "$scr_src" ] || continue
            scr_name=$(basename "$scr_src")
            scr_dst="$SCRIPTS_DST/$scr_name"

            if [ "$STRATEGY" = "merge" ] && [ -f "$scr_dst" ]; then
                APPLIED="${APPLIED}(skipped existing) .github/scripts/$scr_name "
            else
                cp "$scr_src" "$scr_dst"
                APPLIED="${APPLIED}.github/scripts/$scr_name "
            fi
        done
    fi

    # Rulesets
    if [ -d "$RULESETS_SRC" ]; then
        mkdir -p "$RULESETS_DST"
        for rs_src in "$RULESETS_SRC"/*.json; do
            [ -f "$rs_src" ] || continue
            rs_name=$(basename "$rs_src")
            rs_dst="$RULESETS_DST/$rs_name"

            if [ "$STRATEGY" = "merge" ] && [ -f "$rs_dst" ]; then
                APPLIED="${APPLIED}(skipped existing) .github/rulesets/$rs_name "
            else
                cp "$rs_src" "$rs_dst"
                APPLIED="${APPLIED}.github/rulesets/$rs_name "
            fi
        done
    fi

    APPLIED=$(echo "$APPLIED" | xargs 2>/dev/null || true)
    if [ -n "$ERRORS" ]; then
        echo "{\"status\":\"partial\",\"applied\":\"$(json_escape "$APPLIED")\",\"errors\":\"$(json_escape "$ERRORS")\"}"
    else
        echo "{\"status\":\"ok\",\"applied\":\"$(json_escape "$APPLIED")\"}"
    fi
    exit 0
fi

# ===================== default mode (backward compat) =====================
echo "--- 安装 GitHub workflows ---"

mkdir -p "$WF_DST_DIR"

for wf in "$WF_SRC_DIR"/*.yml; do
    if [ -f "$wf" ]; then
        wf_name=$(basename "$wf")
        if [ -f "$WF_DST_DIR/$wf_name" ]; then
            echo "  跳过: $wf_name（已存在）"
        else
            cp "$wf" "$WF_DST_DIR/$wf_name"
            echo "  ✓ $wf_name"
        fi
    fi
done

echo "GitHub workflows 安装完成。"
