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
DEFAULT_BRANCH="main"
PROJECT_VERSION="0.1.0"
PACKAGE_CREATED=false
PACKAGE_VERSION_WAS_MISSING=false
PACKAGE_LOCK_CREATED=false

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

read_current_branch() {
    local branch=""
    branch="$(git -C "$TARGET" symbolic-ref --quiet --short HEAD 2>/dev/null \
        || git -C "$TARGET" rev-parse --abbrev-ref HEAD 2>/dev/null \
        || true)"
    [ "$branch" = "HEAD" ] && branch=""
    [ "$branch" = "null" ] && branch=""
    printf '%s' "$branch"
}

read_package_version() {
    if [ -f "$TARGET/package.json" ] && command -v jq >/dev/null 2>&1; then
        jq -r '.version // empty' "$TARGET/package.json" 2>/dev/null || true
    fi
}

read_version_file() {
    if [ -f "$TARGET/VERSION" ]; then
        sed -n '1p' "$TARGET/VERSION" | tr -d '[:space:]'
    fi
}

read_package_lock_version() {
    if [ -f "$TARGET/package-lock.json" ] && command -v jq >/dev/null 2>&1; then
        local lock_version=""
        lock_version="$(jq -r '.packages[""].version // empty' "$TARGET/package-lock.json" 2>/dev/null || true)"
        if [ -z "$lock_version" ] || [ "$lock_version" = "null" ]; then
            lock_version="$(jq -r '.version // empty' "$TARGET/package-lock.json" 2>/dev/null || true)"
        fi
        printf '%s' "$lock_version"
    fi
}

extract_semver_token() {
    local raw="$1"
    local parsed=""
    local label=""
    label="$(printf '%s\n' "$raw" | sed -nE 's/^\[([^]]+)\]\(.*\).*/\1/p; s/^\[([^]]+)\].*/\1/p; s/^([^[:space:]]+).*/\1/p' | sed -n '1p')"
    case "$label" in
        [Uu]nreleased) return 0 ;;
    esac
    case "$raw" in
        [Uu]nreleased|[Uu]nreleased[[:space:]]*) return 0 ;;
    esac

    parsed="$(printf '%s\n' "$raw" | sed -nE 's/.*\[v?([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?)\].*/\1/p' | sed -n '1p')"
    if [ -z "$parsed" ]; then
        parsed="$(printf '%s\n' "$raw" | sed -nE 's/.*(^|[^0-9A-Za-z.])v?([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?).*/\2/p' | sed -n '1p')"
    fi
    printf '%s' "$parsed"
}

read_changelog_version() {
    if [ -f "$TARGET/CHANGELOG.md" ]; then
        local heading version
        while IFS= read -r heading; do
            version="$(extract_semver_token "$heading")"
            if [ -n "$version" ]; then
                printf '%s' "$version"
                return 0
            fi
        done < <(sed -n 's/^##[[:space:]]*//p' "$TARGET/CHANGELOG.md")
    fi
}

read_release_manifest_version() {
    if [ -f "$TARGET/.release-please-manifest.json" ] && command -v jq >/dev/null 2>&1; then
        jq -r '."." // empty' "$TARGET/.release-please-manifest.json" 2>/dev/null || true
    fi
}

refresh_project_version() {
    local package_version package_lock_version version_file changelog_version manifest_version
    package_version="$(read_package_version)"
    package_lock_version="$(read_package_lock_version)"
    version_file="$(read_version_file)"
    changelog_version="$(read_changelog_version)"
    manifest_version="$(read_release_manifest_version)"

    if [ -n "$package_version" ]; then
        PROJECT_VERSION="$package_version"
    elif [ -n "$package_lock_version" ]; then
        PROJECT_VERSION="$package_lock_version"
    elif [ -n "$version_file" ]; then
        PROJECT_VERSION="$version_file"
    elif [ -n "$changelog_version" ]; then
        PROJECT_VERSION="$changelog_version"
    elif [ -n "$manifest_version" ]; then
        PROJECT_VERSION="$manifest_version"
    fi
}

detect_version_conflict() {
    local package_version package_lock_version version_file changelog_version manifest_version
    local first_version=""
    local conflict="false"
    local source_summary=""

    package_version="$(read_package_version)"
    package_lock_version="$(read_package_lock_version)"
    version_file="$(read_version_file)"
    changelog_version="$(read_changelog_version)"
    manifest_version="$(read_release_manifest_version)"

    add_version_source() {
        local source_name="$1"
        local source_value="$2"
        [ -n "$source_value" ] || return 0
        if [ -z "$source_summary" ]; then
            source_summary="${source_name}=${source_value}"
        else
            source_summary="${source_summary}, ${source_name}=${source_value}"
        fi
        if [ -z "$first_version" ]; then
            first_version="$source_value"
        elif [ "$source_value" != "$first_version" ]; then
            conflict="true"
        fi
    }

    add_version_source "package.json" "$package_version"
    add_version_source "package-lock.json" "$package_lock_version"
    add_version_source "VERSION" "$version_file"
    add_version_source "CHANGELOG.md" "$changelog_version"
    add_version_source ".release-please-manifest.json" "$manifest_version"
    [ -n "$first_version" ] && PROJECT_VERSION="$first_version"

    if [ "$conflict" = "true" ]; then
        USER_ACTIONS=$((USER_ACTIONS + 1))
        add_item "project_version" "version_sources" "needs_user_action" "true" "manual_resolve_version_conflict" "检测到项目版本源不一致：${source_summary}。请先选择唯一版本并同步 package.json、package-lock.json、VERSION、CHANGELOG.md 与 release manifest。"
        return 0
    fi
    return 1
}

set_package_version() {
    local version="$1"
    [ -f "$TARGET/package.json" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local tmp_file
    tmp_file="$(mktemp "$TARGET/.dayu-package.XXXXXX")" || return 1
    if jq --arg version "$version" '.version = $version' "$TARGET/package.json" > "$tmp_file"; then
        mv "$tmp_file" "$TARGET/package.json"
        return 0
    fi
    rm -f "$tmp_file"
    return 1
}

set_package_lock_version() {
    local version="$1"
    [ -f "$TARGET/package-lock.json" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local tmp_file
    tmp_file="$(mktemp "$TARGET/.dayu-package-lock.XXXXXX")" || return 1
    if jq --arg version "$version" '
        if has("packages") and (.packages | type == "object") and ((.packages[""]) | type == "object") then
            .packages[""] += {version: $version}
        else
            .
        end |
        if has("version") then
            .version = $version
        else
            .
        end
    ' "$TARGET/package-lock.json" > "$tmp_file"; then
        mv "$tmp_file" "$TARGET/package-lock.json"
        return 0
    fi

    rm -f "$tmp_file"
    return 1
}

ensure_package_lock_file() {
    [ "$MODE" = "apply" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    [ -f "$TARGET/package-lock.json" ] && return 0
    [ -f "$TARGET/package.json" ] || return 0

    local package_name package_lock_tmp lock_version
    lock_version="${PROJECT_VERSION}"

    package_name="$(jq -r '.name // "dayu-harness-project"' "$TARGET/package.json" 2>/dev/null || echo "dayu-harness-project")"
    package_lock_tmp="$(mktemp "$TARGET/.dayu-package-lock.XXXXXX")" || return 1

    jq -n --arg name "$package_name" --arg version "$lock_version" '{
        name: $name,
        version: $version,
        lockfileVersion: 3,
        requires: true,
        packages: {
            "": {
                version: $version,
                dependencies: {}
            }
        },
        dependencies: {}
    }' > "$package_lock_tmp"

    if mv "$package_lock_tmp" "$TARGET/package-lock.json"; then
        PACKAGE_LOCK_CREATED=true
        return 0
    fi

    rm -f "$package_lock_tmp"
    return 1
}

ensure_file() {
    local path="$1"
    local content="$2"
    local description="$3"
    local action="$4"

    if [ -f "$path" ]; then
        add_item "project_file" "$(basename "$path")" "ok" "false" "none" "${description}已存在。"
        return 0
    fi

    if [ "$MODE" = "apply" ]; then
        printf '%s\n' "$content" > "$path"
        INITIALIZATIONS=$((INITIALIZATIONS + 1))
        add_item "project_file" "$(basename "$path")" "created" "false" "$action" "已创建${description}。"
    else
        INITIALIZATIONS=$((INITIALIZATIONS + 1))
        add_item "project_file" "$(basename "$path")" "needs_initialization" "false" "$action" "项目缺少${description}，apply 阶段会创建。"
    fi
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
  "default_branch":"$(json_escape "$DEFAULT_BRANCH")",
  "project_baseline":{"version":"$(json_escape "$PROJECT_VERSION")"},
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

if detect_version_conflict; then
    items_json="$(join_json "${ITEMS[@]}")"
    cat <<JSONEOF
{
  "mode":"$MODE",
  "target":"$(json_escape "$TARGET_DISPLAY")",
  "status":"needs_user_action",
  "default_branch":"$(json_escape "$DEFAULT_BRANCH")",
  "project_baseline":{"version":"$(json_escape "$PROJECT_VERSION")"},
  "summary":"Project version sources conflict.",
  "items":[${items_json}],
  "missing_tools":0,
  "initializations":0,
  "installs":0,
  "user_actions":$USER_ACTIONS,
  "errors":0,
  "description_nl":"检测到项目版本源不一致。请先同步 package.json、package-lock.json、VERSION、CHANGELOG.md 与 release manifest 后再部署。"
}
JSONEOF
    exit 0
fi

refresh_project_version

if [ ! -d "$TARGET/.git" ]; then
    if [ "$MODE" = "apply" ]; then
        if git -C "$TARGET" init -b main >/dev/null 2>&1 || (git -C "$TARGET" init >/dev/null 2>&1 && git -C "$TARGET" branch -M main >/dev/null 2>&1); then
            INITIALIZATIONS=$((INITIALIZATIONS + 1))
            DEFAULT_BRANCH="$(read_current_branch)"
            [ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"
            add_item "project" "git" "initialized" "true" "git init -b main" "目标目录不是 Git 项目，已初始化 Git，并使用 ${DEFAULT_BRANCH} 作为默认分支。"
        else
            ERRORS=$((ERRORS + 1))
            add_item "project" "git" "error" "true" "git init -b main" "目标目录不是 Git 项目，且 Git 初始化执行失败。"
        fi
    else
        INITIALIZATIONS=$((INITIALIZATIONS + 1))
        add_item "project" "git" "needs_initialization" "true" "git init -b main" "目标目录不是 Git 项目，apply 阶段会使用 main 初始化默认分支。"
    fi
else
    DEFAULT_BRANCH="$(read_current_branch)"
    [ -z "$DEFAULT_BRANCH" ] && DEFAULT_BRANCH="main"
    add_item "project" "git" "ok" "true" "none" "目标目录已是 Git 项目，将保留当前默认分支 ${DEFAULT_BRANCH}。"
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
                PACKAGE_CREATED=true
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

    package_version="$(read_package_version)"
    if [ -n "$package_version" ] && [ "$PACKAGE_CREATED" != true ]; then
        PROJECT_VERSION="$package_version"
    elif [ -z "$package_version" ]; then
        PACKAGE_VERSION_WAS_MISSING=true
    fi

    if [ "$MODE" = "apply" ] && { [ "$PACKAGE_CREATED" = true ] || [ "$PACKAGE_VERSION_WAS_MISSING" = true ]; }; then
        if set_package_version "$PROJECT_VERSION"; then
            add_item "project" "package.version" "configured" "false" "set package.json version" "已将 package.json version 设置为 ${PROJECT_VERSION}。"
        else
            ERRORS=$((ERRORS + 1))
            add_item "project" "package.version" "error" "false" "set package.json version" "设置 package.json version 失败。"
        fi
    elif [ -f "$TARGET/package.json" ]; then
        add_item "project" "package.version" "ok" "false" "none" "package.json version 使用 ${PROJECT_VERSION}。"
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
                    if ! set_package_version "$PROJECT_VERSION"; then
                        ERRORS=$((ERRORS + 1))
                        add_item "project" "package.version" "error" "false" "set package.json version" "安装依赖后重新同步 package.json version 失败。"
                    fi
                    if ! ensure_package_lock_file || ! set_package_lock_version "$PROJECT_VERSION"; then
                        ERRORS=$((ERRORS + 1))
                        add_item "project" "package-lock.version" "error" "false" "sync package-lock.json version" "安装依赖后同步 package-lock.json version 失败。"
                    fi
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

if [ "$requires_node" = true ] && [ -f "$TARGET/package.json" ]; then
    if [ "$MODE" = "apply" ]; then
        if ensure_package_lock_file && set_package_lock_version "$PROJECT_VERSION"; then
            if [ "$PACKAGE_LOCK_CREATED" = true ]; then
                add_item "project" "package-lock.json" "created" "false" "create package-lock.json" "已创建 package-lock.json 并同步版本 ${PROJECT_VERSION}。"
            elif [ -f "$TARGET/package-lock.json" ]; then
                add_item "project" "package-lock.version" "configured" "false" "sync package-lock.json version" "package-lock.json version 已同步为 ${PROJECT_VERSION}。"
            fi
        else
            ERRORS=$((ERRORS + 1))
            add_item "project" "package-lock.version" "error" "false" "sync package-lock.json version" "同步 package-lock.json version 失败。"
        fi
    elif [ -f "$TARGET/package-lock.json" ]; then
        add_item "project" "package-lock.version" "ok" "false" "none" "package-lock.json version 使用 $(read_package_lock_version)。"
    elif [ "$INSTALLS" -gt 0 ]; then
        add_item "project" "package-lock.json" "needs_install" "false" "npm install" "package-lock.json 缺失；apply 阶段安装依赖时会生成或补齐并同步版本 ${PROJECT_VERSION}。"
    else
        INITIALIZATIONS=$((INITIALIZATIONS + 1))
        add_item "project" "package-lock.json" "needs_initialization" "false" "create package-lock.json" "项目缺少 package-lock.json，apply 阶段会创建并设置版本 ${PROJECT_VERSION}。"
    fi
fi

if [ "$PACKAGE_CREATED" != true ] && [ "$PACKAGE_VERSION_WAS_MISSING" != true ]; then
    refresh_project_version
fi

project_name="$(basename "$TARGET")"
ensure_file "$TARGET/README.md" "# ${project_name}

Project initialized with Dayu Harness governance." "README.md" "create README.md"
ensure_file "$TARGET/VERSION" "$PROJECT_VERSION" "VERSION 文件" "create VERSION"
ensure_file "$TARGET/CHANGELOG.md" "# Changelog

## ${PROJECT_VERSION}

- Initial project baseline." "CHANGELOG.md" "create CHANGELOG.md"

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
  "default_branch":"$(json_escape "$DEFAULT_BRANCH")",
  "project_baseline":{"version":"$(json_escape "$PROJECT_VERSION")"},
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
