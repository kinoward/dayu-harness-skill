#!/usr/bin/env bash
# install-commitlint.sh — 安装 commitlint 配置
# 用法: install-commitlint.sh <target-root> [--check|--apply merge|replace|skip]
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
    echo '{"status":"error","error":"usage: install-commitlint.sh <target-root> [--check|--apply merge|replace|skip]","description_nl":"Usage requires target root path."}' >&2
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

CONFIG_FILE="commitlint.config.cjs"
EXISTING_PATH="$TARGET/$CONFIG_FILE"
INCOMING_PATH="$SKILL_DIR/assets/commitlint/$CONFIG_FILE"

# ===================== --check mode =====================
if [ "$MODE" = "check" ]; then
    if [ ! -f "$INCOMING_PATH" ]; then
        echo '{"status":"error","error":"Skill asset not found: assets/commitlint/commitlint.config.cjs","items":[],"summary":"Skill asset missing.","description_nl":"The commitlint config template is missing from the Skill assets."}'
        exit 0
    fi

    if [ -f "$EXISTING_PATH" ]; then
        PLAN_JSON=$("$DIFF_HELPER" merge-plan "$EXISTING_PATH" "$INCOMING_PATH" 2>/dev/null) || {
            echo '{"status":"error","error":"merge-plan failed","items":[],"summary":"Error running diff analysis.","description_nl":"Failed to compare existing and incoming commitlint config files."}'
            exit 0
        }
        ITEMS="{\"file\":\"$CONFIG_FILE\",$(echo "$PLAN_JSON" | sed 's/^{//')"
        TOP_STATUS="manual_required"
        if echo "$PLAN_JSON" | grep -q '"status":"manual_required"'; then
            TOP_STATUS="manual_required"
        else
            TOP_STATUS="conflict"
        fi
        SUMMARY="Existing commitlint.config.cjs found: review required."
        DESC_NL="The project already has commitlint config. Complex config formats are not automatically merged."
    else
        PLAN_JSON=$("$DIFF_HELPER" merge-plan "/nonexistent/$CONFIG_FILE" "$INCOMING_PATH" 2>/dev/null) || {
            PLAN_JSON='{"status":"clean","existing":{"path":"/nonexistent/'"$CONFIG_FILE"'","exists":false,"lines":0},"incoming":{"path":"'"$INCOMING_PATH"'","lines":'$(wc -l < "$INCOMING_PATH" | tr -d ' ')'},"diff":{"added":0,"removed":0},"recommendation":"merge","strategies":["merge","replace","skip"],"description_nl":"No commitlint config found. Ready for clean install."}'
        }
        ITEMS="{\"file\":\"$CONFIG_FILE\",$(echo "$PLAN_JSON" | sed 's/^{//')"
        TOP_STATUS="clean"
        SUMMARY="No existing commitlint.config.cjs. Ready for clean install."
        DESC_NL="No commitlint configuration found in the project. The Skill can install a standard commitlint.config.cjs with conventional commit rules."
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
        echo '{"status":"ok","action":"skip","detail":"commitlint config skipped per user request.","description_nl":"No changes were made because skip was requested."}'
        exit 0
    fi

    if [ ! -f "$INCOMING_PATH" ]; then
        echo '{"status":"error","error":"Skill asset not found: assets/commitlint/commitlint.config.cjs","description_nl":"Skill asset file is missing."}'
        exit 1
    fi

    case "$STRATEGY" in
        merge)
            if [ -f "$EXISTING_PATH" ]; then
                echo '{"status":"manual_required","action":"merge","detail":"commitlint.config.cjs already exists. Automatic merge is unsafe for CJS configs.","description_nl":"A commitlint configuration exists. Use replace to overwrite or skip to keep existing."}'
                exit 0
            fi
            cp "$INCOMING_PATH" "$EXISTING_PATH"
            echo '{"status":"ok","action":"merge","detail":"commitlint.config.cjs created (no existing file to merge).","description_nl":"No existing commitlint config found, so merge copied the Skill template."}'
            ;;
        replace)
            cp "$INCOMING_PATH" "$EXISTING_PATH"
            echo '{"status":"ok","action":"replace","detail":"commitlint.config.cjs written.","description_nl":"commitlint configuration was replaced by the Skill template."}'
            ;;
    esac
    exit 0
fi

# ===================== default mode (backward compat) =====================
echo "--- 安装 commitlint ---"

if [ -f "$EXISTING_PATH" ]; then
    echo "检测到已有 commitlint.config.cjs"
    echo "跳过安装。使用 --apply merge|replace 可处理已有配置，--check 可查看差异。"
    exit 0
fi

if [ ! -f "$TARGET/package.json" ]; then
    echo "跳过：目标项目无 package.json"
    exit 0
fi

cp "$INCOMING_PATH" "$EXISTING_PATH"
echo "  ✓ commitlint.config.cjs"

echo "提示：请安装 commitlint 依赖："
echo "  npm install -D @commitlint/config-conventional @commitlint/cli"
