#!/usr/bin/env bash
# ensure-environment.sh — 检查并准备 大禹治库 Skill 运行/部署后的必需环境
# 用法: ensure-environment.sh <target-root> [--check|--apply] --capabilities "id,id"
set -euo pipefail

MODE="check"
TARGET=""
CAPABILITIES_RAW=""
SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
[ "$SCRIPT_DIR" = "${BASH_SOURCE[0]}" ] && SCRIPT_DIR="."
SCRIPT_DIR="$(cd "$SCRIPT_DIR" && pwd)"
MANIFEST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/capabilities"
OUTPUT_BASE="$(pwd)"

while [ $# -gt 0 ]; do
    case "$1" in
        --check)
            MODE="check"
            shift
            ;;
        --apply)
            MODE="apply"
            shift
            ;;
        --capabilities)
            CAPABILITIES_RAW="${2:-}"
            shift 2
            ;;
        --help|-h)
            echo "usage: ensure-environment.sh <target-root> [--check|--apply] --capabilities \"id,id\""
            exit 0
            ;;
        *)
            TARGET="${1:-}"
            shift
            ;;
    esac
done

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

relative_output_path() {
    local path="${1%/}"
    local base="${OUTPUT_BASE%/}"
    local common="$base"
    local up=""

    if [ "$path" = "$base" ]; then
        printf '.'
        return
    fi

    while [ "$common" != "/" ] && [ "$path" != "$common" ] && [ "${path#"$common"/}" = "$path" ]; do
        common="${common%/*}"
        up="../$up"
    done

    if [ "$path" = "$common" ]; then
        printf '%s' "${up%/}"
    elif [ "$common" = "/" ]; then
        printf '%s%s' "$up" "${path#/}"
    else
        printf '%s%s' "$up" "${path#"$common"/}"
    fi
}

if [ -z "$TARGET" ]; then
    echo '{"status":"error","error":"target root is required","description_nl":"必须提供目标项目目录。"}'
    exit 2
fi

TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
    echo '{"status":"error","error":"target not found","description_nl":"目标项目目录不存在或无法访问。"}'
    exit 2
}
TARGET_DISPLAY="$(relative_output_path "$TARGET")"

DEFAULT_CAPABILITIES=(
    "core"
    "git.commit-format"
    "project.gitignore"
    "ai.execution"
    "ai.memory"
    "knowledge.adr"
    "knowledge.troubleshooting"
    "knowledge.research"
    "project.context"
    "knowledge.archive"
)

load_default_capabilities() {
    command -v jq >/dev/null 2>&1 || return 0
    [ -d "$MANIFEST_DIR" ] || return 0

    local loaded=()
    local manifest_path manifest_id
    for manifest_path in "$MANIFEST_DIR"/*.json; do
        [ -f "$manifest_path" ] || continue
        manifest_id="$(jq -r 'select(.default == true).id // empty' "$manifest_path" 2>/dev/null || true)"
        [ -n "$manifest_id" ] && loaded+=( "$manifest_id" )
    done

    if [ "${#loaded[@]}" -gt 0 ]; then
        DEFAULT_CAPABILITIES=( "${loaded[@]}" )
    fi
}

CAPABILITIES=()
if [ -n "$CAPABILITIES_RAW" ]; then
    IFS=',' read -r -a raw_parts <<< "$CAPABILITIES_RAW"
    for raw in "${raw_parts[@]}"; do
        raw="$(printf '%s' "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -n "$raw" ] && CAPABILITIES+=( "$raw" )
    done
fi
if [ "${#CAPABILITIES[@]}" -eq 0 ]; then
    load_default_capabilities
    CAPABILITIES=( "${DEFAULT_CAPABILITIES[@]}" )
fi

contains_capability() {
    local needle="$1"
    local cap
    for cap in "${CAPABILITIES[@]}"; do
        [ "$cap" = "$needle" ] && return 0
    done
    return 1
}

has_capability_prefix() {
    local prefix="$1"
    local cap
    for cap in "${CAPABILITIES[@]}"; do
        case "$cap" in
            "$prefix"*) return 0 ;;
        esac
    done
    return 1
}

ITEMS=()
MISSING_TOOLS=0
USER_ACTIONS=0
INITIALIZATIONS=0
INSTALLS=0
ERRORS=0

add_item() {
    local kind="$1"
    local name="$2"
    local status="$3"
    local required="$4"
    local action="$5"
    local description="$6"
    local hint="${7:-}"

    local item
    item="{\"kind\":\"$(json_escape "$kind")\",\"name\":\"$(json_escape "$name")\",\"status\":\"$(json_escape "$status")\",\"required\":$required,\"action\":\"$(json_escape "$action")\",\"description_nl\":\"$(json_escape "$description")\""
    if [ -n "$hint" ]; then
        item+=",\"install_hint\":\"$(json_escape "$hint")\""
    fi
    item+="}"
    ITEMS+=( "$item" )
}

join_json() {
    local out=""
    local item
    for item in "$@"; do
        [ -z "$item" ] && continue
        if [ -z "$out" ]; then
            out="$item"
        else
            out="${out},${item}"
        fi
    done
    printf '%s' "$out"
}

install_hint_for_tool() {
    case "$1" in
        git)
            echo "macOS: xcode-select --install 或 brew install git；Ubuntu/Debian: sudo apt-get install git。"
            ;;
        jq)
            echo "macOS: brew install jq；Ubuntu/Debian: sudo apt-get install jq。"
            ;;
        node|npm|npx)
            echo "安装 Node.js LTS（npm/npx 随 Node.js 提供），例如使用 mise/nvm/brew 或系统包管理器。"
            ;;
        python3)
            echo "安装 Python 3。macOS: brew install python；Ubuntu/Debian: sudo apt-get install python3。"
            ;;
        gh)
            echo "安装 GitHub CLI 并登录：macOS: brew install gh；Ubuntu/Debian: 按 GitHub CLI 官方源安装；然后执行 gh auth login。"
            ;;
        *)
            echo "请使用系统包管理器安装 $1。"
            ;;
    esac
}

need_tool() {
    local tool="$1"
    local reason="$2"
    if command -v "$tool" >/dev/null 2>&1; then
        add_item "tool" "$tool" "ok" "true" "none" "$reason 已可用。"
    else
        MISSING_TOOLS=$((MISSING_TOOLS + 1))
        add_item "tool" "$tool" "missing" "true" "install" "$reason 缺失，不能继续部署。" "$(install_hint_for_tool "$tool")"
    fi
}

requires_node=false
requires_python3=false
requires_gh=false
requires_hook_path=false

if contains_capability "git.commit-format"; then
    requires_node=true
    requires_hook_path=true
fi
if contains_capability "quality.node-tooling"; then
    requires_node=true
    requires_hook_path=true
fi
if contains_capability "github.branch-protection" || contains_capability "release.versioning"; then
    requires_hook_path=true
fi
if contains_capability "github.pr"; then
    requires_python3=true
fi
if contains_capability "github.issue" || contains_capability "quality.tdd"; then
    requires_python3=true
fi
if has_capability_prefix "github." || contains_capability "release.versioning"; then
    requires_gh=true
fi

need_tool "jq" "解析 capability manifest 与 package.json 依赖需要 jq"
need_tool "git" "默认 Git 治理能力要求 git"
if [ "$requires_node" = true ]; then
    need_tool "node" "默认提交约束和 Node 工具链要求 Node.js"
    need_tool "npm" "初始化 Node 项目和安装 package.json 依赖需要 npm"
    need_tool "npx" "本地 hook 通过 npx --no-install 调用项目内工具"
fi
if [ "$requires_python3" = true ]; then
    need_tool "python3" "PR body 结构校验脚本需要 Python 3"
fi
if [ "$requires_gh" = true ]; then
    need_tool "gh" "GitHub 能力要求 GitHub CLI"
fi

if [ "$MISSING_TOOLS" -gt 0 ]; then
    items_json="$(join_json "${ITEMS[@]}")"
    cat <<JSONEOF
{
  "mode":"$MODE",
  "target":"$(json_escape "$TARGET_DISPLAY")",
  "status":"needs_install",
  "summary":"Missing required environment tools.",
  "items":[${items_json}],
  "missing_tools":$MISSING_TOOLS,
  "initializations":0,
  "installs":0,
  "user_actions":0,
  "errors":0,
  "description_nl":"缺少必需工具。请先安装缺失工具；如果用户拒绝安装，应终止大禹治库 Skill 部署。"
}
JSONEOF
    exit 0
fi

if [ ! -d "$TARGET/.git" ]; then
    if [ "$MODE" = "apply" ]; then
        if git -C "$TARGET" init >/dev/null 2>&1; then
            INITIALIZATIONS=$((INITIALIZATIONS + 1))
            add_item "project" "git" "initialized" "true" "git init" "目标目录不是 Git 项目，已执行 git init。"
        else
            ERRORS=$((ERRORS + 1))
            add_item "project" "git" "error" "true" "git init" "目标目录不是 Git 项目，且 git init 执行失败。"
        fi
    else
        INITIALIZATIONS=$((INITIALIZATIONS + 1))
        add_item "project" "git" "needs_initialization" "true" "git init" "目标目录不是 Git 项目，部署前必须执行 git init。"
    fi
else
    add_item "project" "git" "ok" "true" "none" "目标目录已是 Git 项目。"
fi

if [ "$requires_hook_path" = true ] && [ -d "$TARGET/.git" ]; then
    hooks_path="$(git -C "$TARGET" config --local --get core.hooksPath 2>/dev/null || true)"
    if [ -z "$hooks_path" ]; then
        if [ "$MODE" = "apply" ]; then
            if git -C "$TARGET" config core.hooksPath .husky >/dev/null 2>&1; then
                INITIALIZATIONS=$((INITIALIZATIONS + 1))
                add_item "git_config" "core.hooksPath" "configured" "true" "git config core.hooksPath .husky" "已配置 Git 使用 .husky 目录执行 hooks。"
            else
                ERRORS=$((ERRORS + 1))
                add_item "git_config" "core.hooksPath" "error" "true" "git config core.hooksPath .husky" "配置 Git hooksPath 失败。"
            fi
        else
            INITIALIZATIONS=$((INITIALIZATIONS + 1))
            add_item "git_config" "core.hooksPath" "needs_initialization" "true" "git config core.hooksPath .husky" "Git hooksPath 未配置，部署前必须指向 .husky。"
        fi
    elif [ "$hooks_path" = ".husky" ]; then
        add_item "git_config" "core.hooksPath" "ok" "true" "none" "Git hooksPath 已指向 .husky。"
    else
        USER_ACTIONS=$((USER_ACTIONS + 1))
        add_item "git_config" "core.hooksPath" "needs_user_action" "true" "manual_confirm" "Git hooksPath 当前为 ${hooks_path}。不能自动覆盖已有 hooksPath，必须由用户确认迁移到 .husky 或手动合并。"
    fi
fi

NPM_DEPS=()
if contains_capability "git.commit-format"; then
    NPM_DEPS+=( "@commitlint/cli" "@commitlint/config-conventional" )
fi
if contains_capability "quality.node-tooling"; then
    NPM_DEPS+=( "eslint" "@eslint/js" "prettier" "lint-staged" )
fi

if [ "$requires_node" = true ]; then
    if [ ! -f "$TARGET/package.json" ]; then
        if [ "$MODE" = "apply" ]; then
            if (cd "$TARGET" && npm init -y >/dev/null 2>&1); then
                INITIALIZATIONS=$((INITIALIZATIONS + 1))
                add_item "project" "node" "initialized" "true" "npm init -y" "目标目录不是 Node 项目，已执行 npm init -y。"
            else
                ERRORS=$((ERRORS + 1))
                add_item "project" "node" "error" "true" "npm init -y" "目标目录不是 Node 项目，且 npm init -y 执行失败。"
            fi
        else
            INITIALIZATIONS=$((INITIALIZATIONS + 1))
            add_item "project" "node" "needs_initialization" "true" "npm init -y" "目标目录不是 Node 项目，部署前必须执行 npm init -y。"
        fi
    else
        add_item "project" "node" "ok" "true" "none" "package.json 已存在。"
    fi

    if [ -f "$TARGET/package.json" ] && [ "${#NPM_DEPS[@]}" -gt 0 ]; then
        MISSING_NPM_DEPS=()
        for dep in "${NPM_DEPS[@]}"; do
            if jq -e --arg dep "$dep" '(.devDependencies[$dep] // .dependencies[$dep]) != null' "$TARGET/package.json" >/dev/null 2>&1; then
                continue
            fi
            MISSING_NPM_DEPS+=( "$dep" )
        done

        if [ "${#MISSING_NPM_DEPS[@]}" -gt 0 ]; then
            dep_list="${MISSING_NPM_DEPS[*]}"
            if [ "$MODE" = "apply" ]; then
                if (cd "$TARGET" && npm install --save-dev "${MISSING_NPM_DEPS[@]}" >/dev/null 2>&1); then
                    INSTALLS=$((INSTALLS + 1))
                    add_item "npm_dependencies" "devDependencies" "installed" "true" "npm install --save-dev ${dep_list}" "已安装必需 package.json devDependencies：${dep_list}。"
                else
                    ERRORS=$((ERRORS + 1))
                    add_item "npm_dependencies" "devDependencies" "error" "true" "npm install --save-dev ${dep_list}" "安装必需 package.json 依赖失败：${dep_list}。"
                fi
            else
                INSTALLS=$((INSTALLS + 1))
                add_item "npm_dependencies" "devDependencies" "needs_install" "true" "npm install --save-dev ${dep_list}" "缺少必需 package.json devDependencies：${dep_list}。"
            fi
        else
            add_item "npm_dependencies" "devDependencies" "ok" "true" "none" "必需 package.json devDependencies 已存在。"
        fi
    fi
fi

if [ "$requires_gh" = true ]; then
    if gh auth status >/dev/null 2>&1; then
        add_item "auth" "gh" "ok" "true" "none" "GitHub CLI 已登录。"
    else
        USER_ACTIONS=$((USER_ACTIONS + 1))
        add_item "auth" "gh" "needs_user_action" "true" "gh auth login" "GitHub CLI 尚未登录，启用 GitHub 能力前必须执行 gh auth login。"
    fi
fi

if [ "$ERRORS" -gt 0 ]; then
    TOP_STATUS="error"
    DESC="环境准备执行失败，必须修复后才能部署。"
elif [ "$USER_ACTIONS" -gt 0 ]; then
    TOP_STATUS="needs_user_action"
    DESC="存在必须由用户确认或登录的环境事项；若用户拒绝，应终止部署。"
elif [ "$MODE" = "check" ] && [ "$INITIALIZATIONS" -gt 0 ]; then
    TOP_STATUS="needs_initialization"
    DESC="环境工具已具备，但目标项目需要初始化；apply 阶段会执行列出的命令。"
elif [ "$MODE" = "check" ] && [ "$INSTALLS" -gt 0 ]; then
    TOP_STATUS="needs_install"
    DESC="环境工具已具备，但目标项目缺少必需 package.json 依赖；apply 阶段会执行列出的安装命令。"
else
    TOP_STATUS="ok"
    DESC="环境依赖完整。"
fi

items_json="$(join_json "${ITEMS[@]}")"
cat <<JSONEOF
{
  "mode":"$MODE",
  "target":"$(json_escape "$TARGET_DISPLAY")",
  "status":"$TOP_STATUS",
  "summary":"$(json_escape "$DESC")",
  "items":[${items_json}],
  "missing_tools":$MISSING_TOOLS,
  "initializations":$INITIALIZATIONS,
  "installs":$INSTALLS,
  "user_actions":$USER_ACTIONS,
  "errors":$ERRORS,
  "description_nl":"$(json_escape "$DESC")"
}
JSONEOF
