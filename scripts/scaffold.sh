#!/usr/bin/env bash
# scaffold.sh — 按能力清单进行项目初始化
# 用法:
#   scaffold.sh <target-root> [--dry-run|--apply] [--enable ids] [--only legacy-category] [--strategy merge|replace|skip]
set -eo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST_DIR="$SKILL_DIR/capabilities"
SCRIPTS_DIR="$SKILL_DIR/scripts"
VALIDATE_SCRIPT="$SKILL_DIR/templates/docs/harness/sensors/scripts/validate.sh"
ENVIRONMENT_SCRIPT="$SCRIPTS_DIR/ensure-environment.sh"
GITHUB_REMOTE_SCRIPT="$SCRIPTS_DIR/github-remote.sh"
OUTPUT_BASE="$(pwd)"

dayu_tmp_dir() {
    local base="${TMPDIR:-/tmp}"
    local candidate
    case "$base" in
        /*) ;;
        *) base="$OUTPUT_BASE/$base" ;;
    esac

    for candidate in "$base" "$OUTPUT_BASE/.tmp" "$SKILL_DIR/.tmp"; do
        [ -n "$candidate" ] || continue
        if mkdir -p "$candidate" 2>/dev/null && [ -d "$candidate" ] && [ -w "$candidate" ]; then
            printf '%s\n' "${candidate%/}"
            return 0
        fi
    done

    echo "error: no writable temporary directory found" >&2
    return 1
}

dayu_mktemp() {
    local prefix="$1"
    mktemp "$(dayu_tmp_dir)/${prefix}.XXXXXX"
}

MODE="prompt"
TARGET=""
ENABLED_CATEGORIES=""
ONLY_CATEGORY="all"
ONLY_EXPLICIT="false"
STRATEGY=""
LOCALE="zh-CN"
GITHUB_REMOTE_MODE="${DAYU_HARNESS_GITHUB_REMOTE:-auto}"
GITHUB_E2E_MODE="${DAYU_HARNESS_GITHUB_E2E:-auto}"
GITHUB_REPOSITORY="${DAYU_HARNESS_GITHUB_REPOSITORY:-}"
GITHUB_VISIBILITY="${DAYU_HARNESS_GITHUB_VISIBILITY:-}"
FINALIZE_GIT="${DAYU_HARNESS_FINALIZE_GIT:-skip}"

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            MODE="dry-run"
            shift
            ;;
        --apply)
            MODE="apply"
            shift
            ;;
        --enable)
            ENABLED_CATEGORIES="${2:-}"
            shift 2
            ;;
        --only)
            ONLY_CATEGORY="${2:-}"
            ONLY_EXPLICIT="true"
            shift 2
            ;;
        --strategy)
            STRATEGY="${2:-}"
            shift 2
            ;;
        --locale)
            LOCALE="${2:-}"
            case "$LOCALE" in
                zh-CN|en) ;;
                *)
                    echo "error: unsupported locale '$LOCALE'. Supported: zh-CN|en" >&2
                    exit 2
                    ;;
            esac
            shift 2
            ;;
        --github-remote)
            GITHUB_REMOTE_MODE="${2:-}"
            case "$GITHUB_REMOTE_MODE" in
                auto|check|apply|verify|skip) ;;
                *)
                    echo "error: unsupported --github-remote '$GITHUB_REMOTE_MODE'. Supported: auto|check|apply|verify|skip" >&2
                    exit 2
                    ;;
            esac
            shift 2
            ;;
        --github-repository|--github-repo)
            GITHUB_REPOSITORY="${2:-}"
            shift 2
            ;;
        --github-visibility|--visibility)
            GITHUB_VISIBILITY="${2:-}"
            case "$GITHUB_VISIBILITY" in
                private|public|"") ;;
                *)
                    echo "error: unsupported --github-visibility '$GITHUB_VISIBILITY'. Supported: private|public" >&2
                    exit 2
                    ;;
            esac
            shift 2
            ;;
        --finalize-git)
            if [ $# -gt 1 ] && [[ "${2:-}" != --* ]]; then
                FINALIZE_GIT="${2:-auto}"
                shift 2
            else
                FINALIZE_GIT="auto"
                shift
            fi
            case "$FINALIZE_GIT" in
                auto|skip) ;;
                *)
                    echo "error: unsupported --finalize-git '$FINALIZE_GIT'. Supported: auto|skip" >&2
                    exit 2
                    ;;
            esac
            ;;
        --github-e2e)
            GITHUB_E2E_MODE="${2:-}"
            case "$GITHUB_E2E_MODE" in
                auto|target|skip) ;;
                *)
                    echo "error: unsupported --github-e2e '$GITHUB_E2E_MODE'. Supported: auto|target|skip" >&2
                    exit 2
                    ;;
            esac
            shift 2
            ;;
        --help|-h)
            MODE="help"
            shift
            ;;
        *)
            TARGET="${1:-}"
            shift
            ;;
    esac
done

usage() {
    echo "用法: scaffold.sh <target-root> [--dry-run|--apply] [--enable ids] [--only category] [--strategy merge|replace|skip] [--locale zh-CN|en] [--github-remote auto|check|apply|verify|skip] [--github-repository owner/repo] [--github-visibility private|public] [--github-e2e auto|target|skip] [--finalize-git auto|skip]"
    echo "说明:"
    echo "  - default=true 的必选能力始终部署；--enable 在必选集上追加能力"
    echo "  - --enable 与 --only 支持逗号分隔；--only 保留历史兼容，不会排除必选能力"
    echo "  - --only 兼容历史分类: docs/husky/commitlint/workflows/eslint/prettier/lint-staged/gitignore/release-please"
    echo "  - --enable 兼容旧能力 id，并会展开到新的原子能力或 preset"
    echo "  - --only all 表示部署全部公开能力；内部能力只通过依赖展开"
    echo "  - --apply 默认不替换已存在文件；安装器 clean 时自动 merge，已有配置需通过 --strategy 声明安全策略"
    echo "  - --locale 选择模板语言。默认 zh-CN；en 将优先使用 manifest.template_files_i18n.en（如存在）"
    echo "  - --github-remote 控制 GitHub remote 编排。默认 auto：dry-run/check 只检查，apply 不推送；apply 需用户显式选择"
    echo "  - --github-repository / --github-visibility 显式指定远端仓库和可见性，等价于对应 DAYU_HARNESS_GITHUB_* 环境变量"
    echo "  - --github-e2e 控制 GitHub Issue/PR 端到端验证。默认 auto：--github-remote apply 且启用 issue+pr 时创建测试 Issue/PR，等待 PR checks 后清理测试产物"
    echo "  - --finalize-git auto 会在部署和本地验证通过后精确 stage managed_paths 并创建初始化提交；默认 skip"
}

if [ "$MODE" = "help" ] || [ -z "${TARGET:-}" ]; then
    usage >&2
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

TARGET_DISPLAY="$(relative_output_path "$TARGET")"
DEFAULT_BRANCH="main"
PROJECT_VERSION="0.1.0"
GITHUB_REMOTE_JSON='{"status":"skipped","description_nl":"GitHub remote orchestration was not requested."}'
REMOTE_VALIDATION_JSON='{"status":"skipped","description_nl":"Remote validation was not requested."}'
GITHUB_E2E_JSON='{"status":"skipped","description_nl":"GitHub Issue/PR E2E validation was not requested."}'
RELEASE_SETTLEMENT_JSON='{"status":"skipped","description_nl":"Release post-remote revalidation was not requested."}'
MANAGED_PATHS=()

if ! command -v jq >/dev/null 2>&1; then
    if [ -f "$ENVIRONMENT_SCRIPT" ] && [ -x "$ENVIRONMENT_SCRIPT" ]; then
        environment_json="$(bash "$ENVIRONMENT_SCRIPT" "$TARGET" --check 2>/dev/null || true)"
    else
        environment_json='{"status":"needs_install","items":[{"kind":"tool","name":"jq","status":"missing","required":true,"action":"install","description_nl":"解析 capability manifest 需要 jq，缺失时不能继续部署。"}],"summary":"Missing required environment tools.","description_nl":"缺少必需工具 jq。请先安装；如果用户拒绝安装，应终止大禹治库 Skill 部署。"}'
    fi

    [ -n "$environment_json" ] || environment_json='{"status":"needs_install","items":[{"kind":"tool","name":"jq","status":"missing","required":true,"action":"install","description_nl":"解析 capability manifest 需要 jq，缺失时不能继续部署。"}],"summary":"Missing required environment tools.","description_nl":"缺少必需工具 jq。请先安装；如果用户拒绝安装，应终止大禹治库 Skill 部署。"}'
    cat <<JSONEOF
{
  "mode":"$MODE",
  "target":"$(json_escape "$TARGET_DISPLAY")",
  "status":"needs_install",
  "default_branch":"$(json_escape "$DEFAULT_BRANCH")",
  "project_baseline":{"version":"$(json_escape "$PROJECT_VERSION")"},
  "github_remote":${GITHUB_REMOTE_JSON},
  "remote_validation":${REMOTE_VALIDATION_JSON},
  "github_e2e":${GITHUB_E2E_JSON},
  "release_settlement":${RELEASE_SETTLEMENT_JSON},
  "environment":${environment_json},
  "capabilities":[],
  "summary":"Environment preparation blocked deployment.",
  "description_nl":"缺少解析 capability manifest 所需的 jq。请先安装缺失工具；如果用户拒绝安装，应终止大禹治库 Skill 部署。",
  "total_files":0,
  "files_new":0,
  "files_existing":0,
  "files_missing":0,
  "capability_count":0
}
JSONEOF
    exit 0
fi

join_json() {
    local out=""
    for item in "$@"; do
        if [ -z "$item" ]; then
            continue
        fi
        if [ -z "$out" ]; then
            out="$item"
        else
            out="${out},${item}"
        fi
    done
    printf '%s' "$out"
}

add_managed_path() {
    local path="$1"
    local existing
    [ -n "$path" ] || return 0
    path="${path#./}"
    case "$path" in
        .claude|.claude/*|skills-lock.json|./skills-lock.json)
            return 0
            ;;
    esac
    if [ "${#MANAGED_PATHS[@]}" -gt 0 ]; then
        for existing in "${MANAGED_PATHS[@]}"; do
            [ "$existing" = "$path" ] && return 0
        done
    fi
    MANAGED_PATHS+=( "$path" )
}

json_array_from_lines() {
    local out="["
    local sep=""
    local item
    for item in "$@"; do
        [ -n "$item" ] || continue
        out="${out}${sep}\"$(json_escape "$item")\""
        sep=","
    done
    out="${out}]"
    printf '%s' "$out"
}

installer_managed_paths() {
    case "$1" in
        install-gitignore.sh)
            printf '%s\n' ".gitignore"
            ;;
        install-husky.sh)
            printf '%s\n' ".husky/commit-msg" ".husky/pre-commit" ".husky/pre-push"
            ;;
    esac
}

collect_managed_paths_for_capability() {
    local manifest_path="$1"
    local kind items_json dst_rel installer_script installer_path

    for kind in template asset; do
        items_json="$(get_kind_items_json "$manifest_path" "$kind")"
        while IFS= read -r dst_rel; do
            add_managed_path "$dst_rel"
        done < <(echo "$items_json" | jq -r '.[].dst? // empty')
    done

    installer_script="$(jq -r '.installer.script // empty' "$manifest_path")"
    [ -n "$installer_script" ] || return 0
    while IFS= read -r installer_path; do
        add_managed_path "$installer_path"
    done < <(installer_managed_paths "$installer_script")
}

collect_managed_paths_for_apply() {
    local cap_id manifest_path
    MANAGED_PATHS=()
    add_managed_path "README.md"
    add_managed_path "VERSION"
    add_managed_path "CHANGELOG.md"
    add_managed_path "package.json"
    add_managed_path "package-lock.json"

    for cap_id in "$@"; do
        manifest_path="$(manifest_path_for_id "$cap_id")" || continue
        collect_managed_paths_for_capability "$manifest_path"
    done
}

managed_staging_policy_json() {
    printf '{"command":"git add -- <managed_paths>","forbidden":["git add .","git add -A","git add --all"],"excluded":[".claude/","skills-lock.json"],"description_nl":"部署后提交只允许 stage Dayu 管理文件和初始化产物，禁止使用 git add .，并排除 .claude/ 与 skills-lock.json。"}'
}

managed_path_is_allowed_for_stage() {
    local path="$1"
    case "$path" in
        .claude|.claude/*|skills-lock.json)
            return 1
            ;;
    esac
    return 0
}

finalize_git_after_apply() {
    local apply_status="$1"
    local checks_status="$2"
    local name email commit_output commit_rc commit_sha
    local stage_paths=()
    local path

    if [ "$FINALIZE_GIT" = "skip" ]; then
        printf '{"status":"skipped","description_nl":"Git finalization was skipped by configuration."}'
        return 0
    fi

    if [ "$apply_status" != "ok" ] || [ "$checks_status" != "passed" ]; then
        printf '{"status":"skipped","description_nl":"Git finalization waits until deployment and post-apply checks are fully passed."}'
        return 0
    fi

    if [ ! -d "$TARGET/.git" ]; then
        printf '{"status":"needs_initialization","description_nl":"目标目录还不是 Git 仓库，无法创建初始化提交。"}'
        return 0
    fi

    name="$(git -C "$TARGET" config user.name 2>/dev/null || true)"
    email="$(git -C "$TARGET" config user.email 2>/dev/null || true)"
    if [ -z "$name" ] || [ -z "$email" ]; then
        printf '{"status":"needs_user_action","description_nl":"Git user.name 或 user.email 未配置，无法创建初始化提交。"}'
        return 0
    fi

    for path in "${MANAGED_PATHS[@]}"; do
        managed_path_is_allowed_for_stage "$path" || continue
        [ -e "$TARGET/$path" ] || continue
        stage_paths+=( "$path" )
    done

    if [ "${#stage_paths[@]}" -eq 0 ]; then
        printf '{"status":"clean","description_nl":"没有可 stage 的 Dayu managed paths。"}'
        return 0
    fi

    if ! git -C "$TARGET" add -- "${stage_paths[@]}" >/dev/null 2>&1; then
        printf '{"status":"error","description_nl":"精确 stage managed paths 失败。"}'
        return 0
    fi
    git -C "$TARGET" reset -q -- .claude skills-lock.json >/dev/null 2>&1 || true

    if git -C "$TARGET" diff --cached --quiet --exit-code >/dev/null 2>&1; then
        printf '{"status":"clean","description_nl":"managed paths 没有新的待提交变更。"}'
        return 0
    fi

    set +e
    commit_output="$(git -C "$TARGET" commit -m "chore: initialize Dayu Harness governance" 2>&1)"
    commit_rc=$?
    set -e

    if [ "$commit_rc" -ne 0 ]; then
        printf '{"status":"error","description_nl":"初始化提交失败：%s"}' "$(json_escape "$commit_output")"
        return 0
    fi

    commit_sha="$(git -C "$TARGET" rev-parse --short=12 HEAD 2>/dev/null || true)"
    printf '{"status":"committed","commit":"%s","staged_paths":%s,"description_nl":"已创建 Dayu Harness 初始化提交，只包含 managed paths。"}' \
        "$(json_escape "$commit_sha")" \
        "$(json_array_from_lines "${stage_paths[@]}")"
}

trim() {
    printf '%s' "$(echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
}

contains_item() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

detect_default_branch() {
    local branch=""
    if [ -d "$TARGET/.git" ]; then
        branch="$(git -C "$TARGET" symbolic-ref --quiet --short HEAD 2>/dev/null \
            || git -C "$TARGET" rev-parse --abbrev-ref HEAD 2>/dev/null \
            || true)"
    fi
    [ -n "$branch" ] && [ "$branch" != "HEAD" ] || branch="main"
    case "$branch" in
        dayu-harness/init|dayu-harness/init-*)
            branch="main"
            ;;
    esac
    printf '%s\n' "$branch"
}

project_has_meaningful_initial_content() {
    local entry base
    while IFS= read -r entry; do
        base="$(basename "$entry")"
        case "$base" in
            .git|.claude|node_modules|package.json|package-lock.json|npm-shrinkwrap.json|.DS_Store)
                continue
                ;;
        esac
        return 0
    done < <(find "$TARGET" -mindepth 1 -maxdepth 1 -print 2>/dev/null)
    return 1
}

read_package_lock_version() {
    if [ -f "$TARGET/package-lock.json" ]; then
        local lock_version=""
        lock_version="$(jq -r '.packages[""].version // empty' "$TARGET/package-lock.json" 2>/dev/null || true)"
        if [ -z "$lock_version" ] || [ "$lock_version" = "null" ]; then
            lock_version="$(jq -r '.version // empty' "$TARGET/package-lock.json" 2>/dev/null || true)"
        fi
        printf '%s' "$lock_version"
    fi
}

is_npm_default_initial_version() {
    local package_version package_lock_version
    [ -f "$TARGET/package.json" ] || return 1
    package_version="$(jq -r '.version // empty' "$TARGET/package.json" 2>/dev/null || true)"
    package_lock_version="$(read_package_lock_version)"

    [ "$package_version" = "1.0.0" ] || return 1
    [ -z "$package_lock_version" ] || [ "$package_lock_version" = "1.0.0" ] || return 1
    [ ! -f "$TARGET/VERSION" ] || return 1
    [ ! -f "$TARGET/CHANGELOG.md" ] || return 1
    [ ! -f "$TARGET/.release-please-manifest.json" ] || return 1
    [ ! -f "$TARGET/AGENTS.md" ] || return 1
    if project_has_meaningful_initial_content; then
        return 1
    fi
    return 0
}

detect_project_version() {
    local version=""
    if is_npm_default_initial_version; then
        version="0.1.0"
    elif [ -f "$TARGET/package.json" ]; then
        version="$(jq -r '.version // empty' "$TARGET/package.json" 2>/dev/null || true)"
    fi
    if [ -z "$version" ] && [ -f "$TARGET/VERSION" ]; then
        version="$(sed -n '1p' "$TARGET/VERSION" | tr -d '[:space:]')"
    fi
    [ -n "$version" ] || version="0.1.0"
    printf '%s\n' "$version"
}

refresh_project_context() {
    local environment_json="${1:-}"
    local env_branch=""
    local env_version=""

    if [ -n "$environment_json" ]; then
        env_branch="$(echo "$environment_json" | jq -r '.default_branch // empty' 2>/dev/null || true)"
        env_version="$(echo "$environment_json" | jq -r '.project_baseline.version // empty' 2>/dev/null || true)"
    fi

    if [ -n "$env_branch" ] && [ "$env_branch" != "HEAD" ] && [ "$env_branch" != "null" ]; then
        DEFAULT_BRANCH="$env_branch"
    else
        DEFAULT_BRANCH="$(detect_default_branch)"
    fi

    if [ -n "$env_version" ]; then
        PROJECT_VERSION="$env_version"
    else
        PROJECT_VERSION="$(detect_project_version)"
    fi
}

project_baseline_json() {
    local readme_state="missing"
    local version_state="missing"
    local changelog_state="missing"
    [ -f "$TARGET/README.md" ] && readme_state="present"
    [ -f "$TARGET/VERSION" ] && version_state="present"
    [ -f "$TARGET/CHANGELOG.md" ] && changelog_state="present"
    printf '{"version":"%s","readme":"%s","version_file":"%s","changelog":"%s"}' \
        "$(json_escape "$PROJECT_VERSION")" \
        "$readme_state" \
        "$version_state" \
        "$changelog_state"
}

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

render_managed_file() {
    local src_path="$1"
    local dst_path="$2"
    local branch_replacement version_replacement
    branch_replacement="$(escape_sed_replacement "$DEFAULT_BRANCH")"
    version_replacement="$(escape_sed_replacement "$PROJECT_VERSION")"

    if LC_ALL=C grep -Iq . "$src_path" 2>/dev/null && grep -q "__DAYU_" "$src_path" 2>/dev/null; then
        sed \
            -e "s/__DAYU_DEFAULT_BRANCH__/${branch_replacement}/g" \
            -e "s/__DAYU_PROJECT_VERSION__/${version_replacement}/g" \
            "$src_path" > "$dst_path"
    else
        cp "$src_path" "$dst_path"
    fi
}

manifest_remote_actions_json() {
    local manifest_path="$1"
    jq -c '.remote_actions // []' "$manifest_path"
}

selected_remote_actions_json() {
    local cap_id manifest_path action
    local actions=()

    for cap_id in "$@"; do
        manifest_path="$(manifest_path_for_id "$cap_id")" || continue
        while IFS= read -r action; do
            [ -n "$action" ] && actions+=( "$action" )
        done < <(jq -c '.remote_actions[]?' "$manifest_path")
    done

    printf '[%s]' "$(join_json "${actions[@]}")"
}

capability_has_remote_actions() {
    local cap_id="$1"
    local manifest_path
    manifest_path="$(manifest_path_for_id "$cap_id")" || return 1
    jq -e '(.remote_actions // []) | length > 0' "$manifest_path" >/dev/null 2>&1
}

selected_has_remote_actions() {
    local cap_id
    for cap_id in "$@"; do
        if capability_has_remote_actions "$cap_id"; then
            return 0
        fi
    done
    return 1
}

selected_has_github_capabilities() {
    local cap_id
    for cap_id in "$@"; do
        case "$cap_id" in
            github.*|release.*)
                return 0
                ;;
        esac
    done
    return 1
}

selected_has_github_e2e_capabilities() {
    local has_issue="false"
    local has_pr="false"
    local cap_id
    for cap_id in "$@"; do
        [ "$cap_id" = "github.issue" ] && has_issue="true"
        [ "$cap_id" = "github.pr" ] && has_pr="true"
    done
    [ "$has_issue" = "true" ] && [ "$has_pr" = "true" ]
}

selected_has_release_please_capability() {
    local cap_id
    for cap_id in "$@"; do
        [ "$cap_id" = "github.release-please" ] && return 0
    done
    return 1
}

selected_has_capability() {
    local wanted="$1"
    shift || true
    local cap_id
    for cap_id in "$@"; do
        [ "$cap_id" = "$wanted" ] && return 0
    done
    return 1
}

dayu_tmp_candidates() {
    [ -n "${DAYU_HARNESS_TMPDIR:-}" ] && printf '%s\n' "$DAYU_HARNESS_TMPDIR"
    [ -n "${TMPDIR:-}" ] && printf '%s\n' "$TMPDIR"
    [ -n "${TARGET:-}" ] && printf '%s\n' "$TARGET/.tmp"
    [ -n "${OUTPUT_BASE:-}" ] && printf '%s\n' "$OUTPUT_BASE/.tmp"
    printf '%s\n' "/tmp"
}

make_writable_tmpfile() {
    local prefix="$1"
    local candidate candidate_abs tmp_file
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        mkdir -p "$candidate" 2>/dev/null || true
        candidate_abs="$(cd "$candidate" 2>/dev/null && pwd)" || continue
        tmp_file="$(mktemp "${candidate_abs%/}/${prefix}.XXXXXX" 2>/dev/null || true)"
        if [ -n "$tmp_file" ]; then
            printf '%s\n' "$tmp_file"
            return 0
        fi
    done < <(dayu_tmp_candidates)
    return 1
}

run_github_remote() {
    local mode="$1"
    shift || true
    local remote_output remote_rc remote_stderr remote_stderr_file payload
    local remote_actions_json
    remote_actions_json="$(selected_remote_actions_json "$@")"

    if [ ! -f "$GITHUB_REMOTE_SCRIPT" ] || [ ! -x "$GITHUB_REMOTE_SCRIPT" ]; then
        printf '{"status":"skipped","description_nl":"github-remote.sh is missing or not executable."}'
        return 0
    fi

    remote_stderr_file=""
    remote_stderr_file="$(make_writable_tmpfile "dayu-github-remote-stderr" 2>/dev/null || true)"
    set +e
    if [ -n "$remote_stderr_file" ]; then
        remote_output="$(DAYU_HARNESS_DEFAULT_BRANCH="$DEFAULT_BRANCH" DAYU_HARNESS_GITHUB_REPOSITORY="$GITHUB_REPOSITORY" DAYU_HARNESS_GITHUB_VISIBILITY="$GITHUB_VISIBILITY" DAYU_HARNESS_REMOTE_ACTIONS_JSON="$remote_actions_json" bash "$GITHUB_REMOTE_SCRIPT" "$TARGET" "--$mode" 2>"$remote_stderr_file")"
        remote_rc=$?
        remote_stderr="$(sed -n '1,12p' "$remote_stderr_file" | tr '\n' ' ' || true)"
        rm -f "$remote_stderr_file"
    else
        remote_output="$(DAYU_HARNESS_DEFAULT_BRANCH="$DEFAULT_BRANCH" DAYU_HARNESS_GITHUB_REPOSITORY="$GITHUB_REPOSITORY" DAYU_HARNESS_GITHUB_VISIBILITY="$GITHUB_VISIBILITY" DAYU_HARNESS_REMOTE_ACTIONS_JSON="$remote_actions_json" bash "$GITHUB_REMOTE_SCRIPT" "$TARGET" "--$mode" 2>&1)"
        remote_rc=$?
        remote_stderr=""
    fi
    set -e

    payload="$(printf '%s\n' "$remote_output" | json_payload_from_output)"
    if printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
        printf '%s' "$payload"
    else
        printf '{"status":"error","exit_code":%s,"description_nl":"github-remote.sh %s failed or returned non-JSON stdout.","stdout":"%s","stderr":"%s"}' \
            "$remote_rc" \
            "$(json_escape "$mode")" \
            "$(json_escape "$remote_output")" \
            "$(json_escape "$remote_stderr")"
    fi
}

# ------------------------------------------------------------
# Manifest loading
# ------------------------------------------------------------
MANIFEST_IDS=()
MANIFEST_PATHS=()
DEFAULT_IDS=()
PUBLIC_IDS=()

for manifest_path in "$MANIFEST_DIR"/*.json; do
    [ -f "$manifest_path" ] || continue
    manifest_id="$(jq -r '.id // empty' "$manifest_path")"
    [ -z "$manifest_id" ] && continue
    MANIFEST_IDS+=( "$manifest_id" )
    MANIFEST_PATHS+=( "$manifest_path" )
    if ! jq -e '.internal == true' "$manifest_path" >/dev/null 2>&1; then
        PUBLIC_IDS+=( "$manifest_id" )
    fi
    if jq -e '.default == true' "$manifest_path" >/dev/null 2>&1; then
        DEFAULT_IDS+=( "$manifest_id" )
    fi
done

if [ "${#MANIFEST_IDS[@]}" -eq 0 ]; then
    echo '{"status":"error","error":"No capability manifests found."}' >&2
    exit 2
fi

manifest_path_for_id() {
    local id="$1"
    local idx
    for idx in "${!MANIFEST_IDS[@]}"; do
        if [ "${MANIFEST_IDS[$idx]}" = "$id" ]; then
            echo "${MANIFEST_PATHS[$idx]}"
            return 0
        fi
    done
    return 1
}

all_manifest_ids() {
    printf '%s\n' "${PUBLIC_IDS[@]}"
}

default_manifest_ids() {
    printf '%s\n' "${DEFAULT_IDS[@]}"
}

# ------------------------------------------------------------
# Compatibility mapping (legacy category -> capability id)
# ------------------------------------------------------------
map_legacy_category() {
    case "$1" in
        docs)
            echo "core"
            ;;
        husky|commitlint)
            echo "git.commit-format"
            ;;
        workflows)
            echo "github.pr"
            ;;
        eslint|prettier|lint-staged|lint_staged)
            echo "quality.node-tooling"
            ;;
        gitignore)
            echo "project.gitignore"
            ;;
        release-please)
            echo "github.release-please"
            ;;
        git.commit)
            echo "git.commit-format"
            ;;
        github.branch-release)
            echo "github.branch-protection release.versioning"
            ;;
        quality.tooling)
            echo "quality.practices quality.node-tooling project.gitignore"
            ;;
        ai.collaboration)
            echo "ai.execution ai.memory"
            ;;
        project.docs)
            echo "project.context"
            ;;
        archive.project)
            echo "knowledge.archive"
            ;;
        knowledge.base)
            echo "knowledge.adr knowledge.troubleshooting knowledge.research knowledge.archive"
            ;;
        quality.standard)
            echo "quality.practices project.gitignore quality.node-tooling"
            ;;
        github.delivery)
            echo "git.commit-format github.repository-settings github.issue github.pr github.branch-protection"
            ;;
        release.automated)
            echo "github.repository-settings release.versioning github.release-please"
            ;;
        *)
            echo "$1"
            ;;
    esac
}

resolve_request_ids() {
    local raw_ids=()
    local token
    local token_trimmed
    local mapped

    while IFS= read -r id; do
        [ -z "$id" ] && continue
        raw_ids+=( "$id" )
    done < <(default_manifest_ids)

    if [ -n "$ENABLED_CATEGORIES" ]; then
        IFS=',' read -r -a token_list <<< "$ENABLED_CATEGORIES"
        for token in "${token_list[@]}"; do
            token_trimmed="$(trim "$token")"
            [ -z "$token_trimmed" ] && continue
            if [ "$token_trimmed" = "all" ]; then
                while IFS= read -r id; do
                    raw_ids+=( "$id" )
                done < <(all_manifest_ids)
            else
                mapped="$(map_legacy_category "$token_trimmed")"
                if [ -n "$mapped" ]; then
                    IFS=' ' read -r -a mapped_ids <<< "$mapped"
                    for id in "${mapped_ids[@]}"; do
                        raw_ids+=( "$id" )
                    done
                fi
            fi
        done
    elif [ "$ONLY_EXPLICIT" = "true" ]; then
        if [ "$ONLY_CATEGORY" = "all" ]; then
            while IFS= read -r id; do
                raw_ids+=( "$id" )
            done < <(all_manifest_ids)
        else
            IFS=',' read -r -a token_list <<< "$ONLY_CATEGORY"
            for token in "${token_list[@]}"; do
                token_trimmed="$(trim "$token")"
                [ -z "$token_trimmed" ] && continue
                mapped="$(map_legacy_category "$token_trimmed")"
                if [ -n "$mapped" ]; then
                    IFS=' ' read -r -a mapped_ids <<< "$mapped"
                    for id in "${mapped_ids[@]}"; do
                        raw_ids+=( "$id" )
                    done
                fi
            done
        fi
    fi

    local resolved=()
    local id
    for id in "${raw_ids[@]}"; do
        [ -z "$id" ] && continue
        if ! manifest_path_for_id "$id" >/dev/null; then
            echo "error: unknown capability '$id'" >&2
            exit 2
        fi
        if ! contains_item "$id" "${resolved[@]}"; then
            resolved+=( "$id" )
        fi
    done
    printf '%s\n' "${resolved[@]}"
}

get_template_items_json() {
    local manifest_path="$1"
    local items_json

    if [ "$LOCALE" = "en" ]; then
        items_json="$(jq -c '
            . as $manifest
            | (.template_files // []) as $base
            | ($manifest.template_files_i18n.en // []) as $en
            | [
                $base[] | . as $src_item
                | (
                    ($en | map(select(.dst == $src_item.dst)) | .[0]) as $en_item
                    | if ($en_item | type == "object") then
                        $en_item + {"__locale_source_found":true}
                      else
                        {
                            "src": ($src_item.src | sub("^templates/"; "templates.en/")),
                            "dst": $src_item.dst,
                            "executable": ($src_item.executable // false),
                            "__locale_source_found": false
                        }
                      end
                )
            ]
        ' "$manifest_path")"
        echo "$items_json"
        return
    fi

    jq -c '.template_files // []' "$manifest_path"
}

get_kind_items_json() {
    local manifest_path="$1"
    local kind="$2"
    local items_json

    if [ "$kind" = "template" ]; then
        items_json="$(get_template_items_json "$manifest_path")"
        if [ -n "$items_json" ]; then
            echo "$items_json"
        else
            echo "[]"
        fi
        return
    fi

    jq -c ".${kind}_files // []" "$manifest_path"
}

RESOLVE_SEEN=()
RESOLVE_ORDER=()

resolve_recursive() {
    local cap_id="$1"
    if contains_item "$cap_id" "${RESOLVE_SEEN[@]}"; then
        return 0
    fi
    RESOLVE_SEEN+=( "$cap_id" )

    local manifest_path
    manifest_path="$(manifest_path_for_id "$cap_id")" || {
        echo "error: unknown capability '$cap_id'" >&2
        exit 2
    }

    local dep_id
    while IFS= read -r dep_id; do
        dep_id="$(trim "$dep_id")"
        [ -z "$dep_id" ] && continue
        if ! manifest_path_for_id "$dep_id" >/dev/null; then
            echo "error: unknown dependency '$dep_id' in '$cap_id'" >&2
            exit 2
        fi
        resolve_recursive "$dep_id"
    done < <(jq -r '.dependencies[]? // empty' "$manifest_path")

    RESOLVE_ORDER+=( "$cap_id" )
}

resolve_with_dependencies() {
    RESOLVE_SEEN=()
    RESOLVE_ORDER=()
    for cap_id in "$@"; do
        resolve_recursive "$cap_id"
    done
    printf '%s\n' "${RESOLVE_ORDER[@]}"
}

# ------------------------------------------------------------
# Collectors
# ------------------------------------------------------------
DRY_ITEMS=()
APPLY_ITEMS=()

collect_file_entries() {
    local manifest_path="$1"
    local kind="$2"
    local mode="$3"

    local items_json
    items_json="$(get_kind_items_json "$manifest_path" "$kind")"

    while IFS= read -r item_json; do
        [ -z "$item_json" ] && continue

        local src_rel dst_rel executable
        src_rel="$(echo "$item_json" | jq -r '.src // empty')"
        dst_rel="$(echo "$item_json" | jq -r '.dst // empty')"
        executable="$(echo "$item_json" | jq -r '(.executable // false) | tostring')"
        local locale_source_found
        locale_source_found="$(echo "$item_json" | jq -r 'if has("__locale_source_found") then .["__locale_source_found"] else true end')"
        [ -z "$src_rel" ] && continue

        local src_path="$SKILL_DIR/$src_rel"
        local dst_path="$TARGET/$dst_rel"
        local status="new"
        local needs_strategy="false"
        local exists_in_target="false"
        local source_lines=""
        local target_lines=""
        local description=""

        if [ "$mode" = "dry" ]; then
            if [ "$locale_source_found" = "false" ] || [ ! -f "$src_path" ]; then
                status="missing_source"
                DRY_MISSING=$((DRY_MISSING + 1))
                if [ "$locale_source_found" = "false" ]; then
                    description="Source template lacks English mapping for locale mode: $src_rel"
                else
                    description="Source file missing: $src_rel"
                fi
            else
                source_lines="$(wc -l < "$src_path" | tr -d ' ')"
                DRY_FILES=$((DRY_FILES + 1))
                if [ -f "$dst_path" ]; then
                    status="existing"
                    exists_in_target="true"
                    DRY_EXISTING=$((DRY_EXISTING + 1))
                    target_lines="$(wc -l < "$dst_path" | tr -d ' ')"
                    description="File exists and will be skipped by default in apply."
                else
                    status="new"
                    DRY_NEW=$((DRY_NEW + 1))
                    description="New file ready for copy."
                fi
            fi
        else
            if [ "$locale_source_found" = "false" ] || [ ! -f "$src_path" ]; then
                status="missing_source"
                APPLY_MISSING=$((APPLY_MISSING + 1))
                APPLY_ERROR=$((APPLY_ERROR + 1))
                if [ "$locale_source_found" = "false" ]; then
                    description="Source template lacks English mapping for locale mode: $src_rel"
                else
                    description="Source file missing: $src_rel"
                fi
            else
                source_lines="$(wc -l < "$src_path" | tr -d ' ')"
                APPLY_FILES=$((APPLY_FILES + 1))
                if [ -f "$dst_path" ]; then
                    status="skipped_existing"
                    needs_strategy="true"
                    exists_in_target="true"
                    target_lines="$(wc -l < "$dst_path" | tr -d ' ')"
                    APPLY_EXISTING=$((APPLY_EXISTING + 1))
                    APPLY_SKIPPED=$((APPLY_SKIPPED + 1))
                    description="Target file exists; skipped by default."
                else
                    mkdir -p "$(dirname "$dst_path")"
                    if render_managed_file "$src_path" "$dst_path"; then
                        if [ "$executable" = "true" ]; then
                            chmod +x "$dst_path"
                        fi
                        status="copied"
                        APPLY_NEW=$((APPLY_NEW + 1))
                        description="Copied source file."
                    else
                        status="error"
                        APPLY_ERROR=$((APPLY_ERROR + 1))
                        description="Failed to copy source file."
                    fi
                fi
            fi
        fi

        local item
        item="{\"kind\":\"$kind\",\"src\":\"$(json_escape "$src_rel")\",\"dst\":\"$(json_escape "$dst_rel")\",\"executable\":$executable,\"exists_in_target\":$exists_in_target,\"status\":\"$(json_escape "$status")\",\"needs_strategy\":$needs_strategy,\"description_nl\":\"$(json_escape "$description")\""
        if [ -n "$source_lines" ]; then
            item+=",\"source_lines\":$source_lines"
        fi
        if [ -n "$target_lines" ]; then
            item+=",\"target_lines\":$target_lines"
        fi
        item+="}"

        if [ "$mode" = "dry" ]; then
            DRY_ITEMS+=( "$item" )
        else
            APPLY_ITEMS+=( "$item" )
        fi
    done < <(echo "$items_json" | jq -c '.[]?')
}

collect_file_entries_blocked() {
    local manifest_path="$1"
    local kind="$2"
    local status="$3"
    local description="$4"

    local items_json
    items_json="$(get_kind_items_json "$manifest_path" "$kind")"

    while IFS= read -r item_json; do
        [ -z "$item_json" ] && continue

        local src_rel dst_rel executable src_path dst_path exists_in_target source_lines target_lines item_status
        src_rel="$(echo "$item_json" | jq -r '.src // empty')"
        dst_rel="$(echo "$item_json" | jq -r '.dst // empty')"
        executable="$(echo "$item_json" | jq -r '(.executable // false) | tostring')"
        local locale_source_found
        locale_source_found="$(echo "$item_json" | jq -r 'if has("__locale_source_found") then .["__locale_source_found"] else true end')"
        [ -z "$src_rel" ] && continue

        src_path="$SKILL_DIR/$src_rel"
        dst_path="$TARGET/$dst_rel"
        exists_in_target="false"
        source_lines=""
        target_lines=""
        item_status="$status"

        APPLY_FILES=$((APPLY_FILES + 1))
        if [ "$locale_source_found" != "false" ] && [ -f "$src_path" ]; then
            source_lines="$(wc -l < "$src_path" | tr -d ' ')"
        else
            item_status="missing_source"
            APPLY_MISSING=$((APPLY_MISSING + 1))
            APPLY_ERROR=$((APPLY_ERROR + 1))
        fi
        if [ -f "$dst_path" ]; then
            exists_in_target="true"
            APPLY_EXISTING=$((APPLY_EXISTING + 1))
            target_lines="$(wc -l < "$dst_path" | tr -d ' ')"
        fi
        if [ "$item_status" = "needs_strategy" ]; then
            APPLY_STRATEGY_REQUIRED=$((APPLY_STRATEGY_REQUIRED + 1))
        fi

        local item
        item="{\"kind\":\"$kind\",\"src\":\"$(json_escape "$src_rel")\",\"dst\":\"$(json_escape "$dst_rel")\",\"executable\":$executable,\"exists_in_target\":$exists_in_target,\"status\":\"$(json_escape "$item_status")\",\"needs_strategy\":true,\"description_nl\":\"$(json_escape "$description")\""
        if [ -n "$source_lines" ]; then
            item+=",\"source_lines\":$source_lines"
        fi
        if [ -n "$target_lines" ]; then
            item+=",\"target_lines\":$target_lines"
        fi
        item+="}"
        APPLY_ITEMS+=( "$item" )
    done < <(echo "$items_json" | jq -c '.[]?')
}

collect_installer_entry_dry() {
    local manifest_path="$1"
    local cap_id="$2"
    local installer_script safe_strategies status description
    installer_script="$(jq -r '.installer.script // empty' "$manifest_path")"
    [ -z "$installer_script" ] && return 0

    safe_strategies="$(jq -c '.installer.safe_strategies // ["merge","skip"]' "$manifest_path")"
    local installer_path="$SCRIPTS_DIR/$installer_script"
    status="ready"
    if [ ! -f "$installer_path" ]; then
        status="missing"
        DRY_INST_MISSING=$((DRY_INST_MISSING + 1))
        description="Installer missing: $installer_script"
    elif [ ! -x "$installer_path" ]; then
        status="not_executable"
        DRY_INST_MISSING=$((DRY_INST_MISSING + 1))
        description="Installer not executable: $installer_script"
    else
        description="Installer available."
    fi

    DRY_ITEMS+=( "{\"kind\":\"installer\",\"script\":\"$(json_escape "$installer_script")\",\"capability\":\"$(json_escape "$cap_id")\",\"status\":\"$(json_escape "$status")\",\"safe_strategies\":$safe_strategies,\"needs_strategy\":false,\"description_nl\":\"$(json_escape "$description")\"}" )
}

collect_repository_settings_remote_entry_dry() {
    local cap_id="$1"
    [ "$cap_id" = "github.repository-settings" ] || return 0

    DRY_ITEMS+=( "{\"kind\":\"remote_settings\",\"capability\":\"github.repository-settings\",\"api\":\"PATCH /repos/{owner}/{repo}\",\"status\":\"planned\",\"needs_strategy\":false,\"allow_merge_commit\":true,\"allow_squash_merge\":false,\"allow_rebase_merge\":false,\"allow_auto_merge\":true,\"delete_branch_on_merge\":true,\"description_nl\":\"启用 --github-remote apply 后，会由 scripts/github-remote.sh 统一同步 allow_merge_commit=true、allow_squash_merge=false、allow_rebase_merge=false、allow_auto_merge=true 与 delete_branch_on_merge=true。\"}" )
}

collect_repository_settings_remote_entry_apply() {
    local cap_id="$1"
    [ "$cap_id" = "github.repository-settings" ] || return 0

    local status description
    case "$GITHUB_REMOTE_MODE" in
        apply)
            status="delegated"
            description="远端仓库设置将由 scripts/github-remote.sh --apply 统一执行。"
            ;;
        verify)
            status="verify_only"
            description="本次只验证远端仓库设置，不执行写入。"
            ;;
        skip)
            status="skipped"
            description="用户选择跳过 GitHub remote 编排，未写入远端仓库设置。"
            ;;
        auto|check|"")
            status="pending"
            description="远端仓库设置等待用户显式选择 --github-remote apply 后再写入。"
            ;;
        *)
            status="pending"
            description="远端仓库设置等待 GitHub remote 编排。"
            ;;
    esac

    APPLY_ITEMS+=( "{\"kind\":\"remote_settings\",\"capability\":\"github.repository-settings\",\"api\":\"PATCH /repos/{owner}/{repo}\",\"status\":\"$(json_escape "$status")\",\"needs_strategy\":false,\"allow_merge_commit\":true,\"allow_squash_merge\":false,\"allow_rebase_merge\":false,\"allow_auto_merge\":true,\"delete_branch_on_merge\":true,\"description_nl\":\"$(json_escape "$description")\"}" )
}

collect_installer_entry_apply() {
    local manifest_path="$1"
    local cap_id="$2"
    local effective_strategy="${3:-$STRATEGY}"
    local installer_script safe_strategies status description needs_strategy action installer_result
    installer_script="$(jq -r '.installer.script // empty' "$manifest_path")"
    [ -z "$installer_script" ] && return 0

    safe_strategies="$(jq -r '.installer.safe_strategies[]? // "merge" | @sh' "$manifest_path" | tr '\n' ' ')"
    if [ -z "$safe_strategies" ]; then
        safe_strategies="merge skip"
    fi

    local installer_path="$SCRIPTS_DIR/$installer_script"
    status="ready"
    needs_strategy="false"
    action=""
    installer_result="ok"

    local safe_array_json
    safe_array_json="["
    local sep=""
    for strategy in $safe_strategies; do
        strategy="$(echo "$strategy" | sed "s/^'//;s/'$//")"
        safe_array_json="${safe_array_json}${sep}\"$(json_escape "$strategy")\""
        sep=","
    done
    if [ -z "$sep" ]; then
        safe_array_json='["merge","skip"]'
    else
        safe_array_json="${safe_array_json}]"
    fi

    if [ ! -f "$installer_path" ] || [ ! -x "$installer_path" ]; then
        status="missing"
        description="Installer missing or not executable: $installer_script"
        APPLY_ERROR=$((APPLY_ERROR + 1))
        installer_result="error"
    elif [ -z "$effective_strategy" ]; then
        status="needs_strategy"
        needs_strategy="true"
        description="Strategy required for installer-backed capability. Use a strategy allowed by that capability manifest."
        APPLY_STRATEGY_REQUIRED=$((APPLY_STRATEGY_REQUIRED + 1))
        installer_result="needs_strategy"
    else
        local allowed="false"
        for strategy in $safe_strategies; do
            strategy="$(echo "$strategy" | sed "s/^'//;s/'$//")"
            if [ "$effective_strategy" = "$strategy" ]; then
                allowed="true"
                break
            fi
        done

        if [ "$allowed" != "true" ]; then
            status="needs_strategy"
            needs_strategy="true"
            description="Unsafe strategy '$effective_strategy'. Allowed: ${safe_strategies}"
            APPLY_STRATEGY_REQUIRED=$((APPLY_STRATEGY_REQUIRED + 1))
            installer_result="needs_strategy"
        else
            local installer_output installer_rc
            set +e
            installer_output="$(DAYU_HARNESS_CAPABILITY="$cap_id" "$installer_path" "$TARGET" --apply "$effective_strategy" 2>&1)"
            installer_rc=$?
            set -e

            if [ "$installer_rc" -ne 0 ]; then
                status="error"
                description="Installer failed with code $installer_rc."
                APPLY_ERROR=$((APPLY_ERROR + 1))
                installer_result="error"
            else
                status="$(echo "$installer_output" | jq -r '.status // "ok"' 2>/dev/null || echo "ok")"
                action="$(echo "$installer_output" | jq -r '.action // ""' 2>/dev/null || echo "")"
                description="$(echo "$installer_output" | jq -r '.description_nl // .detail // "installer completed"' 2>/dev/null || echo "$installer_output")"
                if [ "$status" = "partial" ]; then
                    APPLY_PARTIAL=$((APPLY_PARTIAL + 1))
                    installer_result="partial"
                elif [ "$status" = "ok" ] || [ "$status" = "needs_strategy" ] || [ "$status" = "skip" ] || [ "$status" = "clean" ]; then
                    if [ "$status" = "needs_strategy" ]; then
                        APPLY_STRATEGY_REQUIRED=$((APPLY_STRATEGY_REQUIRED + 1))
                    elif [ "$action" = "skip" ]; then
                        APPLY_SKIPPED=$((APPLY_SKIPPED + 1))
                    else
                        APPLY_INSTALLED=$((APPLY_INSTALLED + 1))
                    fi
                    installer_result="$status"
                else
                    status="error"
                    APPLY_ERROR=$((APPLY_ERROR + 1))
                    installer_result="error"
                fi
            fi
        fi
    fi

    APPLY_ITEMS+=( "{\"kind\":\"installer\",\"script\":\"$(json_escape "$installer_script")\",\"capability\":\"$(json_escape "$cap_id")\",\"status\":\"$(json_escape "$status")\",\"safe_strategies\":${safe_array_json},\"action\":\"$(json_escape "$action")\",\"effective_strategy\":\"$(json_escape "$effective_strategy")\",\"needs_strategy\":${needs_strategy},\"installer_result\":\"$(json_escape "$installer_result")\",\"description_nl\":\"$(json_escape "$description")\"}" )
}

build_selected_list_summary() {
    local arr=("$@")
    local out=""
    local i
    for i in "${arr[@]}"; do
        if [ -z "$out" ]; then
            out="$i"
        else
            out="$out, $i"
        fi
    done
    echo "$out"
}

run_environment_gate() {
    local mode="$1"
    shift
    local capabilities
    capabilities="$(build_selected_list_summary "$@")"

    if [ ! -f "$ENVIRONMENT_SCRIPT" ] || [ ! -x "$ENVIRONMENT_SCRIPT" ]; then
        echo '{"status":"error","description_nl":"Environment preflight script is missing or not executable."}'
        return 0
    fi

    bash "$ENVIRONMENT_SCRIPT" "$TARGET" "--$mode" --capabilities "$capabilities"
}

json_payload_from_output() {
    awk 'BEGIN {emit=0} /^[[:space:]]*\{/ {emit=1} emit {print}'
}

render_dayu_issue_body() {
    local summary="$1"
    local background="${2:-}"
    local formatter="$TARGET/docs/harness/sensors/scripts/dayu-format.mjs"
    local rendered formatter_rc

    if [ -f "$formatter" ] && command -v node >/dev/null 2>&1; then
        set +e
        rendered="$(node "$formatter" issue-body --summary "$summary" --background "$background" 2>/dev/null)"
        formatter_rc=$?
        set -e
        if [ "$formatter_rc" -eq 0 ] && [ -n "$rendered" ]; then
            printf '%s\n' "$rendered"
            return 0
        fi
    fi

    cat <<EOF
## Summary

- $summary

## Background

- $background
EOF
}

render_dayu_pr_body() {
    local issue="$1"
    local summary="$2"
    local implementation="$3"
    local command_one="$4"
    local command_two="${5:-}"
    local formatter="$TARGET/docs/harness/sensors/scripts/dayu-format.mjs"
    local rendered formatter_rc

    if [ -f "$formatter" ] && command -v node >/dev/null 2>&1; then
        set +e
        if [ -n "$command_two" ]; then
            rendered="$(node "$formatter" pr-body --summary "$summary" --implementation "$implementation" --test-command "$command_one" --test-command "$command_two" --issue "$issue" --final yes 2>/dev/null)"
        else
            rendered="$(node "$formatter" pr-body --summary "$summary" --implementation "$implementation" --test-command "$command_one" --issue "$issue" --final yes 2>/dev/null)"
        fi
        formatter_rc=$?
        set -e
        if [ "$formatter_rc" -eq 0 ] && [ -n "$rendered" ]; then
            printf '%s\n' "$rendered"
            return 0
        fi
    fi

    cat <<EOF
## Summary
<!-- dayu-harness:summary -->

- $summary

## Implementation notes
<!-- dayu-harness:implementation-notes -->

- $implementation

## Test plan
<!-- dayu-harness:test-plan -->

- [x] \`$command_one\`
EOF
    if [ -n "$command_two" ]; then
        printf -- '- [x] `%s`\n' "$command_two"
    fi
    cat <<EOF

Final PR: yes
Closes #$issue
EOF
}

run_capability_smoke_checks() {
    local items=()
    local failed=0
    local partial=0
    local cap_id manifest_path path missing_paths all_paths path_count
    local status desc tmp_file body_file event_file input_file command_output command_rc body event_body

    add_smoke_item() {
        local capability="$1"
        local name="$2"
        local item_status="$3"
        local item_desc="$4"
        items+=( "{\"capability\":\"$(json_escape "$capability")\",\"name\":\"$(json_escape "$name")\",\"status\":\"$(json_escape "$item_status")\",\"description_nl\":\"$(json_escape "$item_desc")\"}" )
        case "$item_status" in
            failed)
                failed=$((failed + 1))
                ;;
            partial|skipped)
                partial=$((partial + 1))
                ;;
        esac
    }

    for cap_id in "$@"; do
        manifest_path="$(manifest_path_for_id "$cap_id" 2>/dev/null || true)"
        if [ -z "$manifest_path" ] || [ ! -f "$manifest_path" ]; then
            add_smoke_item "$cap_id" "manifest-files" "failed" "找不到 capability manifest，无法验证部署文件。"
            continue
        fi

        all_paths="$(jq -r '(.template_files // [])[]?.dst, (.asset_files // [])[]?.dst' "$manifest_path" 2>/dev/null | sed '/^$/d' || true)"
        path_count="$(printf '%s\n' "$all_paths" | sed '/^$/d' | wc -l | tr -d ' ')"
        missing_paths=""
        while IFS= read -r path; do
            [ -z "$path" ] && continue
            if [ ! -e "$TARGET/$path" ]; then
                if [ -n "$missing_paths" ]; then
                    missing_paths+=", "
                fi
                missing_paths+="$path"
            fi
        done < <(printf '%s\n' "$all_paths")

        if [ -n "$missing_paths" ]; then
            add_smoke_item "$cap_id" "manifest-files" "failed" "部署文件缺失：$missing_paths。"
        elif [ "$path_count" -gt 0 ]; then
            add_smoke_item "$cap_id" "manifest-files" "passed" "已验证 ${path_count} 个 manifest 声明文件存在。"
        else
            add_smoke_item "$cap_id" "manifest-files" "passed" "该能力无静态部署文件，跳过文件存在性检查。"
        fi
    done

    if selected_has_capability "core" "$@"; then
        if [ -x "$TARGET/docs/harness/sensors/scripts/dayu-format.mjs" ] && grep -Fq 'case "pr-body"' "$TARGET/docs/harness/sensors/scripts/dayu-format.mjs" 2>/dev/null; then
            add_smoke_item "core" "fixed-format-renderer" "passed" "固定格式内容 renderer 已部署且包含 PR body 模式。"
        else
            add_smoke_item "core" "fixed-format-renderer" "failed" "固定格式内容 renderer 缺失、不可执行或不完整。"
        fi
    fi

    if selected_has_capability "project.gitignore" "$@"; then
        if [ -f "$TARGET/.gitignore" ] && grep -Fq "Dayu Harness local exclusions" "$TARGET/.gitignore" 2>/dev/null && grep -Fxq ".claude/" "$TARGET/.gitignore" 2>/dev/null; then
            add_smoke_item "project.gitignore" "gitignore-rules" "passed" ".gitignore 已存在并包含 Dayu Harness 本地排除段。"
        elif [ -f "$TARGET/.gitignore" ]; then
            add_smoke_item "project.gitignore" "gitignore-rules" "failed" ".gitignore 已存在但缺少 Dayu Harness 本地排除段。"
        else
            add_smoke_item "project.gitignore" "gitignore-rules" "skipped" ".gitignore 未安装；可能是 installer strategy=skip。"
        fi
    fi

    if selected_has_capability "git.commit-format" "$@"; then
        if ! command -v npx >/dev/null 2>&1; then
            add_smoke_item "git.commit-format" "commitlint-cli" "failed" "缺少 npx，无法验证 commitlint CLI。"
        else
            set +e
            (cd "$TARGET" && npx --no-install commitlint --version >/dev/null 2>&1)
            command_rc=$?
            set -e
            if [ "$command_rc" -eq 0 ]; then
                add_smoke_item "git.commit-format" "commitlint-cli" "passed" "commitlint CLI 可在目标项目本地解析。"
            else
                add_smoke_item "git.commit-format" "commitlint-cli" "failed" "commitlint CLI 无法在目标项目本地解析。"
            fi
        fi

        if [ ! -f "$TARGET/.husky/commit-msg" ]; then
            add_smoke_item "git.commit-format" "commit-msg-hook" "skipped" "commit-msg hook 未安装；可能是 installer strategy=skip。"
        elif ! grep -Fq "commitlint" "$TARGET/.husky/commit-msg" 2>/dev/null; then
            add_smoke_item "git.commit-format" "commit-msg-hook" "failed" "commit-msg hook 未包含 commitlint 校验片段。"
        else
            tmp_file="$(make_writable_tmpfile "dayu-commit-msg")"
            printf '%s\n' "test: verify dayu harness commit hook" > "$tmp_file"
            set +e
            (cd "$TARGET" && bash ".husky/commit-msg" "$tmp_file" >/dev/null 2>&1)
            command_rc=$?
            set -e
            rm -f "$tmp_file"
            if [ "$command_rc" -eq 0 ]; then
                add_smoke_item "git.commit-format" "commit-msg-hook" "passed" "commit-msg hook 接受确定性生成的 Conventional Commit 消息。"
            else
                add_smoke_item "git.commit-format" "commit-msg-hook" "failed" "commit-msg hook 未接受有效 Conventional Commit 消息。"
            fi

            tmp_file="$(make_writable_tmpfile "dayu-commit-msg-bad")"
            printf '%s\n' "bad commit message" > "$tmp_file"
            set +e
            command_output="$(cd "$TARGET" && bash ".husky/commit-msg" "$tmp_file" 2>&1)"
            command_rc=$?
            set -e
            rm -f "$tmp_file"
            if [ "$command_rc" -ne 0 ] && printf '%s' "$command_output" | grep -Fq "Conventional Commits"; then
                add_smoke_item "git.commit-format" "commit-msg-hook-rejects-invalid" "passed" "commit-msg hook 会拒绝非 Conventional Commit 消息。"
            else
                add_smoke_item "git.commit-format" "commit-msg-hook-rejects-invalid" "failed" "commit-msg hook 未按预期拒绝无效提交消息。"
            fi
        fi
    fi

    if selected_has_capability "quality.node-tooling" "$@"; then
        if [ ! -f "$TARGET/eslint.config.cjs" ] || [ ! -f "$TARGET/.prettierrc" ] || [ ! -f "$TARGET/.lintstagedrc.json" ]; then
            add_smoke_item "quality.node-tooling" "tooling-configs" "failed" "ESLint、Prettier 或 lint-staged 配置缺失。"
        elif ! command -v npx >/dev/null 2>&1; then
            add_smoke_item "quality.node-tooling" "tooling-cli" "failed" "缺少 npx，无法验证本地 linter/formatter CLI。"
        else
            set +e
            (cd "$TARGET" && npx --no-install eslint --version >/dev/null 2>&1 && npx --no-install prettier --version >/dev/null 2>&1 && npx --no-install lint-staged --version >/dev/null 2>&1)
            command_rc=$?
            set -e
            if [ "$command_rc" -eq 0 ]; then
                add_smoke_item "quality.node-tooling" "tooling-cli" "passed" "ESLint、Prettier 与 lint-staged CLI 可在目标项目本地解析。"
            else
                add_smoke_item "quality.node-tooling" "tooling-cli" "failed" "ESLint、Prettier 或 lint-staged CLI 无法在目标项目本地解析。"
            fi
        fi

        if [ ! -f "$TARGET/.husky/pre-commit" ]; then
            add_smoke_item "quality.node-tooling" "pre-commit-hook" "skipped" "pre-commit hook 未安装；可能是 installer strategy=skip。"
        elif grep -Fq "lint-staged" "$TARGET/.husky/pre-commit" 2>/dev/null; then
            add_smoke_item "quality.node-tooling" "pre-commit-hook" "passed" "pre-commit hook 已包含 lint-staged 执行片段。"
        else
            add_smoke_item "quality.node-tooling" "pre-commit-hook" "failed" "pre-commit hook 未包含 lint-staged 执行片段。"
        fi
    fi

    if selected_has_capability "github.branch-protection" "$@"; then
        if [ ! -f "$TARGET/.husky/pre-push" ]; then
            add_smoke_item "github.branch-protection" "pre-push-default-branch" "skipped" "pre-push hook 未安装；可能是 installer strategy=skip。"
        else
            input_file="$(make_writable_tmpfile "dayu-pre-push-branch")"
            printf '%s\n' "refs/heads/dayu-smoke 1111111111111111111111111111111111111111 refs/heads/$DEFAULT_BRANCH 2222222222222222222222222222222222222222" > "$input_file"
            set +e
            command_output="$(cd "$TARGET" && DAYU_HARNESS_PRE_PUSH_INPUT="$input_file" bash ".husky/pre-push" 2>&1)"
            command_rc=$?
            set -e
            rm -f "$input_file"
            if [ "$command_rc" -ne 0 ] && printf '%s' "$command_output" | grep -Fq "direct push"; then
                add_smoke_item "github.branch-protection" "pre-push-default-branch" "passed" "pre-push hook 会拒绝直接推送默认分支。"
            else
                add_smoke_item "github.branch-protection" "pre-push-default-branch" "failed" "pre-push hook 未按预期拒绝默认分支直接推送。"
            fi

            input_file="$(make_writable_tmpfile "dayu-pre-push-feature")"
            printf '%s\n' "refs/heads/dayu-smoke 1111111111111111111111111111111111111111 refs/heads/dayu-smoke 0000000000000000000000000000000000000000" > "$input_file"
            set +e
            command_output="$(cd "$TARGET" && DAYU_HARNESS_PRE_PUSH_INPUT="$input_file" bash ".husky/pre-push" 2>&1)"
            command_rc=$?
            set -e
            rm -f "$input_file"
            if [ "$command_rc" -eq 0 ]; then
                add_smoke_item "github.branch-protection" "pre-push-feature-branch" "passed" "pre-push hook 允许推送普通功能分支。"
            else
                add_smoke_item "github.branch-protection" "pre-push-feature-branch" "failed" "pre-push hook 错误拦截了普通功能分支推送。"
            fi
        fi
    fi

    if selected_has_capability "release.versioning" "$@"; then
        if [ ! -f "$TARGET/.husky/pre-push" ]; then
            add_smoke_item "release.versioning" "pre-push-release-tag" "skipped" "pre-push hook 未安装；可能是 installer strategy=skip。"
        else
            input_file="$(make_writable_tmpfile "dayu-pre-push-tag")"
            printf '%s\n' "refs/tags/v0.1.0 1111111111111111111111111111111111111111 refs/tags/v0.1.0 2222222222222222222222222222222222222222" > "$input_file"
            set +e
            command_output="$(cd "$TARGET" && DAYU_HARNESS_PRE_PUSH_INPUT="$input_file" bash ".husky/pre-push" 2>&1)"
            command_rc=$?
            set -e
            rm -f "$input_file"
            if [ "$command_rc" -ne 0 ] && printf '%s' "$command_output" | grep -Fq "release tag"; then
                add_smoke_item "release.versioning" "pre-push-release-tag" "passed" "pre-push hook 会拒绝覆盖 release tag。"
            else
                add_smoke_item "release.versioning" "pre-push-release-tag" "failed" "pre-push hook 未按预期拒绝覆盖 release tag。"
            fi

            input_file="$(make_writable_tmpfile "dayu-pre-push-new-tag")"
            printf '%s\n' "refs/tags/v9.9.9 1111111111111111111111111111111111111111 refs/tags/v9.9.9 0000000000000000000000000000000000000000" > "$input_file"
            set +e
            command_output="$(cd "$TARGET" && DAYU_HARNESS_PRE_PUSH_INPUT="$input_file" bash ".husky/pre-push" 2>&1)"
            command_rc=$?
            set -e
            rm -f "$input_file"
            if [ "$command_rc" -eq 0 ]; then
                add_smoke_item "release.versioning" "pre-push-new-release-tag" "passed" "pre-push hook 允许创建新的 release tag。"
            else
                add_smoke_item "release.versioning" "pre-push-new-release-tag" "failed" "pre-push hook 错误拦截了新的 release tag。"
            fi
        fi
    fi

    if selected_has_capability "github.pr" "$@"; then
        if [ ! -f "$TARGET/.github/scripts/pr_body_structure.py" ]; then
            add_smoke_item "github.pr" "pr-body-validator" "failed" "PR body validator 缺失。"
        else
            body_file="$(make_writable_tmpfile "dayu-pr-body")"
            render_dayu_pr_body "1" "Verify deterministic PR body rendering." "Render and validate a Dayu Harness PR body without model free-form text." "docs/harness/sensors/scripts/validate.sh --json ." > "$body_file"
            set +e
            python3 "$TARGET/.github/scripts/pr_body_structure.py" < "$body_file" >/dev/null 2>&1
            command_rc=$?
            set -e
            rm -f "$body_file"
            if [ "$command_rc" -eq 0 ]; then
                add_smoke_item "github.pr" "pr-body-validator" "passed" "确定性生成的 PR body 可通过 PR 结构校验。"
            else
                add_smoke_item "github.pr" "pr-body-validator" "failed" "确定性生成的 PR body 未通过 PR 结构校验。"
            fi

            body_file="$(make_writable_tmpfile "dayu-pr-body-bad")"
            printf '%s\n\n%s\n' "## Summary" "- Missing required sections and issue trailer." > "$body_file"
            set +e
            python3 "$TARGET/.github/scripts/pr_body_structure.py" < "$body_file" >/dev/null 2>&1
            command_rc=$?
            set -e
            rm -f "$body_file"
            if [ "$command_rc" -ne 0 ]; then
                add_smoke_item "github.pr" "pr-body-validator-rejects-invalid" "passed" "PR body validator 会拒绝缺少必需结构的正文。"
            else
                add_smoke_item "github.pr" "pr-body-validator-rejects-invalid" "failed" "PR body validator 未拒绝无效 PR 正文。"
            fi
        fi
    fi

    if selected_has_capability "github.issue" "$@"; then
        if [ ! -f "$TARGET/.github/scripts/issue_depends_on.py" ]; then
            add_smoke_item "github.issue" "issue-body-validator" "failed" "Issue depends-on validator 缺失。"
        else
            body="$(render_dayu_issue_body "Verify deterministic issue body rendering." "Render and validate a Dayu Harness issue body without model free-form text.")"
            event_file="$(make_writable_tmpfile "dayu-issue-event")"
            jq -n --arg body "$body" '{issue:{body:$body}}' > "$event_file"
            set +e
            python3 "$TARGET/.github/scripts/issue_depends_on.py" "$event_file" >/dev/null 2>&1
            command_rc=$?
            set -e
            rm -f "$event_file"
            if [ "$command_rc" -eq 0 ]; then
                add_smoke_item "github.issue" "issue-body-validator" "passed" "确定性生成的 Issue body 可通过 Issue 依赖格式校验。"
            else
                add_smoke_item "github.issue" "issue-body-validator" "failed" "确定性生成的 Issue body 未通过 Issue 依赖格式校验。"
            fi

            body="$(printf '## Summary\n\n- Invalid depends-on trailer.\n\nDepends on #1\n')"
            event_file="$(make_writable_tmpfile "dayu-issue-event-bad")"
            jq -n --arg body "$body" '{issue:{body:$body}}' > "$event_file"
            set +e
            python3 "$TARGET/.github/scripts/issue_depends_on.py" "$event_file" >/dev/null 2>&1
            command_rc=$?
            set -e
            rm -f "$event_file"
            if [ "$command_rc" -ne 0 ]; then
                add_smoke_item "github.issue" "issue-body-validator-rejects-invalid" "passed" "Issue depends-on validator 会拒绝格式错误的依赖行。"
            else
                add_smoke_item "github.issue" "issue-body-validator-rejects-invalid" "failed" "Issue depends-on validator 未拒绝格式错误的依赖行。"
            fi
        fi
    fi

    if selected_has_capability "quality.tdd" "$@"; then
        if [ -f "$TARGET/.github/scripts/pr_tdd_check.py" ] && [ -f "$TARGET/.github/dayu-harness/pr-tdd-policy.json" ]; then
            set +e
            python3 "$TARGET/.github/scripts/pr_tdd_check.py" "$TARGET/.github/dayu-harness/pr-tdd-policy.json" --validate-policy-only >/dev/null 2>&1
            command_rc=$?
            set -e
            if [ "$command_rc" -eq 0 ]; then
                add_smoke_item "quality.tdd" "policy-validator" "passed" "TDD policy 文件可被 checker 解析。"
            else
                add_smoke_item "quality.tdd" "policy-validator" "failed" "TDD policy 文件未通过 checker 解析。"
            fi

            tmp_file="$(make_writable_tmpfile "dayu-tdd-policy-bad")"
            printf '%s\n' '{"impl_patterns":"src/.*"}' > "$tmp_file"
            set +e
            python3 "$TARGET/.github/scripts/pr_tdd_check.py" "$tmp_file" --validate-policy-only >/dev/null 2>&1
            command_rc=$?
            set -e
            rm -f "$tmp_file"
            if [ "$command_rc" -ne 0 ]; then
                add_smoke_item "quality.tdd" "policy-validator-rejects-invalid" "passed" "TDD policy checker 会拒绝类型错误的策略文件。"
            else
                add_smoke_item "quality.tdd" "policy-validator-rejects-invalid" "failed" "TDD policy checker 未拒绝类型错误的策略文件。"
            fi
        else
            add_smoke_item "quality.tdd" "policy-validator" "failed" "TDD checker 或 policy 文件缺失。"
        fi
    fi

    if selected_has_capability "github.release-please" "$@"; then
        if [ -f "$TARGET/.github/scripts/release_please_policy.py" ] && [ -f "$TARGET/.github/release-please-policy.json" ]; then
            set +e
            python3 "$TARGET/.github/scripts/release_please_policy.py" "$TARGET/.github/release-please-policy.json" "$TARGET" >/dev/null 2>&1
            command_rc=$?
            set -e
            if [ "$command_rc" -eq 0 ]; then
                add_smoke_item "github.release-please" "release-policy-validator" "passed" "release-please policy 与目标项目文件通过本地校验。"
            else
                add_smoke_item "github.release-please" "release-policy-validator" "failed" "release-please policy 本地校验失败。"
            fi

            tmp_file="$(make_writable_tmpfile "dayu-release-policy-bad")"
            printf '%s\n' '{}' > "$tmp_file"
            set +e
            python3 "$TARGET/.github/scripts/release_please_policy.py" "$tmp_file" "$TARGET" >/dev/null 2>&1
            command_rc=$?
            set -e
            rm -f "$tmp_file"
            if [ "$command_rc" -ne 0 ]; then
                add_smoke_item "github.release-please" "release-policy-validator-rejects-invalid" "passed" "release-please policy checker 会拒绝缺少必需字段的策略文件。"
            else
                add_smoke_item "github.release-please" "release-policy-validator-rejects-invalid" "failed" "release-please policy checker 未拒绝缺少必需字段的策略文件。"
            fi
        else
            add_smoke_item "github.release-please" "release-policy-validator" "failed" "release-please policy 脚本或策略文件缺失。"
        fi
    fi

    status="passed"
    desc="已对所有已选择能力执行部署文件与关键行为 smoke 检查。"
    if [ "$failed" -gt 0 ]; then
        status="failed"
        desc="能力 smoke 检查存在 ${failed} 个失败项。"
    elif [ "$partial" -gt 0 ]; then
        status="partial"
        desc="能力 smoke 检查存在 ${partial} 个跳过或部分项。"
    fi

    printf '{"status":"%s","items":[%s],"description_nl":"%s"}' \
        "$status" \
        "$(join_json "${items[@]}")" \
        "$(json_escape "$desc")"
}

run_post_apply_checks() {
    local check_name rel_path fallback_path script_path check_output check_rc payload desc status
    local items=()
    local failed=0
    local skipped=0
    local partial=0
    POST_VALIDATE_STATUS="skipped"
    POST_VALIDATE_DESC=""

    run_one_check() {
        check_name="$1"
        rel_path="$2"
        fallback_path="$3"
        script_path="$TARGET/$rel_path"
        if [ ! -f "$script_path" ]; then
            script_path="$fallback_path"
        fi

        if [ ! -f "$script_path" ]; then
            skipped=$((skipped + 1))
            status="skipped"
            desc="${rel_path} is missing."
            items+=( "{\"name\":\"$(json_escape "$check_name")\",\"script\":\"$(json_escape "$rel_path")\",\"status\":\"$status\",\"exit_code\":0,\"description_nl\":\"$(json_escape "$desc")\"}" )
            return 0
        fi

        set +e
        check_output="$(bash "$script_path" --json "$TARGET" 2>&1)"
        check_rc=$?
        set -e
        payload="$(printf '%s\n' "$check_output" | json_payload_from_output)"
        desc="$(printf '%s' "$payload" | jq -r '.description_nl // .summary // empty' 2>/dev/null || true)"
        if [ -z "$desc" ]; then
            desc="$(printf '%s\n' "$check_output" | sed -n '1,4p' | tr '\n' ' ')"
        fi

        if [ "$check_rc" -eq 0 ]; then
            status="passed"
        else
            status="failed"
            failed=$((failed + 1))
        fi

        if [ "$check_name" = "validate" ]; then
            POST_VALIDATE_STATUS="$status"
            POST_VALIDATE_DESC="$desc"
        fi

        items+=( "{\"name\":\"$(json_escape "$check_name")\",\"script\":\"$(json_escape "$rel_path")\",\"status\":\"$status\",\"exit_code\":$check_rc,\"description_nl\":\"$(json_escape "$desc")\"}" )
    }

    run_one_check "validate" "docs/harness/sensors/scripts/validate.sh" "$SKILL_DIR/templates/docs/harness/sensors/scripts/validate.sh"
    run_one_check "audit" "docs/harness/sensors/scripts/audit.sh" "$SKILL_DIR/templates/docs/harness/sensors/scripts/audit.sh"
    run_one_check "check-consistency" "docs/harness/sensors/scripts/check-consistency.sh" "$SKILL_DIR/templates/docs/harness/sensors/scripts/check-consistency.sh"

    payload="$(run_capability_smoke_checks "$@")"
    status="$(printf '%s' "$payload" | jq -r '.status // "failed"' 2>/dev/null || echo "failed")"
    desc="$(printf '%s' "$payload" | jq -r '.description_nl // empty' 2>/dev/null || true)"
    [ -n "$desc" ] || desc="Capability smoke checks completed."
    case "$status" in
        passed)
            ;;
        partial)
            partial=$((partial + 1))
            ;;
        *)
            status="failed"
            failed=$((failed + 1))
            ;;
    esac
    items+=( "{\"name\":\"capability-smoke\",\"script\":\"builtin:capability-smoke\",\"status\":\"$status\",\"exit_code\":0,\"description_nl\":\"$(json_escape "$desc")\",\"details\":$payload}" )

    local overall="passed"
    local description="部署后 validate、audit、check-consistency 与 capability-smoke 均通过。"
    if [ "$failed" -gt 0 ]; then
        overall="failed"
        description="部署后验证存在 ${failed} 个失败项。"
    elif [ "$skipped" -gt 0 ] || [ "$partial" -gt 0 ]; then
        overall="partial"
        description="部署后验证有 ${skipped} 个跳过项与 ${partial} 个部分项。"
    fi

    printf '{"status":"%s","checks":[%s],"description_nl":"%s"}' \
        "$overall" \
        "$(join_json "${items[@]}")" \
        "$(json_escape "$description")"
}

github_e2e_result_json() {
    local status="$1"
    local desc="$2"
    local issue="${3:-}"
    local pr="${4:-}"
    local branch="${5:-}"
    local extra=""
    [ -n "$issue" ] && extra+=",\"issue\":\"$(json_escape "$issue")\""
    [ -n "$pr" ] && extra+=",\"pull_request\":\"$(json_escape "$pr")\""
    [ -n "$branch" ] && extra+=",\"branch\":\"$(json_escape "$branch")\""
    printf '{"status":"%s","description_nl":"%s"%s}' \
        "$(json_escape "$status")" \
        "$(json_escape "$desc")" \
        "$extra"
}

wait_github_workflow_success() {
    local repo="$1"
    local workflow="$2"
    local head_sha="$3"
    local event_filter="$4"
    local created_after="${5:-}"
    local timeout="${DAYU_HARNESS_GITHUB_E2E_TIMEOUT_SECONDS:-900}"
    local deadline=$((SECONDS + timeout))
    local run_json status conclusion event run_id
    GITHUB_E2E_WAIT_DESC=""

    while [ "$SECONDS" -lt "$deadline" ]; do
        run_json="$(gh run list --repo "$repo" --workflow "$workflow" --json databaseId,headSha,status,conclusion,event,createdAt --limit 30 2>/dev/null \
            | jq -c --arg sha "$head_sha" --arg event "$event_filter" --arg after "$created_after" '[.[] | select(.headSha == $sha and .event == $event and ($after == "" or .createdAt >= $after))] | .[0] // empty' 2>/dev/null || true)"
        if [ -n "$run_json" ]; then
            status="$(printf '%s' "$run_json" | jq -r '.status // empty' 2>/dev/null || true)"
            conclusion="$(printf '%s' "$run_json" | jq -r '.conclusion // empty' 2>/dev/null || true)"
            event="$(printf '%s' "$run_json" | jq -r '.event // empty' 2>/dev/null || true)"
            run_id="$(printf '%s' "$run_json" | jq -r '.databaseId // empty' 2>/dev/null || true)"
            if [ "$status" = "completed" ]; then
                if [ "$conclusion" = "success" ] && [ "$event" = "$event_filter" ]; then
                    return 0
                fi
                GITHUB_E2E_WAIT_DESC="${workflow} run ${run_id:-unknown} completed with conclusion ${conclusion:-unknown}."
                return 1
            fi
        fi
        sleep 15
    done

    GITHUB_E2E_WAIT_DESC="${workflow} did not complete for ${event_filter} within ${timeout}s."
    return 1
}

repo_from_remote_json() {
    local remote_json="$1"
    local repo=""
    repo="$(printf '%s' "$remote_json" | jq -r '.repository // empty' 2>/dev/null || true)"
    if [ -n "$repo" ]; then
        printf '%s' "$repo"
        return 0
    fi
    if git -C "$TARGET" remote get-url origin >/dev/null 2>&1; then
        git -C "$TARGET" remote get-url origin 2>/dev/null \
            | sed -nE 's#^https://github.com/([^/]+/[^/.]+)(\.git)?$#\1#p; s#^git@github.com:([^/]+/[^/.]+)(\.git)?$#\1#p' \
            | sed -n '1p'
    fi
}

remote_workflow_exists() {
    local repo="$1"
    local workflow="$2"
    [ -n "$repo" ] || return 1
    [ -n "$workflow" ] || return 1
    [ -n "$DEFAULT_BRANCH" ] || return 1
    gh api "repos/$repo/contents/.github/workflows/$workflow?ref=$DEFAULT_BRANCH" >/dev/null 2>&1
}

release_settlement_result_json() {
    local status="$1"
    local desc="$2"
    local wait_status="${3:-skipped}"
    local refresh_status="${4:-skipped}"
    local checks_json="${5:-null}"
    printf '{"status":"%s","wait_status":"%s","refresh_status":"%s","post_apply_checks":%s,"description_nl":"%s"}' \
        "$(json_escape "$status")" \
        "$(json_escape "$wait_status")" \
        "$(json_escape "$refresh_status")" \
        "$checks_json" \
        "$(json_escape "$desc")"
}

github_remote_initialization_pr_pending() {
    local apply_json="$1"
    printf '%s' "$apply_json" | jq -e '.items[]? | select((.kind == "remote" and .action == "push_init_branch" and .status == "ok") or (.kind == "pull_request" and .action == "create" and .status == "ok"))' >/dev/null 2>&1
}

wait_release_please_workflow_quiet() {
    local repo="$1"
    local started_after="$2"
    local timeout="${DAYU_HARNESS_RELEASE_SETTLE_TIMEOUT_SECONDS:-900}"
    local deadline=$((SECONDS + timeout))
    local runs_json recent_count active_count failed_count stable_count
    stable_count=0

    while [ "$SECONDS" -lt "$deadline" ]; do
        runs_json="$(gh run list --repo "$repo" --workflow "release-please.yml" --json databaseId,status,conclusion,event,createdAt --limit 30 2>/dev/null || true)"
        recent_count="$(printf '%s' "$runs_json" | jq -r --arg after "$started_after" '[.[]? | select($after == "" or .createdAt >= $after)] | length' 2>/dev/null || echo 0)"
        active_count="$(printf '%s' "$runs_json" | jq -r --arg after "$started_after" '[.[]? | select(($after == "" or .createdAt >= $after) and .status != "completed")] | length' 2>/dev/null || echo 0)"
        failed_count="$(printf '%s' "$runs_json" | jq -r --arg after "$started_after" '[.[]? | select(($after == "" or .createdAt >= $after) and .status == "completed" and (.conclusion // "") != "success")] | length' 2>/dev/null || echo 0)"

        recent_count="${recent_count:-0}"
        active_count="${active_count:-0}"
        failed_count="${failed_count:-0}"

        if [ "$recent_count" -gt 0 ] && [ "$active_count" -eq 0 ]; then
            stable_count=$((stable_count + 1))
            if [ "$stable_count" -ge 2 ]; then
                if [ "$failed_count" -gt 0 ]; then
                    return 1
                fi
                return 0
            fi
        else
            stable_count=0
        fi
        sleep 10
    done

    return 2
}

run_post_apply_checks_at_root() {
    local root="$1"
    shift || true
    local original_target="$TARGET"
    local result
    TARGET="$root"
    result="$(run_post_apply_checks "$@")"
    TARGET="$original_target"
    printf '%s' "$result"
}

make_writable_tmpdir() {
    local prefix="$1"
    local candidate candidate_abs tmpdir
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        mkdir -p "$candidate" 2>/dev/null || true
        candidate_abs="$(cd "$candidate" 2>/dev/null && pwd)" || continue
        tmpdir="$(mktemp -d "${candidate_abs%/}/${prefix}.XXXXXX" 2>/dev/null || true)"
        if [ -n "$tmpdir" ]; then
            printf '%s' "$tmpdir"
            return 0
        fi
    done < <(dayu_tmp_candidates)
    return 1
}

prepare_release_validation_root() {
    local current_branch remote_ref local_head remote_head pull_output tmp_parent tmp_worktree
    RELEASE_VALIDATION_ROOT=""
    RELEASE_VALIDATION_TMP_WORKTREE=""
    RELEASE_REFRESH_STATUS="passed"

    [ -n "$DEFAULT_BRANCH" ] || return 1
    if ! git -C "$TARGET" fetch origin "$DEFAULT_BRANCH" >/dev/null 2>&1; then
        return 1
    fi
    remote_ref="origin/$DEFAULT_BRANCH"
    if ! git -C "$TARGET" rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
        return 1
    fi
    current_branch="$(git -C "$TARGET" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    local_head="$(git -C "$TARGET" rev-parse HEAD 2>/dev/null || true)"
    remote_head="$(git -C "$TARGET" rev-parse "$remote_ref" 2>/dev/null || true)"
    [ -n "$remote_head" ] || return 1

    if [ "$current_branch" = "$DEFAULT_BRANCH" ] && [ -z "$(git -C "$TARGET" status --porcelain)" ]; then
        if [ "$local_head" = "$remote_head" ]; then
            RELEASE_VALIDATION_ROOT="$TARGET"
            return 0
        fi
        if git -C "$TARGET" merge-base --is-ancestor HEAD "$remote_ref" >/dev/null 2>&1; then
            set +e
            pull_output="$(git -C "$TARGET" pull --ff-only origin "$DEFAULT_BRANCH" 2>&1)"
            local pull_rc=$?
            set -e
            if [ "$pull_rc" -ne 0 ]; then
                printf '%s' "$pull_output" >&2
                return 1
            fi
            local_head="$(git -C "$TARGET" rev-parse HEAD 2>/dev/null || true)"
            if [ "$local_head" != "$remote_head" ]; then
                return 1
            fi
            RELEASE_VALIDATION_ROOT="$TARGET"
            return 0
        fi
    fi

    tmp_parent="$(make_writable_tmpdir "dayu-release-remote-main")"
    if [ -z "$tmp_parent" ]; then
        return 1
    fi
    rmdir "$tmp_parent" >/dev/null 2>&1 || true
    tmp_worktree="$tmp_parent"
    if ! git -C "$TARGET" worktree add --detach "$tmp_worktree" "$remote_ref" >/dev/null 2>&1; then
        rm -rf "$tmp_worktree" >/dev/null 2>&1 || true
        return 1
    fi

    RELEASE_VALIDATION_ROOT="$tmp_worktree"
    RELEASE_VALIDATION_TMP_WORKTREE="$tmp_worktree"
    RELEASE_REFRESH_STATUS="worktree"
    return 0
}

cleanup_release_validation_root() {
    if [ -n "${RELEASE_VALIDATION_TMP_WORKTREE:-}" ]; then
        git -C "$TARGET" worktree remove --force "$RELEASE_VALIDATION_TMP_WORKTREE" >/dev/null 2>&1 || rm -rf "$RELEASE_VALIDATION_TMP_WORKTREE"
        RELEASE_VALIDATION_TMP_WORKTREE=""
    fi
}

run_release_post_remote_revalidation() {
    local apply_json="$1"
    local verify_json="$2"
    local started_after="$3"
    shift 3 || true
    local repo wait_rc wait_status refresh_rc refresh_status checks_json checks_status desc

    if ! selected_has_release_please_capability "$@"; then
        release_settlement_result_json "skipped" "Release post-remote revalidation requires github.release-please."
        return 0
    fi
    if [ "$GITHUB_REMOTE_MODE" != "apply" ] && [ "$GITHUB_REMOTE_MODE" != "verify" ]; then
        release_settlement_result_json "skipped" "Release post-remote revalidation requires --github-remote apply or --github-remote verify."
        return 0
    fi
    repo="$(repo_from_remote_json "$verify_json")"
    if [ -z "$repo" ]; then
        repo="$(repo_from_remote_json "$apply_json")"
    fi
    if [ -z "$repo" ]; then
        release_settlement_result_json "failed" "Release post-remote revalidation could not resolve owner/repo."
        return 0
    fi
    if ! command -v gh >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        release_settlement_result_json "failed" "Release post-remote revalidation requires gh, git and jq."
        return 0
    fi
    if ! gh auth status >/dev/null 2>&1; then
        release_settlement_result_json "failed" "Release post-remote revalidation requires an authenticated GitHub CLI session."
        return 0
    fi
    if github_remote_initialization_pr_pending "$apply_json"; then
        release_settlement_result_json "skipped" "Release post-remote revalidation waits until the initialization PR is merged into the remote default branch." "skipped" "skipped"
        return 0
    fi
    if ! remote_workflow_exists "$repo" "release-please.yml"; then
        release_settlement_result_json "failed" "release-please.yml must exist on the remote default branch before release revalidation."
        return 0
    fi

    wait_status="skipped"
    if [ -n "$started_after" ]; then
        wait_status="passed"
        set +e
        wait_release_please_workflow_quiet "$repo" "$started_after"
        wait_rc=$?
        set -e
        if [ "$wait_rc" -ne 0 ]; then
            if [ "$wait_rc" -eq 1 ]; then
                release_settlement_result_json "failed" "release-please workflow completed with a non-success conclusion." "failed" "skipped"
            else
                release_settlement_result_json "failed" "release-please workflow did not settle before timeout." "timeout" "skipped"
            fi
            return 0
        fi
    fi

    refresh_status="passed"
    set +e
    prepare_release_validation_root
    refresh_rc=$?
    set -e
    if [ "$refresh_rc" -ne 0 ]; then
        release_settlement_result_json "failed" "Release revalidation could not fetch or prepare the remote default branch for validation." "$wait_status" "failed"
        return 0
    fi
    refresh_status="${RELEASE_REFRESH_STATUS:-passed}"

    checks_json="$(run_post_apply_checks_at_root "$RELEASE_VALIDATION_ROOT" "$@")"
    cleanup_release_validation_root
    checks_status="$(echo "$checks_json" | jq -r '.status // "skipped"' 2>/dev/null || echo "skipped")"
    if [ "$checks_status" = "failed" ]; then
        desc="Release workflow settled, but post-release validate/audit/check-consistency/capability-smoke failed."
        release_settlement_result_json "failed" "$desc" "$wait_status" "$refresh_status" "$checks_json"
    elif [ "$checks_status" = "partial" ]; then
        desc="Release workflow settled, but post-release checks had skipped items."
        release_settlement_result_json "partial" "$desc" "$wait_status" "$refresh_status" "$checks_json"
    else
        desc="Release workflow settled; refreshed default branch and post-release checks passed."
        release_settlement_result_json "passed" "$desc" "$wait_status" "$refresh_status" "$checks_json"
    fi
}

run_github_target_e2e() {
    local apply_json="$1"
    local verify_json="$2"
    shift 2 || true
    local repo original_branch issue_after issue_url issue_number issue_body main_sha branch marker_file marker_rel head_sha body_file pr_url pr_number current_branch e2e_commit_created

    if [ "$GITHUB_E2E_MODE" = "skip" ]; then
        github_e2e_result_json "skipped" "GitHub Issue/PR E2E validation was skipped by user choice."
        return 0
    fi

    if ! selected_has_github_e2e_capabilities "$@"; then
        github_e2e_result_json "skipped" "GitHub Issue/PR E2E validation requires both github.issue and github.pr."
        return 0
    fi

    if [ "$GITHUB_REMOTE_MODE" != "apply" ] && [ "$GITHUB_REMOTE_MODE" != "verify" ]; then
        github_e2e_result_json "skipped" "GitHub Issue/PR E2E validation requires --github-remote apply or --github-remote verify so workflows exist on the remote default branch."
        return 0
    fi

    if printf '%s' "$apply_json" | jq -e '.items[]? | select((.kind == "remote" and .action == "push_init_branch" and .status == "ok") or (.kind == "pull_request" and .action == "create" and .status == "ok"))' >/dev/null 2>&1; then
        github_e2e_result_json "skipped" "GitHub Issue/PR E2E validation waits until the initialization PR is merged into the default branch."
        return 0
    fi

    repo="$(repo_from_remote_json "$verify_json")"
    if [ -z "$repo" ]; then
        repo="$(repo_from_remote_json "$apply_json")"
    fi
    if [ -z "$repo" ]; then
        github_e2e_result_json "failed" "GitHub Issue/PR E2E validation could not resolve owner/repo."
        return 0
    fi

    if ! command -v gh >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        github_e2e_result_json "failed" "GitHub Issue/PR E2E validation requires gh, git and jq."
        return 0
    fi
    if ! gh auth status >/dev/null 2>&1; then
        github_e2e_result_json "failed" "GitHub Issue/PR E2E validation requires an authenticated GitHub CLI session."
        return 0
    fi
    if ! remote_workflow_exists "$repo" "issue-lint.yml" || ! remote_workflow_exists "$repo" "pr-lint.yml"; then
        github_e2e_result_json "failed" "GitHub Issue/PR E2E validation requires issue-lint.yml and pr-lint.yml to exist on the remote default branch before creating test issues or PRs."
        return 0
    fi

    original_branch="$(git -C "$TARGET" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    marker_file=""
    marker_rel=""
    body_file=""
    e2e_commit_created="false"
    restore_github_e2e_branch() {
        rm -f "${body_file:-}"
        if [ -n "${marker_rel:-}" ] && [ "$e2e_commit_created" != "true" ]; then
            git -C "$TARGET" restore --staged "$marker_rel" >/dev/null 2>&1 || true
            rm -f "$TARGET/$marker_rel"
            rmdir "$TARGET/.dayu-harness-smoke" >/dev/null 2>&1 || true
        fi
        current_branch="$(git -C "$TARGET" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        if [ -n "$original_branch" ] && [ "$current_branch" != "$original_branch" ]; then
            git -C "$TARGET" switch "$original_branch" >/dev/null 2>&1 || true
        fi
    }
    fail_github_e2e() {
        local desc="$1"
        local issue="${2:-}"
        local pr="${3:-}"
        local smoke_branch="${4:-}"
        restore_github_e2e_branch
        github_e2e_result_json "failed" "$desc" "$issue" "$pr" "$smoke_branch"
    }
    cleanup_github_e2e_remote_branch_ref() {
        local smoke_branch="$1"
        [ -n "$smoke_branch" ] || return 0

        git -C "$TARGET" fetch --prune origin >/dev/null 2>&1 || true
        if git -C "$TARGET" ls-remote --exit-code --heads origin "$smoke_branch" >/dev/null 2>&1; then
            git -C "$TARGET" push origin --delete "$smoke_branch" >/dev/null 2>&1 || return 1
            git -C "$TARGET" fetch --prune origin >/dev/null 2>&1 || true
        fi
        git -C "$TARGET" branch -dr "origin/$smoke_branch" >/dev/null 2>&1 || true
        return 0
    }

    issue_after="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    main_sha="$(git -C "$TARGET" rev-parse HEAD 2>/dev/null || true)"
    if [ -z "$main_sha" ]; then
        fail_github_e2e "GitHub Issue/PR E2E validation requires a local commit to test from."
        return 0
    fi

    issue_body="$(render_dayu_issue_body "Verify Dayu Harness Issue to PR governance after initialization." "Created by scaffold.sh post-deployment E2E validation.")"
    if ! issue_url="$(gh issue create --repo "$repo" --title "Dayu Harness Issue PR E2E verification" --body "$issue_body" 2>/dev/null)"; then
        fail_github_e2e "GitHub Issue/PR E2E validation failed to create a test issue."
        return 0
    fi
    issue_number="${issue_url##*/}"

    if ! wait_github_workflow_success "$repo" "issue-lint.yml" "$main_sha" "issues" "$issue_after"; then
        fail_github_e2e "GitHub Issue workflow E2E failed: ${GITHUB_E2E_WAIT_DESC:-unknown issue-lint result}" "$issue_url"
        return 0
    fi

    branch="dayu-harness/e2e-${issue_number}-$(date +%Y%m%d%H%M%S)"
    if ! git -C "$TARGET" switch -c "$branch" >/dev/null 2>&1; then
        fail_github_e2e "GitHub Issue/PR E2E validation failed to create a local test branch." "$issue_url" "" "$branch"
        return 0
    fi

    marker_rel=".dayu-harness-smoke/issue-${issue_number}.md"
    marker_file="$TARGET/$marker_rel"
    mkdir -p "$(dirname "$marker_file")"
    printf 'Dayu Harness GitHub E2E smoke for issue #%s\n' "$issue_number" > "$marker_file"
    if ! git -C "$TARGET" add "$marker_rel" >/dev/null 2>&1; then
        fail_github_e2e "GitHub Issue/PR E2E validation failed to stage the smoke marker." "$issue_url" "" "$branch"
        return 0
    fi
    if ! git -C "$TARGET" commit -m "test: verify dayu harness github e2e" >/dev/null 2>&1; then
        fail_github_e2e "GitHub Issue/PR E2E validation failed to create the smoke commit." "$issue_url" "" "$branch"
        return 0
    fi
    e2e_commit_created="true"
    if ! git -C "$TARGET" push -u origin "$branch" >/dev/null 2>&1; then
        fail_github_e2e "GitHub Issue/PR E2E validation failed to push the smoke branch." "$issue_url" "" "$branch"
        return 0
    fi
    head_sha="$(git -C "$TARGET" rev-parse HEAD 2>/dev/null || true)"

    body_file="$(make_writable_tmpfile "dayu-e2e-pr-body")"
    render_dayu_pr_body "$issue_number" \
      "Verify Dayu Harness GitHub Issue to PR governance after initialization." \
      "Adds a smoke marker on an isolated validation branch." \
      "gh issue view $issue_number --repo $repo" \
      "gh pr checks --repo $repo" > "$body_file"
    if ! pr_url="$(gh pr create --repo "$repo" --base "$DEFAULT_BRANCH" --head "$branch" --title "Dayu Harness GitHub E2E verification" --body-file "$body_file" 2>/dev/null)"; then
        fail_github_e2e "GitHub Issue/PR E2E validation failed to create a test PR." "$issue_url" "" "$branch"
        return 0
    fi
    rm -f "$body_file"
    body_file=""
    pr_number="${pr_url##*/}"

    if ! wait_github_workflow_success "$repo" "pr-lint.yml" "$head_sha" "pull_request"; then
        fail_github_e2e "GitHub PR workflow E2E failed: ${GITHUB_E2E_WAIT_DESC:-unknown pr-lint result}" "$issue_url" "$pr_url" "$branch"
        return 0
    fi

    if ! gh pr close "$pr_number" --repo "$repo" --comment "Dayu Harness GitHub E2E validation passed; closing this test PR without merge." --delete-branch >/dev/null 2>&1; then
        fail_github_e2e "GitHub Issue/PR E2E validation passed lint checks, but failed to close the test PR or delete the remote test branch." "$issue_url" "$pr_url" "$branch"
        return 0
    fi
    if ! gh issue close "$issue_number" --repo "$repo" --comment "Dayu Harness GitHub E2E validation passed; closing this test issue." >/dev/null 2>&1; then
        fail_github_e2e "GitHub Issue/PR E2E validation passed lint checks and closed the test PR, but failed to close the test issue." "$issue_url" "$pr_url" "$branch"
        return 0
    fi
    if ! cleanup_github_e2e_remote_branch_ref "$branch"; then
        fail_github_e2e "GitHub Issue/PR E2E validation passed lint checks, but failed to delete or prune the remote test branch ref." "$issue_url" "$pr_url" "$branch"
        return 0
    fi

    restore_github_e2e_branch
    if ! git -C "$TARGET" branch -D "$branch" >/dev/null 2>&1; then
        fail_github_e2e "GitHub Issue/PR E2E validation passed, but failed to delete the local test branch." "$issue_url" "$pr_url" "$branch"
        return 0
    fi

    github_e2e_result_json "passed" "GitHub Issue/PR E2E validation passed; test PR, test issue, test branch and local remote-tracking refs were closed, deleted or pruned without merging." "$issue_url" "$pr_url" "$branch"
}

do_dry_run() {
    local requested_ids=()
    local capability_ids=()
    local capability_jsons=()

    for id in $(resolve_request_ids); do
        requested_ids+=( "$id" )
    done
    if [ "${#requested_ids[@]}" -eq 0 ]; then
        echo "error: no capabilities requested" >&2
        exit 2
    fi

    for id in $(resolve_with_dependencies "${requested_ids[@]}"); do
        capability_ids+=( "$id" )
    done
    if [ "${#capability_ids[@]}" -eq 0 ]; then
        echo "error: no capabilities resolved" >&2
        exit 2
    fi

    local environment_json environment_status environment_desc
    environment_json="$(run_environment_gate "check" "${capability_ids[@]}" 2>&1)"
    environment_status="$(echo "$environment_json" | jq -r '.status // "error"' 2>/dev/null || echo "error")"
    environment_desc="$(echo "$environment_json" | jq -r '.description_nl // "Environment check failed."' 2>/dev/null || echo "Environment check failed.")"
    refresh_project_context "$environment_json"
    if selected_has_remote_actions "${capability_ids[@]}" || selected_has_github_e2e_capabilities "${capability_ids[@]}"; then
        GITHUB_REMOTE_JSON="$(run_github_remote check "${capability_ids[@]}")"
    fi

    DRY_FILES=0
    DRY_NEW=0
    DRY_EXISTING=0
    DRY_MISSING=0
    DRY_INST_MISSING=0

    local cap_id
    for cap_id in "${capability_ids[@]}"; do
        local manifest_path
        manifest_path="$(manifest_path_for_id "$cap_id")"

        local cap_desc cap_desc_nl cap_default dependencies_json acceptance_json installer_json remote_actions_json
        cap_desc="$(json_escape "$(jq -r '.description // empty' "$manifest_path")")"
        cap_desc_nl="$(json_escape "$(jq -r '.description_nl // empty' "$manifest_path")")"
        cap_default="$(jq -r '.default // false' "$manifest_path")"
        dependencies_json="$(jq -c '.dependencies // []' "$manifest_path")"
        acceptance_json="$(jq -c '.acceptance // []' "$manifest_path")"
        installer_json="$(jq -c '.installer // null' "$manifest_path")"
        remote_actions_json="$(manifest_remote_actions_json "$manifest_path")"

        local pre_new=$DRY_NEW
        local pre_existing=$DRY_EXISTING
        local pre_missing=$DRY_MISSING
        local pre_inst_missing=$DRY_INST_MISSING

        DRY_ITEMS=()
        collect_file_entries "$manifest_path" "template" "dry"
        collect_file_entries "$manifest_path" "asset" "dry"
        collect_installer_entry_dry "$manifest_path" "$cap_id"
        collect_repository_settings_remote_entry_dry "$cap_id"

        local cap_new=$((DRY_NEW - pre_new))
        local cap_existing=$((DRY_EXISTING - pre_existing))
        local cap_missing=$((DRY_MISSING - pre_missing))
        local cap_inst_missing=$((DRY_INST_MISSING - pre_inst_missing))

        local status="clean"
        if [ "$cap_missing" -gt 0 ] || [ "$cap_inst_missing" -gt 0 ]; then
            status="error"
        elif [ "$cap_existing" -gt 0 ]; then
            status="conflict"
        fi

        local items_json
        items_json="$(join_json "${DRY_ITEMS[@]}")"
        capability_jsons+=( "{\"id\":\"$cap_id\",\"description\":\"$cap_desc\",\"description_nl\":\"$cap_desc_nl\",\"default\":$cap_default,\"dependencies\":$dependencies_json,\"acceptance\":$acceptance_json,\"installer\":$installer_json,\"remote_actions\":$remote_actions_json,\"status\":\"$status\",\"files_total\":$((cap_new + cap_existing)),\"files_new\":$cap_new,\"files_existing\":$cap_existing,\"files_missing\":$cap_missing,\"items\":[$items_json]}" )
    done

    local top_status="clean"
    local top_desc
    if [ "$DRY_MISSING" -gt 0 ] || [ "$DRY_INST_MISSING" -gt 0 ]; then
        top_status="error"
        top_desc="Dry-run found missing source files."
    elif [ "$environment_status" != "ok" ]; then
        top_status="$environment_status"
        top_desc="$environment_desc"
    elif [ "$DRY_EXISTING" -gt 0 ]; then
        top_status="conflict"
        top_desc="Dry-run found existing files. Apply will skip existing targets unless strategy is provided."
    else
        top_desc="Dry-run is clean. ${DRY_NEW} new files, ${DRY_FILES} managed files total."
    fi

    local capabilities_json
    capabilities_json="$(join_json "${capability_jsons[@]}")"
    local summary
    summary="$(build_selected_list_summary "${capability_ids[@]}")"
    collect_managed_paths_for_apply "${capability_ids[@]}"

    cat <<JSONEOF
{
  "mode":"dry-run",
  "target":"$(json_escape "$TARGET_DISPLAY")",
  "status":"$top_status",
  "default_branch":"$(json_escape "$DEFAULT_BRANCH")",
  "project_baseline":$(project_baseline_json),
  "github_remote":${GITHUB_REMOTE_JSON},
  "remote_validation":${REMOTE_VALIDATION_JSON},
  "github_e2e":${GITHUB_E2E_JSON},
  "release_settlement":${RELEASE_SETTLEMENT_JSON},
  "environment":${environment_json},
  "capabilities":[${capabilities_json}],
  "managed_paths":$(json_array_from_lines "${MANAGED_PATHS[@]}"),
  "staging_policy":$(managed_staging_policy_json),
  "summary":"Selected capabilities: $(json_escape "$summary")",
  "description_nl":"$(json_escape "$top_desc")",
  "total_files":$DRY_FILES,
  "files_new":$DRY_NEW,
  "files_existing":$DRY_EXISTING,
  "files_missing":$DRY_MISSING,
  "capability_count":${#capability_ids[@]}
}
JSONEOF
}

do_apply() {
    local requested_ids=()
    local capability_ids=()
    local capability_jsons=()

    for id in $(resolve_request_ids); do
        requested_ids+=( "$id" )
    done
    if [ "${#requested_ids[@]}" -eq 0 ]; then
        echo "error: no capabilities requested" >&2
        exit 2
    fi

    for id in $(resolve_with_dependencies "${requested_ids[@]}"); do
        capability_ids+=( "$id" )
    done
    if [ "${#capability_ids[@]}" -eq 0 ]; then
        echo "error: no capabilities resolved" >&2
        exit 2
    fi

    local environment_json environment_status environment_desc
    environment_json="$(run_environment_gate "apply" "${capability_ids[@]}" 2>&1)"
    environment_status="$(echo "$environment_json" | jq -r '.status // "error"' 2>/dev/null || echo "error")"
    environment_desc="$(echo "$environment_json" | jq -r '.description_nl // "Environment preflight failed."' 2>/dev/null || echo "Environment preflight failed.")"
    refresh_project_context "$environment_json"
    local has_remote_actions="false"
    local has_remote_sync="false"
    if selected_has_remote_actions "${capability_ids[@]}"; then
        has_remote_actions="true"
        has_remote_sync="true"
    fi
    if selected_has_github_e2e_capabilities "${capability_ids[@]}"; then
        has_remote_sync="true"
    fi
    if [ "$has_remote_sync" = "true" ]; then
        GITHUB_REMOTE_JSON="$(run_github_remote check "${capability_ids[@]}")"
    fi
    if [ "$GITHUB_REMOTE_MODE" = "apply" ]; then
        remote_repository="$(echo "$GITHUB_REMOTE_JSON" | jq -r '.repository // empty' 2>/dev/null || true)"
        remote_check_status="$(echo "$GITHUB_REMOTE_JSON" | jq -r '.status // "error"' 2>/dev/null || echo "error")"
        if [ "$has_remote_sync" = "true" ] && [ -z "$remote_repository" ]; then
            cat <<JSONEOF
{
  "mode":"apply",
  "target":"$(json_escape "$TARGET_DISPLAY")",
  "status":"needs_user_action",
  "default_branch":"$(json_escape "$DEFAULT_BRANCH")",
  "project_baseline":$(project_baseline_json),
  "github_remote":${GITHUB_REMOTE_JSON},
  "remote_validation":${REMOTE_VALIDATION_JSON},
  "github_e2e":${GITHUB_E2E_JSON},
  "release_settlement":${RELEASE_SETTLEMENT_JSON},
  "environment":${environment_json},
  "capabilities":[],
  "summary":"GitHub remote repository was not resolved.",
  "description_nl":"启用 --github-remote apply 前必须先设置 --github-repository owner/repo、DAYU_HARNESS_GITHUB_REPOSITORY，或配置可解析的 GitHub origin；本次未写入治理文件，避免出现本地已部署但远端 E2E 被跳过的 partial 状态。",
  "applied_count":0,
  "skipped_count":0,
  "files_total":0,
  "files_new":0,
  "files_existing":0,
  "validation":"skipped",
  "validation_description_nl":"GitHub remote repository is unresolved."
}
JSONEOF
            return 0
        fi
        if [ "$has_remote_sync" = "true" ] && [ "$remote_check_status" = "needs_user_action" ] && echo "$GITHUB_REMOTE_JSON" | jq -e '.items[]? | select(.kind == "auth" or .status == "needs_user_action")' >/dev/null 2>&1; then
            cat <<JSONEOF
{
  "mode":"apply",
  "target":"$(json_escape "$TARGET_DISPLAY")",
  "status":"needs_user_action",
  "default_branch":"$(json_escape "$DEFAULT_BRANCH")",
  "project_baseline":$(project_baseline_json),
  "github_remote":${GITHUB_REMOTE_JSON},
  "remote_validation":${REMOTE_VALIDATION_JSON},
  "github_e2e":${GITHUB_E2E_JSON},
  "release_settlement":${RELEASE_SETTLEMENT_JSON},
  "environment":${environment_json},
  "capabilities":[],
  "summary":"GitHub remote preflight requires user action.",
  "description_nl":"GitHub 远端预检需要用户处理后才能执行 --github-remote apply；本次未写入治理文件，避免远端验证被跳过后误报成功。",
  "applied_count":0,
  "skipped_count":0,
  "files_total":0,
  "files_new":0,
  "files_existing":0,
  "validation":"skipped",
  "validation_description_nl":"GitHub remote preflight requires user action."
}
JSONEOF
            return 0
        fi
    fi
    if [ "$environment_status" != "ok" ]; then
        cat <<JSONEOF
{
  "mode":"apply",
  "target":"$(json_escape "$TARGET_DISPLAY")",
  "status":"$environment_status",
  "default_branch":"$(json_escape "$DEFAULT_BRANCH")",
  "project_baseline":$(project_baseline_json),
  "github_remote":${GITHUB_REMOTE_JSON},
  "remote_validation":${REMOTE_VALIDATION_JSON},
  "github_e2e":${GITHUB_E2E_JSON},
  "release_settlement":${RELEASE_SETTLEMENT_JSON},
  "environment":${environment_json},
  "capabilities":[],
  "summary":"Environment preparation blocked deployment.",
  "description_nl":"$(json_escape "$environment_desc")",
  "applied_count":0,
  "skipped_count":0,
  "files_total":0,
  "files_new":0,
  "files_existing":0,
  "validation":"skipped",
  "validation_description_nl":"Environment is incomplete."
}
JSONEOF
        return 0
    fi

    APPLY_FILES=0
    APPLY_NEW=0
    APPLY_EXISTING=0
    APPLY_SKIPPED=0
    APPLY_MISSING=0
    APPLY_ERROR=0
    APPLY_PARTIAL=0
    APPLY_INSTALLED=0
    APPLY_STRATEGY_REQUIRED=0

    local cap_id
    for cap_id in "${capability_ids[@]}"; do
        local manifest_path
        manifest_path="$(manifest_path_for_id "$cap_id")"
        local cap_desc cap_desc_nl cap_default dependencies_json acceptance_json installer_json remote_actions_json
        cap_desc="$(json_escape "$(jq -r '.description // empty' "$manifest_path")")"
        cap_desc_nl="$(json_escape "$(jq -r '.description_nl // empty' "$manifest_path")")"
        cap_default="$(jq -r '.default // false' "$manifest_path")"
        dependencies_json="$(jq -c '.dependencies // []' "$manifest_path")"
        acceptance_json="$(jq -c '.acceptance // []' "$manifest_path")"
        installer_json="$(jq -c '.installer // null' "$manifest_path")"
        remote_actions_json="$(manifest_remote_actions_json "$manifest_path")"

        local pre_new=$APPLY_NEW
        local pre_existing=$APPLY_EXISTING
        local pre_skipped=$APPLY_SKIPPED
        local pre_missing=$APPLY_MISSING
        local pre_error=$APPLY_ERROR
        local pre_partial=$APPLY_PARTIAL
        local pre_installed=$APPLY_INSTALLED
        local pre_strategy=$APPLY_STRATEGY_REQUIRED

        APPLY_ITEMS=()
        local installer_script strategy_state blocked_desc effective_strategy
        installer_script="$(jq -r '.installer.script // empty' "$manifest_path")"
        strategy_state="allowed"
        blocked_desc=""
        effective_strategy="$STRATEGY"
        if [ -n "$installer_script" ]; then
            if [ -z "$STRATEGY" ]; then
                local installer_path installer_check_output installer_check_rc installer_check_status
                installer_path="$SCRIPTS_DIR/$installer_script"
                if [ -f "$installer_path" ] && [ -x "$installer_path" ]; then
                    set +e
                    installer_check_output="$(DAYU_HARNESS_CAPABILITY="$cap_id" "$installer_path" "$TARGET" --check 2>&1)"
                    installer_check_rc=$?
                    set -e
                    installer_check_status="$(echo "$installer_check_output" | jq -r '.status // "error"' 2>/dev/null || echo "error")"
                    if [ "$installer_check_rc" -eq 0 ] && [ "$installer_check_status" = "clean" ]; then
                        effective_strategy="merge"
                    elif [ "$installer_check_rc" -eq 0 ] && [ "$installer_script" = "install-husky.sh" ] && [ "$installer_check_status" = "conflict" ]; then
                        local auto_merge_husky hook_file hook_path
                        auto_merge_husky="true"
                        while IFS= read -r hook_file; do
                            [ -z "$hook_file" ] && continue
                            hook_path="$TARGET/${hook_file#./}"
                            if [ ! -f "$hook_path" ] || ! grep -qF "hook managed by dayu-harness snippets" "$hook_path"; then
                                auto_merge_husky="false"
                                break
                            fi
                        done < <(echo "$installer_check_output" | jq -r '.items[]? | select(.exists == true) | .file' 2>/dev/null)

                        if [ "$auto_merge_husky" = "true" ]; then
                            effective_strategy="merge"
                        else
                            strategy_state="needs_strategy"
                            blocked_desc="$(echo "$installer_check_output" | jq -r '.description_nl // "Capability has an installer and existing configuration needs an explicit strategy."' 2>/dev/null || echo "Capability has an installer and existing configuration needs an explicit strategy.")"
                        fi
                    else
                        strategy_state="needs_strategy"
                        blocked_desc="$(echo "$installer_check_output" | jq -r '.description_nl // "Capability has an installer and existing configuration needs an explicit strategy."' 2>/dev/null || echo "Capability has an installer and existing configuration needs an explicit strategy.")"
                    fi
                else
                    strategy_state="needs_strategy"
                    blocked_desc="Capability has an installer, but the installer is missing or not executable."
                fi
            elif [ "$STRATEGY" = "skip" ]; then
                # A skip strategy applies to the installer-managed component
                # only. Static templates/assets in the same capability remain
                # safe to copy when the target path is new.
                effective_strategy="skip"
            else
                local allowed_strategy="false"
                local candidate
                for candidate in $(jq -r '.installer.safe_strategies[]? // empty' "$manifest_path"); do
                    if [ "$candidate" = "$STRATEGY" ]; then
                        allowed_strategy="true"
                        break
                    fi
                done
                if [ "$allowed_strategy" != "true" ]; then
                    strategy_state="needs_strategy"
                    blocked_desc="Capability strategy is not allowed by the manifest; no files were written."
                fi
            fi
        fi
        if [ "$strategy_state" = "allowed" ]; then
            collect_file_entries "$manifest_path" "template" "apply"
            collect_file_entries "$manifest_path" "asset" "apply"
            collect_installer_entry_apply "$manifest_path" "$cap_id" "$effective_strategy"
            collect_repository_settings_remote_entry_apply "$cap_id"
        else
            collect_file_entries_blocked "$manifest_path" "template" "$strategy_state" "$blocked_desc"
            collect_file_entries_blocked "$manifest_path" "asset" "$strategy_state" "$blocked_desc"
            collect_installer_entry_apply "$manifest_path" "$cap_id" "$effective_strategy"
        fi

        local cap_new=$((APPLY_NEW - pre_new))
        local cap_existing=$((APPLY_EXISTING - pre_existing))
        local cap_skipped=$((APPLY_SKIPPED - pre_skipped))
        local cap_missing=$((APPLY_MISSING - pre_missing))
        local cap_error=$((APPLY_ERROR - pre_error))
        local cap_partial=$((APPLY_PARTIAL - pre_partial))
        local cap_installed=$((APPLY_INSTALLED - pre_installed))
        local cap_strategy=$((APPLY_STRATEGY_REQUIRED - pre_strategy))

        local status="ok"
        if [ "$cap_error" -gt 0 ] || [ "$cap_missing" -gt 0 ]; then
            status="error"
        elif [ "$cap_strategy" -gt 0 ]; then
            status="needs_strategy"
        elif [ "$cap_partial" -gt 0 ] || [ "$cap_installed" -gt 0 ] || [ "$cap_skipped" -gt 0 ]; then
            status="partial"
        fi

        local items_json
        items_json="$(join_json "${APPLY_ITEMS[@]}")"
        capability_jsons+=( "{\"id\":\"$cap_id\",\"description\":\"$cap_desc\",\"description_nl\":\"$cap_desc_nl\",\"default\":$cap_default,\"dependencies\":$dependencies_json,\"acceptance\":$acceptance_json,\"installer\":$installer_json,\"remote_actions\":$remote_actions_json,\"status\":\"$status\",\"files_total\":$((cap_new + cap_existing)),\"files_new\":$cap_new,\"files_existing\":$cap_existing,\"items\":[$items_json]}" )
    done

    local overall_status="ok"
    if [ "$APPLY_ERROR" -gt 0 ] || [ "$APPLY_MISSING" -gt 0 ]; then
        overall_status="error"
    elif [ "$APPLY_STRATEGY_REQUIRED" -gt 0 ]; then
        overall_status="needs_strategy"
    elif [ "$APPLY_PARTIAL" -gt 0 ] || [ "$APPLY_SKIPPED" -gt 0 ]; then
        overall_status="partial"
    fi

    local post_apply_checks_json post_apply_status validation_status validation_desc
    post_apply_checks_json="$(run_post_apply_checks "${capability_ids[@]}")"
    post_apply_status="$(echo "$post_apply_checks_json" | jq -r '.status // "skipped"' 2>/dev/null || echo "skipped")"
    validation_status="$(echo "$post_apply_checks_json" | jq -r '.checks[]? | select(.name == "validate") | .status' 2>/dev/null | sed -n '1p')"
    validation_desc="$(echo "$post_apply_checks_json" | jq -r '.checks[]? | select(.name == "validate") | .description_nl' 2>/dev/null | sed -n '1p')"
    [ -n "$validation_status" ] || validation_status="skipped"
    if [ "$post_apply_status" = "failed" ] && [ "$overall_status" = "ok" ]; then
        overall_status="error"
    elif [ "$post_apply_status" = "partial" ] && [ "$overall_status" = "ok" ]; then
        overall_status="partial"
    fi

    collect_managed_paths_for_apply "${capability_ids[@]}"

    local git_finalization_json git_finalization_status
    git_finalization_json="$(finalize_git_after_apply "$overall_status" "$post_apply_status")"
    git_finalization_status="$(echo "$git_finalization_json" | jq -r '.status // "skipped"' 2>/dev/null || echo "error")"
    if [ "$FINALIZE_GIT" = "auto" ]; then
        if [ "$git_finalization_status" = "error" ]; then
            overall_status="error"
        elif [ "$git_finalization_status" = "needs_user_action" ] || [ "$git_finalization_status" = "needs_initialization" ]; then
            if [ "$overall_status" = "ok" ]; then
                overall_status="needs_user_action"
            fi
        fi
    fi

    local release_remote_started_at=""
    local release_settlement_status=""
    if [ "$has_remote_sync" = "true" ]; then
        case "$GITHUB_REMOTE_MODE" in
            apply)
                if [ "$overall_status" = "ok" ]; then
                    release_remote_started_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
                    GITHUB_REMOTE_JSON="$(run_github_remote apply "${capability_ids[@]}")"
                    REMOTE_VALIDATION_JSON="$(run_github_remote verify "${capability_ids[@]}")"
                else
                    GITHUB_REMOTE_JSON='{"status":"skipped","description_nl":"GitHub remote sync waits until deployment, validation, and initialization commit are successful."}'
                    REMOTE_VALIDATION_JSON='{"status":"skipped","description_nl":"Remote validation was skipped because local finalization did not complete successfully."}'
                fi
                ;;
            verify)
                if [ "$overall_status" = "ok" ]; then
                    REMOTE_VALIDATION_JSON="$(run_github_remote verify "${capability_ids[@]}")"
                else
                    REMOTE_VALIDATION_JSON='{"status":"skipped","description_nl":"Remote validation waits until deployment and local validation are successful."}'
                fi
                ;;
            skip)
                GITHUB_REMOTE_JSON='{"status":"skipped","description_nl":"GitHub remote orchestration was skipped by user choice."}'
                REMOTE_VALIDATION_JSON='{"status":"skipped","description_nl":"Remote validation was skipped by user choice."}'
                ;;
            auto|check|"")
                REMOTE_VALIDATION_JSON='{"status":"skipped","description_nl":"Remote validation requires --github-remote apply or --github-remote verify."}'
                ;;
        esac

        remote_status="$(echo "$GITHUB_REMOTE_JSON" | jq -r '.status // "skipped"' 2>/dev/null || echo "error")"
        remote_validation_status="$(echo "$REMOTE_VALIDATION_JSON" | jq -r '.status // "skipped"' 2>/dev/null || echo "error")"
        if [ "$GITHUB_REMOTE_MODE" = "apply" ] && [ "$remote_status" = "error" ]; then
            overall_status="error"
        elif [ "$GITHUB_REMOTE_MODE" = "apply" ] && [ "$remote_status" != "ok" ] && [ "$remote_status" != "skipped" ]; then
            if [ "$overall_status" = "ok" ]; then
                overall_status="partial"
            fi
        fi
        if [ "$GITHUB_REMOTE_MODE" = "verify" ] || [ "$GITHUB_REMOTE_MODE" = "apply" ]; then
            if [ "$remote_validation_status" = "error" ]; then
                overall_status="error"
            elif [ "$remote_validation_status" != "ok" ] && [ "$remote_validation_status" != "skipped" ]; then
                if [ "$overall_status" = "ok" ]; then
                    overall_status="partial"
                fi
            fi
        fi
    fi

    if selected_has_release_please_capability "${capability_ids[@]}"; then
        if [ "$overall_status" = "ok" ]; then
            RELEASE_SETTLEMENT_JSON="$(run_release_post_remote_revalidation "$GITHUB_REMOTE_JSON" "$REMOTE_VALIDATION_JSON" "$release_remote_started_at" "${capability_ids[@]}")"
            release_settlement_status="$(echo "$RELEASE_SETTLEMENT_JSON" | jq -r '.status // "skipped"' 2>/dev/null || echo "failed")"
            if [ "$release_settlement_status" = "failed" ]; then
                overall_status="error"
            elif [ "$release_settlement_status" = "partial" ] && [ "$overall_status" = "ok" ]; then
                overall_status="partial"
            fi
        else
            RELEASE_SETTLEMENT_JSON='{"status":"skipped","description_nl":"Release post-remote revalidation waits until deployment, local validation, git finalization and remote verification are successful."}'
        fi
    fi

    if selected_has_github_capabilities "${capability_ids[@]}"; then
        if [ "$overall_status" = "ok" ] || [ "$GITHUB_E2E_MODE" = "skip" ]; then
            GITHUB_E2E_JSON="$(run_github_target_e2e "$GITHUB_REMOTE_JSON" "$REMOTE_VALIDATION_JSON" "${capability_ids[@]}")"
            github_e2e_status="$(echo "$GITHUB_E2E_JSON" | jq -r '.status // "skipped"' 2>/dev/null || echo "failed")"
            if [ "$github_e2e_status" = "failed" ]; then
                overall_status="error"
            fi
        else
            GITHUB_E2E_JSON='{"status":"skipped","description_nl":"GitHub Issue/PR E2E validation waits until deployment, local validation, git finalization and remote verification are successful."}'
        fi
    fi

    local top_desc="Apply completed with status $overall_status."
    if [ "$overall_status" = "needs_strategy" ]; then
        top_desc="Apply required a strategy for installer-backed capabilities. Re-run with an allowed --strategy value."
    elif [ "$overall_status" = "needs_user_action" ]; then
        top_desc="Apply wrote and validated files, but initialization commit or sync needs user action."
    elif [ "$overall_status" = "partial" ]; then
        if [ "$STRATEGY" = "skip" ]; then
            top_desc="Apply completed with partial changes. Installer-managed components were skipped, while static files were still processed."
        else
            top_desc="Apply completed with partial changes. Existing targets were skipped by default."
        fi
    elif [ "$overall_status" = "error" ]; then
        top_desc="Apply encountered errors. Resolve conflicts and retry."
        if [ "$validation_status" = "failed" ]; then
            top_desc="Apply copied files, but final validation failed. Resolve validation errors and retry."
        fi
    fi

    local capabilities_json
    capabilities_json="$(join_json "${capability_jsons[@]}")"
    local summary
    summary="$(build_selected_list_summary "${capability_ids[@]}")"
    local applied_list
    applied_list="$(build_selected_list_summary "${capability_ids[@]}")"

    cat <<JSONEOF
{
  "mode":"apply",
  "target":"$(json_escape "$TARGET_DISPLAY")",
  "status":"$overall_status",
  "default_branch":"$(json_escape "$DEFAULT_BRANCH")",
  "project_baseline":$(project_baseline_json),
  "github_remote":${GITHUB_REMOTE_JSON},
  "remote_validation":${REMOTE_VALIDATION_JSON},
  "github_e2e":${GITHUB_E2E_JSON},
  "release_settlement":${RELEASE_SETTLEMENT_JSON},
  "environment":${environment_json},
  "capabilities":[${capabilities_json}],
  "managed_paths":$(json_array_from_lines "${MANAGED_PATHS[@]}"),
  "staging_policy":$(managed_staging_policy_json),
  "git_finalization":${git_finalization_json},
  "summary":"Applied capability set: $(json_escape "$summary")",
  "description_nl":"$(json_escape "$top_desc")",
  "applied_count":$APPLY_NEW,
  "skipped_count":$APPLY_SKIPPED,
  "files_total":$((APPLY_NEW + APPLY_EXISTING)),
  "files_new":$APPLY_NEW,
  "files_existing":$APPLY_EXISTING,
  "validation":"$(json_escape "$validation_status")",
  "validation_description_nl":"$(json_escape "$validation_desc")",
  "post_apply_checks":${post_apply_checks_json},
  "applied":"$(json_escape "$applied_list")"
}
JSONEOF
}

case "$MODE" in
    dry-run)
        do_dry_run
        ;;
    apply)
        do_apply
        ;;
    prompt)
        do_dry_run
        echo "" >&2
        echo "=== 以上为预览 (dry-run) ===" >&2
        echo "执行 scaffold.sh --apply 以实际复制文件。" >&2
        echo "或使用 --enable <ids> / --only <category> 进一步过滤。" >&2
        echo "安装器能力（含 installer）如需执行，请提供该能力允许的 --strategy。" >&2
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
