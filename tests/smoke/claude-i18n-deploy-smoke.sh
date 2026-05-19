#!/usr/bin/env bash
# Manual Claude Code CLI smoke test for zh-CN/en Dayu Harness deployments.
#
# This test talks to Claude Code and therefore depends on local authentication,
# network access, and permission prompts. It is opt-in and is not part of the
# default CI suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK_ROOT="$REPO_ROOT/tests/unit/.tmp"
JSON_MODE=false
KEEP=true

usage() {
    cat <<'EOF'
Usage:
  RUN_CLAUDE_I18N_SMOKE=1 tests/smoke/claude-i18n-deploy-smoke.sh [--json] [--cleanup]

Environment:
  RUN_CLAUDE_I18N_SMOKE=1   required guard for this external Claude CLI smoke test

Behavior:
  - creates two empty temporary projects under tests/unit/.tmp/
  - drives Claude Code CLI with /dayu-harness
  - deploys zh-CN in one project and en in the other
  - keeps Git constraints enabled and GitHub constraints disabled
  - runs deployment validators
  - compares the two deployments with tests/helpers/compare-i18n-deployments.sh
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --json)
            JSON_MODE=true
            shift
            ;;
        --cleanup)
            KEEP=false
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unexpected argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ "${RUN_CLAUDE_I18N_SMOKE:-}" != "1" ]; then
    echo "Set RUN_CLAUDE_I18N_SMOKE=1 to run the Claude CLI smoke test." >&2
    exit 2
fi

if command -v rtk >/dev/null 2>&1; then
    CLAUDE_CMD=(rtk claude)
elif command -v claude >/dev/null 2>&1; then
    CLAUDE_CMD=(claude)
else
    echo "Claude Code CLI is not available." >&2
    exit 2
fi

mkdir -p "$WORK_ROOT"
ZH_DIR="$(mktemp -d "$WORK_ROOT/claude-i18n-zh.XXXXXX")"
EN_DIR="$(mktemp -d "$WORK_ROOT/claude-i18n-en.XXXXXX")"

cleanup() {
    if [ "$KEEP" = false ]; then
        rm -rf "$ZH_DIR" "$EN_DIR"
    fi
}
trap cleanup EXIT

run_claude_deploy() {
    local target_dir="$1"
    local locale="$2"
    local locale_label="$3"
    local session_log="$target_dir/claude-session.log"
    local debug_log="$target_dir/claude-debug.log"
    local prompt

    prompt="$(cat <<EOF
/dayu-harness

请在当前目录执行 Dayu Harness Skill 部署 smoke test。
Please run the Dayu Harness Skill deployment smoke test in the current directory.

约束 / Constraints:
- 目标目录 / target directory: $target_dir
- 部署语言 / deployment locale: $locale_label ($locale)
- 必须实际 apply，不要只 dry-run / Apply the deployment, do not stop at dry-run.
- 保留默认 Git 约束 / Keep default Git constraints enabled.
- 不要启用任何 GitHub 约束 / Do not enable any github.* capability.
- 如需初始化，请使用 rtk git init、rtk npm init -y 和 rtk npm install。
- Use rtk-prefixed shell commands when initialization or install commands are required.
- 完成后运行 validate.sh、audit.sh、check-consistency.sh 的 --json 检查。
- Run validate.sh, audit.sh, and check-consistency.sh with --json after deployment.
EOF
)"

    if [ "$JSON_MODE" = true ]; then
        (
            cd "$target_dir"
            "${CLAUDE_CMD[@]}" \
                --add-dir "$REPO_ROOT" \
                --print \
                --output-format text \
                --permission-mode acceptEdits \
                --allowedTools 'Bash(rtk *),Read,Write,Edit,MultiEdit,LS,Glob,Grep' \
                --debug-file "$debug_log" \
                "$prompt"
        ) > "$session_log" 2>&1
    else
        echo "Running Claude deployment for $locale_label at $target_dir"
        (
            cd "$target_dir"
            "${CLAUDE_CMD[@]}" \
                --add-dir "$REPO_ROOT" \
                --print \
                --output-format text \
                --permission-mode acceptEdits \
                --allowedTools 'Bash(rtk *),Read,Write,Edit,MultiEdit,LS,Glob,Grep' \
                --debug-file "$debug_log" \
                "$prompt"
        ) 2>&1 | tee "$session_log"
    fi
}

run_claude_deploy "$ZH_DIR" "zh-CN" "Chinese"
run_claude_deploy "$EN_DIR" "en" "English"

if [ "$JSON_MODE" = true ]; then
    bash "$REPO_ROOT/tests/helpers/compare-i18n-deployments.sh" --json "$ZH_DIR" "$EN_DIR" |
        jq --arg zh "$ZH_DIR" --arg en "$EN_DIR" '. + {deployments:{zh:$zh,en:$en}}'
else
    echo
    echo "zh-CN deployment: $ZH_DIR"
    echo "English deployment: $EN_DIR"
    bash "$REPO_ROOT/tests/helpers/compare-i18n-deployments.sh" "$ZH_DIR" "$EN_DIR"
fi
