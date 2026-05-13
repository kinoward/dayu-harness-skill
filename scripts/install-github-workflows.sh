#!/usr/bin/env bash
# install-github-workflows.sh — 安装 GitHub workflows, rulesets, scripts
# 用法: install-github-workflows.sh <target-root> [--check|--apply merge|replace|skip]
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
    echo '{"status":"error","error":"usage: install-github-workflows.sh <target-root> [--check|--apply merge|replace|skip]","description_nl":"Usage requires target-root and optional strategy."}'
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

append_plan_item() {
    local file="$1"
    local existing="$2"
    local incoming="$3"

    local plan_json
    plan_json=$("$DIFF_HELPER" merge-plan "$existing" "$incoming" 2>/dev/null) || return 1

    local plan_body="${plan_json#\{}"
    [ -n "$ITEMS" ] && ITEMS+=","
    ITEMS+="{\"file\":\"$file\",$plan_body"
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

    # Check workflow files (YAML)
    if [ -d "$WF_SRC_DIR" ]; then
        for wf_src in "$WF_SRC_DIR"/*.yml; do
            [ -f "$wf_src" ] || continue
            wf_name=$(basename "$wf_src")
            wf_dst="$WF_DST_DIR/$wf_name"

            if ! append_plan_item ".github/workflows/$wf_name" "$wf_dst" "$wf_src"; then
                ERROR_COUNT=$((ERROR_COUNT + 1))
                [ -n "$ITEMS" ] && ITEMS+=","
                ITEMS+="{\"file\":\".github/workflows/$wf_name\",\"status\":\"error\",\"strategies\":[\"skip\"],\"description_nl\":\"Unable to compute merge plan for this workflow.\"}"
                continue
            fi

            if [ -f "$wf_dst" ]; then
                ANY_CONFLICT="true"
                EXISTING_COUNT=$((EXISTING_COUNT + 1))
            else
                NEW_COUNT=$((NEW_COUNT + 1))
            fi
        done
    fi

    # Check scripts (cannot safely merge deterministic script wrappers in this step)
    if [ -d "$SCRIPTS_SRC" ]; then
        for scr_src in "$SCRIPTS_SRC"/*; do
            [ -f "$scr_src" ] || continue
            scr_name=$(basename "$scr_src")
            scr_dst="$SCRIPTS_DST/$scr_name"
            if [ -f "$scr_dst" ]; then
                ANY_CONFLICT="true"
                EXISTING_COUNT=$((EXISTING_COUNT + 1))
                [ -n "$ITEMS" ] && ITEMS+=","
                ITEMS+="{\"file\":\".github/scripts/$scr_name\",\"status\":\"manual_required\",\"existing\":{\"exists\":true},\"incoming\":{\"path\":\"$(json_escape "$scr_src")\",\"lines\":$(wc -l < "$scr_src" | tr -d ' ')},\"diff\":{\"added\":0,\"removed\":0},\"recommendation\":\"manual_required\",\"strategies\":[\"replace\",\"skip\"],\"description_nl\":\"Existing script found. Merge is not implemented safely; replace or skip.\"}"
            else
                NEW_COUNT=$((NEW_COUNT + 1))
                [ -n "$ITEMS" ] && ITEMS+=","
                ITEMS+="{\"file\":\".github/scripts/$scr_name\",\"status\":\"clean\",\"existing\":{\"exists\":false},\"incoming\":{\"path\":\"$(json_escape "$scr_src")\",\"lines\":$(wc -l < "$scr_src" | tr -d ' ')},\"diff\":{\"added\":0,\"removed\":0},\"recommendation\":\"merge\",\"strategies\":[\"merge\",\"replace\",\"skip\"],\"description_nl\":\"New workflow helper script ready for install.\"}"
            fi
        done
    fi

    # Check rulesets (JSON)
    if [ -d "$RULESETS_SRC" ]; then
        for rs_src in "$RULESETS_SRC"/*.json; do
            [ -f "$rs_src" ] || continue
            rs_name=$(basename "$rs_src")
            rs_dst="$RULESETS_DST/$rs_name"

            if [ -f "$rs_dst" ]; then
                if ! append_plan_item ".github/rulesets/$rs_name" "$rs_dst" "$rs_src"; then
                    ERROR_COUNT=$((ERROR_COUNT + 1))
                    [ -n "$ITEMS" ] && ITEMS+=","
                    ITEMS+="{\"file\":\".github/rulesets/$rs_name\",\"status\":\"error\",\"strategies\":[\"skip\"],\"description_nl\":\"Unable to compute merge plan for this ruleset.\"}"
                    continue
                fi
                ANY_CONFLICT="true"
                EXISTING_COUNT=$((EXISTING_COUNT + 1))
            else
                if ! append_plan_item ".github/rulesets/$rs_name" "$rs_dst" "$rs_src"; then
                    ERROR_COUNT=$((ERROR_COUNT + 1))
                    [ -n "$ITEMS" ] && ITEMS+=","
                    ITEMS+="{\"file\":\".github/rulesets/$rs_name\",\"status\":\"error\",\"strategies\":[\"skip\"],\"description_nl\":\"Unable to compute merge plan for this ruleset.\"}"
                    continue
                fi
                NEW_COUNT=$((NEW_COUNT + 1))
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
        SUMMARY="No existing GitHub workflow assets found. ${NEW_COUNT} item(s) ready for clean install."
        DESC_NL="The project has no GitHub workflows, scripts, or rulesets currently installed. All items from the Skill are ready for a clean install."
    elif [ "$TOP_STATUS" = "conflict" ]; then
        SUMMARY="Found ${EXISTING_COUNT} existing item(s), ${NEW_COUNT} new item(s). Review merge plan."
        DESC_NL="Some GitHub workflow files, scripts, or rulesets already exist. Existing items use manual merge requirements or safe replacement only."
    else
        SUMMARY="Errors encountered during check."
        DESC_NL="Errors occurred while checking GitHub workflow files. Please verify Skill assets and existing files."
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
        echo '{"status":"ok","action":"skip","detail":"GitHub workflows skipped per user request.","description_nl":"No changes were made because skip was requested."}'
        exit 0
    fi

    # Merge mode is conservative: only copy incoming files that do not already exist.
    if [ "$STRATEGY" = "merge" ]; then
        UNSAFE=false
        # Workflows (YAML) require manual merge; any existing file blocks merge.
        if [ -d "$WF_SRC_DIR" ]; then
            for wf_src in "$WF_SRC_DIR"/*.yml; do
                [ -f "$wf_src" ] || continue
                wf_name=$(basename "$wf_src")
                wf_dst="$WF_DST_DIR/$wf_name"
                if [ -f "$wf_dst" ]; then
                    UNSAFE=true
                    break
                fi
            done
        fi

        # Scripts are not safely merged in this installer.
        if [ -d "$SCRIPTS_SRC" ] && ! $UNSAFE; then
            for scr_src in "$SCRIPTS_SRC"/*; do
                [ -f "$scr_src" ] || continue
                scr_name=$(basename "$scr_src")
                scr_dst="$SCRIPTS_DST/$scr_name"
                if [ -f "$scr_dst" ]; then
                    UNSAFE=true
                    break
                fi
            done
        fi

        # Rulesets JSON should not be auto-merged.
        if [ -d "$RULESETS_SRC" ] && ! $UNSAFE; then
            for rs_src in "$RULESETS_SRC"/*.json; do
                [ -f "$rs_src" ] || continue
                rs_name=$(basename "$rs_src")
                rs_dst="$RULESETS_DST/$rs_name"
                if [ -f "$rs_dst" ]; then
                    UNSAFE=true
                    break
                fi
            done
        fi

        if [ "$UNSAFE" = "true" ]; then
            echo '{"status":"manual_required","action":"merge","detail":"Merge blocked for safety because existing GitHub config files were detected.","description_nl":"Automatic merge is not implemented for existing workflows, scripts, or rulesets. Please use replace for a full overwrite or skip."}'
            exit 0
        fi
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

            if [ "$STRATEGY" = "merge" ] && [ -f "$wf_dst" ]; then
                continue
            fi
            cp "$wf_src" "$wf_dst"
            APPLIED="${APPLIED}.github/workflows/$wf_name "
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
                continue
            fi
            cp "$scr_src" "$scr_dst"
            APPLIED="${APPLIED}.github/scripts/$scr_name "
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
                continue
            fi
            cp "$rs_src" "$rs_dst"
            APPLIED="${APPLIED}.github/rulesets/$rs_name "
        done
    fi

    APPLIED=$(echo "$APPLIED" | xargs 2>/dev/null || true)
    if [ -n "$ERRORS" ]; then
        echo "{\"status\":\"partial\",\"applied\":\"$(json_escape "$APPLIED")\",\"errors\":\"$(json_escape "$ERRORS")\",\"description_nl\":\"Some items failed during apply.\"}"
    else
        echo "{\"status\":\"ok\",\"applied\":\"$(json_escape "$APPLIED")\",\"description_nl\":\"Applied GitHub workflow assets using strategy '$STRATEGY'.\"}"
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
