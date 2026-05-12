#!/usr/bin/env bash
# install-commitlint.sh — 安装 commitlint 配置
# 用法: install-commitlint.sh <target-root> [--check|--apply merge|replace|skip]
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
    echo '{"status":"error","error":"usage: install-commitlint.sh <target-root> [--check|--apply merge|replace|skip]"}' >&2
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

CONFIG_FILE="commitlint.config.cjs"
EXISTING_PATH="$TARGET/$CONFIG_FILE"
INCOMING_PATH="$SKILL_DIR/assets/commitlint/$CONFIG_FILE"

# ===================== --check mode =====================
if [ "$MODE" = "check" ]; then
    if [ ! -f "$INCOMING_PATH" ]; then
        echo '{"status":"error","error":"Skill asset not found: assets/commitlint/commitlint.config.cjs","items":[],"summary":"Skill asset missing.","description_nl":"The commitlint config template is missing from the Skill assets."}'
        exit 0
    fi

    plan_json=$("$DIFF_HELPER" merge-plan "$EXISTING_PATH" "$INCOMING_PATH" 2>/dev/null) || {
        echo '{"status":"error","error":"merge-plan failed","items":[],"summary":"Error running diff analysis.","description_nl":"Failed to compare existing and incoming commitlint config files."}'
        exit 0
    }

    plan_with_file="\"file\":\"$CONFIG_FILE\",$(echo "$plan_json" | sed 's/^{//' )"
    item="{$plan_with_file"

    if echo "$plan_json" | grep -q '"exists": true'; then
        TOP_STATUS="conflict"
        SUMMARY="Existing commitlint.config.cjs found. Review merge plan."
        DESC_NL="The project already has a commitlint configuration. The Skill provides an alternative configuration with potentially different rules. You can merge (combine both), replace (use Skill version), or skip (keep existing)."
    else
        TOP_STATUS="clean"
        SUMMARY="No existing commitlint.config.cjs. Ready for clean install."
        DESC_NL="No commitlint configuration found in the project. The Skill can install a standard commitlint.config.cjs with conventional commit rules."
    fi

    cat <<JSONEOF
{
  "status": "$TOP_STATUS",
  "items": [$item],
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
        echo '{"status":"ok","action":"skip","detail":"commitlint config skipped per user request."}'
        exit 0
    fi

    if [ ! -f "$INCOMING_PATH" ]; then
        echo '{"status":"error","error":"Skill asset not found: assets/commitlint/commitlint.config.cjs"}'
        exit 1
    fi

    case "$STRATEGY" in
        merge)
            if [ -f "$EXISTING_PATH" ]; then
                echo '{"status":"ok","action":"merge","detail":"commitlint.config.cjs already exists — merge not implemented (manual merge recommended for JS configs). Existing file preserved."}'
            else
                cp "$INCOMING_PATH" "$EXISTING_PATH"
                echo '{"status":"ok","action":"merge","detail":"commitlint.config.cjs created (no existing file to merge)."}'
            fi
            ;;
        replace)
            cp "$INCOMING_PATH" "$EXISTING_PATH"
            echo '{"status":"ok","action":"replace","detail":"commitlint.config.cjs written."}'
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
