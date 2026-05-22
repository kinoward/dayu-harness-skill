#!/usr/bin/env bash
# github-remote.sh — GitHub 远端协同检查、创建与校验
# 用法：scripts/github-remote.sh <target-root> --check|--apply|--verify [--repository owner/repo] [--visibility private|public]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET=""
MODE="check"

DAYU_GITHUB_REPO="${DAYU_HARNESS_GITHUB_REPOSITORY:-}"
DAYU_GITHUB_VISIBILITY="${DAYU_HARNESS_GITHUB_VISIBILITY:-private}"
REQUESTED_DEFAULT_BRANCH="${DAYU_HARNESS_DEFAULT_BRANCH:-}"
REMOTE_ACTIONS_EXPLICIT="false"
if [ "${DAYU_HARNESS_REMOTE_ACTIONS_JSON+x}" = "x" ]; then
    REMOTE_ACTIONS_EXPLICIT="true"
    REMOTE_ACTIONS_JSON="${DAYU_HARNESS_REMOTE_ACTIONS_JSON}"
else
    REMOTE_ACTIONS_JSON="[]"
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --check|--apply|--verify)
            MODE="${1#--}"
            shift
            ;;
        --repository|--repo)
            DAYU_GITHUB_REPO="${2:-}"
            shift 2
            ;;
        --visibility)
            DAYU_GITHUB_VISIBILITY="${2:-}"
            shift 2
            ;;
        --help|-h)
            echo '{"status":"error","error":"usage: github-remote.sh <target-root> --check|--apply|--verify [--repository owner/repo] [--visibility private|public]","description_nl":"请传入目标目录、--check / --apply / --verify，可选传入 --repository owner/repo 与 --visibility private|public。"}'
            exit 2
            ;;
        *)
            if [ -z "$TARGET" ]; then
                TARGET="$1"
                shift
            else
                echo '{"status":"error","error":"only one target path is allowed","description_nl":"参数输入有误，只允许传入一个目标目录。"}'
                exit 2
            fi
            ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo '{"status":"error","error":"target root is required","description_nl":"必须提供目标仓库目录。"}'
    exit 2
fi

if ! TARGET="$(cd "$TARGET" 2>/dev/null && pwd)"; then
    echo '{"status":"error","error":"target not found","description_nl":"目标仓库目录不存在或无法访问。"}'
    exit 2
fi

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

normalize_branch_name() {
    local branch="$1"
    case "$branch" in
        ""|HEAD|null) branch="" ;;
        dayu-harness/init|dayu-harness/init-*) branch="main" ;;
    esac
    printf '%s' "$branch"
}

ensure_default_branch_fallback() {
    if [ -z "$DEFAULT_BRANCH" ]; then
        DEFAULT_BRANCH="main"
    fi
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

to_json_array() {
    local out="["
    local first="true"
    local item
    for item in "$@"; do
        [ -z "$item" ] && continue
        if [ "$first" = "false" ]; then
            out+=","
        else
            first="false"
        fi
        out+="\"$(json_escape "$item")\""
    done
    out+="]"
    printf '%s' "$out"
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

validate_repo_name() {
    local value="$1"
    [[ "$value" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]
}

extract_repo_from_remote_url() {
    local url="$1"
    local repo=""

    case "$url" in
        https://github.com/*|http://github.com/*)
            repo="${url#*github.com/}"
            ;;
        ssh://git@github.com/*)
            repo="${url#ssh://git@github.com/}"
            ;;
        git@github.com:*)
            repo="${url#git@github.com:}"
            ;;
        *)
            return 1
            ;;
    esac

    repo="${repo#/}"
    repo="${repo%.git}"
    if validate_repo_name "$repo"; then
        printf '%s' "$repo"
        return 0
    fi
    return 1
}

parse_json_array_names() {
    local payload="$1"
    local expr="$2"
    local parsed=""
    parsed="$(printf '%s' "$payload" | jq -r "$expr" 2>/dev/null | sed '/^$/d' || true)"
    printf '%s' "$parsed"
}

parse_resource_names() {
    local payload="$1"
    local collection_key="$2"
    local parsed=""
    parsed="$(printf '%s' "$payload" | jq -r --arg key "$collection_key" 'if type == "array" then .[]? elif type == "object" then (.[$key] // [])[]? else empty end | .name // empty' 2>/dev/null | sed '/^$/d' || true)"
    printf '%s' "$parsed"
}

contains_line() {
    local needle="$1"
    local lines="$2"

    while IFS= read -r line; do
        if [ "$line" = "$needle" ]; then
            return 0
        fi
    done < <(printf '%s\n' "$lines")
    return 1
}

to_json_array_from_lines() {
    local lines="$1"
    local out="["
    local first="true"
    local item

    while IFS= read -r item; do
        [ -z "$item" ] && continue
        if [ "$first" = "true" ]; then
            first="false"
        else
            out+=","
        fi
        out+="\"$(json_escape "$item")\""
    done < <(printf '%s\n' "$lines")
    out+=']'
    printf '%s' "$out"
}

add_resource_item() {
    local kind="$1"
    local status="$2"
    local required="$3"
    local present="$4"
    local missing="$5"
    local description="$6"

    ITEMS+=( "{\"kind\":\"$(json_escape "$kind")\",\"status\":\"$(json_escape "$status")\",\"required\":${required},\"present\":${present},\"missing\":${missing},\"description_nl\":\"$(json_escape "$description")\"}" )
    case "$status" in
        error)
            STATUS_ERROR=$((STATUS_ERROR + 1))
            ;;
        needs_user_action)
            STATUS_NEED_USER_ACTION=$((STATUS_NEED_USER_ACTION + 1))
            ;;
        needs_initialization)
            STATUS_NEED_INIT=$((STATUS_NEED_INIT + 1))
            ;;
        missing)
            STATUS_WARNING=$((STATUS_WARNING + 1))
            ;;
        partial)
            STATUS_WARNING=$((STATUS_WARNING + 1))
            ;;
    esac
}

add_item() {
    local json="$1"
    local status="$2"

    ITEMS+=( "$json" )
    case "$status" in
        error)
            STATUS_ERROR=$((STATUS_ERROR + 1))
            ;;
        needs_user_action)
            STATUS_NEED_USER_ACTION=$((STATUS_NEED_USER_ACTION + 1))
            ;;
        needs_initialization)
            STATUS_NEED_INIT=$((STATUS_NEED_INIT + 1))
            ;;
        missing)
            STATUS_WARNING=$((STATUS_WARNING + 1))
            ;;
        partial)
            STATUS_WARNING=$((STATUS_WARNING + 1))
            ;;
    esac
}

add_unique_array_item() {
    local value="$1"
    shift
    local existing
    [ -n "$value" ] || return 0
    for existing in "$@"; do
        [ "$existing" = "$value" ] && return 1
    done
    return 0
}

local_release_assets_present() {
    [ -f "$TARGET/.github/workflows/release-please.yml" ] || \
    [ -f "$TARGET/.github/release-please-policy.json" ] || \
    [ -f "$TARGET/release-please-config.json" ] || \
    [ -f "$TARGET/.release-please-manifest.json" ]
}

configure_required_remote_actions() {
    local action_count kind name
    action_count="$(printf '%s' "$REMOTE_ACTIONS_JSON" | jq -r 'if type == "array" then length else 0 end' 2>/dev/null || echo 0)"

    if [ "$action_count" -gt 0 ]; then
        while IFS= read -r kind; do
            case "$kind" in
                repository_settings)
                    NEED_REPOSITORY_SETTINGS="true"
                    ;;
                workflow_permissions)
                    NEED_WORKFLOW_PERMISSIONS="true"
                    ;;
            esac
        done < <(printf '%s' "$REMOTE_ACTIONS_JSON" | jq -r '.[]?.kind // empty' 2>/dev/null)

        while IFS= read -r name; do
            [ -z "$name" ] && continue
            if [ "${#REQUIRED_RULESETS[@]}" -eq 0 ] || add_unique_array_item "$name" "${REQUIRED_RULESETS[@]}"; then
                REQUIRED_RULESETS+=( "$name" )
            fi
        done < <(printf '%s' "$REMOTE_ACTIONS_JSON" | jq -r '.[]? | select(.kind == "ruleset") | .name // empty' 2>/dev/null)

        while IFS= read -r name; do
            [ -z "$name" ] && continue
            if [ "${#REQUIRED_SECRETS[@]}" -eq 0 ] || add_unique_array_item "$name" "${REQUIRED_SECRETS[@]}"; then
                REQUIRED_SECRETS+=( "$name" )
            fi
        done < <(printf '%s' "$REMOTE_ACTIONS_JSON" | jq -r '.[]? | select(.kind == "secret_check") | .name // empty' 2>/dev/null)

        while IFS= read -r name; do
            [ -z "$name" ] && continue
            if [ "${#REQUIRED_VARIABLES[@]}" -eq 0 ] || add_unique_array_item "$name" "${REQUIRED_VARIABLES[@]}"; then
                REQUIRED_VARIABLES+=( "$name" )
            fi
        done < <(printf '%s' "$REMOTE_ACTIONS_JSON" | jq -r '.[]? | select(.kind == "variable_check") | .name // empty' 2>/dev/null)
        return 0
    fi

    if [ "$REMOTE_ACTIONS_EXPLICIT" = "true" ]; then
        return 0
    fi

    [ -f "$TARGET/.github/repository/pull-request-settings.json" ] && NEED_REPOSITORY_SETTINGS="true"
    [ -f "$TARGET/.github/rulesets/protect-main.json" ] && REQUIRED_RULESETS+=( "protect-main" )
    [ -f "$TARGET/.github/rulesets/protect-tags.json" ] && REQUIRED_RULESETS+=( "protect-tags" )
    if local_release_assets_present; then
        NEED_WORKFLOW_PERMISSIONS="true"
    fi
}

describe_status() {
    local status="$1"
    local description
    local short
    case "$status" in
        ok|clean)
            description="远端编排状态正常。"
            ;;
        needs_initialization)
            description="前置环境不足，需要初始化后重试。"
            ;;
        needs_user_action)
            description="需要用户确认或登录 GitHub CLI 后继续。"
            ;;
        partial)
            description="部分操作已执行，仍有项未满足。"
            ;;
        error)
            description="远端编排执行失败，请先修正错误项。"
            ;;
        *)
            description="远端编排状态待确认。"
            ;;
    esac
    echo "$description"
}

summary_status() {
    if [ "$STATUS_ERROR" -gt 0 ]; then
        echo "error"
    elif [ "$STATUS_WARNING" -gt 0 ] && [ "$1" = "verify" ]; then
        echo "needs_user_action"
    elif [ "$STATUS_NEED_USER_ACTION" -gt 0 ]; then
        echo "needs_user_action"
    elif [ "$STATUS_NEED_INIT" -gt 0 ]; then
        echo "needs_initialization"
    else
        echo "ok"
    fi
}

emit_output() {
    local status="$1"
    local description="$2"
    local items_json
    items_json="$(join_json "${ITEMS[@]}")"

    printf '{\n'
    printf '  "status":"%s",\n' "$status"
    printf '  "repository":"%s",\n' "$(json_escape "${REPOSITORY}")"
    printf '  "default_branch":"%s",\n' "$(json_escape "${DEFAULT_BRANCH}")"
    printf '  "visibility":"%s",\n' "$(json_escape "${VISIBILITY}")"
    printf '  "items":[%s],\n' "$items_json"
    printf '  "description_nl":"%s"\n' "$(json_escape "$description")"
    printf '}\n'
}

HAS_GIT="false"
if command -v git >/dev/null 2>&1; then
    HAS_GIT="true"
fi
HAS_GH="false"
if command -v gh >/dev/null 2>&1; then
    HAS_GH="true"
fi
HAS_JQ="false"
if command -v jq >/dev/null 2>&1; then
    HAS_JQ="true"
fi

GH_AUTH_OK="false"
if [ "$HAS_GH" = "true" ]; then
    if gh auth status >/dev/null 2>&1; then
        GH_AUTH_OK="true"
    fi
fi

REPOSITORY="${DAYU_GITHUB_REPO:-}"
REPO_SOURCE=""
REPO_HAS_ORIGIN="false"
ORIGIN_URL=""
REPO_VIEW_JSON=""
REPO_FROM_ORIGIN=""
REPO_MISMATCH="false"
REMOTE_DEFAULT_BRANCH=""
REMOTE_DEFAULT_BRANCH_MISMATCH="false"
DEFAULT_BRANCH=""
VISIBILITY=""
ALLOWED_AUTO_MERGE=""
DELETE_BRANCH_ON_MERGE=""
REMOTE_SYNC_STATE="unknown"

NEED_REPOSITORY_SETTINGS="false"
NEED_WORKFLOW_PERMISSIONS="false"
REQUIRED_RULESETS=()
REQUIRED_SECRETS=()
REQUIRED_VARIABLES=()

ITEMS=()
STATUS_ERROR=0
STATUS_WARNING=0
STATUS_NEED_USER_ACTION=0
STATUS_NEED_INIT=0

if [ "$HAS_JQ" != "true" ]; then
    echo '{"status":"error","error":"jq is required","description_nl":"缺少 jq，无法读取 GitHub API 返回结构。"}'
    exit 2
fi

if [ "$HAS_GH" != "true" ]; then
    echo '{"status":"error","error":"gh is required","description_nl":"缺少 GitHub CLI（gh），无法读取或管理远端仓库。"}'
    exit 2
fi

configure_required_remote_actions

if [ "$HAS_GIT" != "true" ]; then
    STATUS_NEED_INIT=$((STATUS_NEED_INIT + 1))
    add_item '{"kind":"tool","name":"git","status":"needs_initialization","description_nl":"未安装 git，无法读取远端及进行推送。"}' "needs_initialization"
fi

if [ ! -d "$TARGET/.git" ]; then
    STATUS_NEED_INIT=$((STATUS_NEED_INIT + 1))
    add_item '{"kind":"project","name":".git","status":"needs_initialization","description_nl":"目标目录未初始化为 Git 仓库。"}' "needs_initialization"
fi

if [ "$HAS_GH" = "true" ]; then
    if [ "$GH_AUTH_OK" = "true" ]; then
        add_item '{"kind":"auth","name":"gh","status":"ok","description_nl":"GitHub CLI 已登录。"}' "ok"
    else
        add_item '{"kind":"auth","name":"gh","status":"needs_user_action","description_nl":"GitHub CLI 未登录，请先执行 gh auth login。"}' "needs_user_action"
    fi
fi

if [ "$HAS_GIT" = "true" ] && [ -d "$TARGET/.git" ]; then
    if ORIGIN_URL="$(git -C "$TARGET" remote get-url origin 2>/dev/null || true)"; then
        if [ -n "$ORIGIN_URL" ]; then
            REPO_HAS_ORIGIN="true"
            REPO_FROM_ORIGIN="$(extract_repo_from_remote_url "$ORIGIN_URL" || true)"
        fi
    fi
fi

if [ -z "$REPOSITORY" ]; then
    if [ "$REPO_HAS_ORIGIN" = "true" ]; then
        if [ -n "${REPO_FROM_ORIGIN:-}" ]; then
            REPOSITORY="$REPO_FROM_ORIGIN"
            REPO_SOURCE="origin"
            add_item '{"kind":"repository","name":"origin","status":"ok","description_nl":"已识别 origin 远端仓库。"}' "ok"
        else
            add_item '{"kind":"repository","name":"origin","status":"needs_user_action","description_nl":"origin 远端 URL 无法解析为 owner/repo。"}' "needs_user_action"
        fi
    fi
    if [ -z "$REPOSITORY" ]; then
        add_item '{"kind":"repository","name":"DAYU_HARNESS_GITHUB_REPOSITORY","status":"missing","description_nl":"未设置 DAYU_HARNESS_GITHUB_REPOSITORY，且未能从 origin 解析 GitHub 仓库。"}' "needs_initialization"
    fi
else
    if validate_repo_name "$REPOSITORY"; then
        REPO_SOURCE="env"
        add_item '{"kind":"repository","name":"DAYU_HARNESS_GITHUB_REPOSITORY","status":"ok","description_nl":"使用环境变量指定的仓库。"}' "ok"
        if [ "$REPO_HAS_ORIGIN" = "true" ]; then
            if [ -n "${REPO_FROM_ORIGIN:-}" ]; then
                if [ "$REPO_FROM_ORIGIN" = "$REPOSITORY" ]; then
                    add_item '{"kind":"repository","name":"origin","status":"ok","description_nl":"origin 与指定仓库一致。"}' "ok"
                else
                    REPO_MISMATCH="true"
                    add_item "{\"kind\":\"repository\",\"name\":\"origin\",\"status\":\"needs_user_action\",\"description_nl\":\"origin 指向 ${REPO_FROM_ORIGIN}，但 DAYU_HARNESS_GITHUB_REPOSITORY 指向 ${REPOSITORY}；为避免推送和远端设置落到不同仓库，请先统一。\"}" "needs_user_action"
                fi
            else
                add_item '{"kind":"repository","name":"origin","status":"needs_user_action","description_nl":"origin 远端 URL 无法解析为 owner/repo，无法确认是否与指定仓库一致。"}' "needs_user_action"
            fi
        fi
    else
        add_item '{"kind":"repository","name":"DAYU_HARNESS_GITHUB_REPOSITORY","status":"error","description_nl":"环境变量 DAYU_HARNESS_GITHUB_REPOSITORY 需为 owner/repo。"}' "error"
        REPOSITORY=""
    fi
fi

if [ "$GH_AUTH_OK" = "true" ] && [ -n "$REPOSITORY" ]; then
    REPO_VIEW_JSON="$(gh api "repos/$REPOSITORY" 2>/dev/null || true)"
    if [ -n "${REPO_VIEW_JSON}" ]; then
        REMOTE_DEFAULT_BRANCH="$(normalize_branch_name "$(printf '%s' "$REPO_VIEW_JSON" | jq -r '.default_branch // ""' 2>/dev/null || true)")"
        DEFAULT_BRANCH="$REMOTE_DEFAULT_BRANCH"
        VISIBILITY="$(printf '%s' "$REPO_VIEW_JSON" | jq -r '.visibility // ""' 2>/dev/null || true)"
        ALLOWED_AUTO_MERGE="$(printf '%s' "$REPO_VIEW_JSON" | jq -r '.allow_auto_merge // ""' 2>/dev/null || true)"
        DELETE_BRANCH_ON_MERGE="$(printf '%s' "$REPO_VIEW_JSON" | jq -r '.delete_branch_on_merge // ""' 2>/dev/null || true)"
    fi
fi

if [ -n "$REQUESTED_DEFAULT_BRANCH" ]; then
    DEFAULT_BRANCH="$(normalize_branch_name "$REQUESTED_DEFAULT_BRANCH")"
fi

if [ -z "$DEFAULT_BRANCH" ] && [ "$HAS_GIT" = "true" ] && [ -d "$TARGET/.git" ]; then
    if [ -n "$REPO_HAS_ORIGIN" ] && [ "$REPO_HAS_ORIGIN" = "true" ]; then
        DEFAULT_BRANCH="$(normalize_branch_name "$(git -C "$TARGET" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | awk -F/ '{print $NF}' || true)")"
    fi
    if [ -z "$DEFAULT_BRANCH" ]; then
        DEFAULT_BRANCH="$(normalize_branch_name "$(git -C "$TARGET" rev-parse --abbrev-ref HEAD 2>/dev/null || true)")"
    fi
fi
ensure_default_branch_fallback

if [ -n "$REMOTE_DEFAULT_BRANCH" ] && [ -n "$DEFAULT_BRANCH" ] && [ "$REMOTE_DEFAULT_BRANCH" != "$DEFAULT_BRANCH" ]; then
    REMOTE_DEFAULT_BRANCH_MISMATCH="true"
    add_item "{\"kind\":\"default_branch\",\"name\":\"remote\",\"status\":\"missing\",\"description_nl\":\"GitHub 远端默认分支为 ${REMOTE_DEFAULT_BRANCH}，本地治理默认分支为 ${DEFAULT_BRANCH}；--apply 会在推送后同步远端默认分支。\"}" "missing"
fi

if [ -z "$VISIBILITY" ]; then
    VISIBILITY="unknown"
fi

assess_remote_sync_state() {
    local local_ref remote_ref counts left_count right_count status detail
    REMOTE_SYNC_STATE="unknown"

    if [ "$HAS_GIT" != "true" ] || [ ! -d "$TARGET/.git" ]; then
        REMOTE_SYNC_STATE="no_git"
        add_item '{"kind":"remote_sync","status":"needs_initialization","state":"no_git","description_nl":"缺少 Git 仓库上下文，无法判断本地与远端分支关系。"}' "needs_initialization"
        return 0
    fi

    if ! git -C "$TARGET" rev-parse --verify HEAD >/dev/null 2>&1; then
        REMOTE_SYNC_STATE="no_local_commit"
        add_item '{"kind":"remote_sync","status":"needs_initialization","state":"no_local_commit","description_nl":"本地尚无提交，无法与远端分支比较。"}' "needs_initialization"
        return 0
    fi

    if ! git -C "$TARGET" remote get-url origin >/dev/null 2>&1; then
        REMOTE_SYNC_STATE="no_remote"
        add_item '{"kind":"remote_sync","status":"missing","state":"no_remote","description_nl":"尚未配置 origin，创建或绑定远端后才能比较分支关系。"}' "missing"
        return 0
    fi

    git -C "$TARGET" fetch origin "$DEFAULT_BRANCH" --quiet >/dev/null 2>&1 || true
    local_ref="HEAD"
    remote_ref="refs/remotes/origin/${DEFAULT_BRANCH}"

    if ! git -C "$TARGET" rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
        REMOTE_SYNC_STATE="remote_missing"
        add_item "{\"kind\":\"remote_sync\",\"status\":\"missing\",\"state\":\"remote_missing\",\"description_nl\":\"远端 origin/${DEFAULT_BRANCH} 不存在，允许首次推送当前默认分支。\"}" "missing"
        return 0
    fi

    counts="$(git -C "$TARGET" rev-list --left-right --count "${remote_ref}...${local_ref}" 2>/dev/null || true)"
    left_count="$(printf '%s' "$counts" | awk '{print $1}')"
    right_count="$(printf '%s' "$counts" | awk '{print $2}')"
    left_count="${left_count:-0}"
    right_count="${right_count:-0}"

    if [ "$left_count" = "0" ] && [ "$right_count" = "0" ]; then
        REMOTE_SYNC_STATE="same"
        status="ok"
        detail="本地 ${DEFAULT_BRANCH} 与 origin/${DEFAULT_BRANCH} 一致。"
    elif [ "$left_count" = "0" ]; then
        REMOTE_SYNC_STATE="ahead"
        status="ok"
        detail="本地 ${DEFAULT_BRANCH} 领先 origin/${DEFAULT_BRANCH} ${right_count} 个提交，可正常推送。"
    elif [ "$right_count" = "0" ]; then
        REMOTE_SYNC_STATE="behind"
        if [ "$MODE" = "apply" ]; then
            status="ok"
            detail="本地 ${DEFAULT_BRANCH} 落后 origin/${DEFAULT_BRANCH} ${left_count} 个提交；apply 将推送初始化分支并创建 PR，禁止 force push。"
        else
            status="needs_user_action"
            detail="本地 ${DEFAULT_BRANCH} 落后 origin/${DEFAULT_BRANCH} ${left_count} 个提交；需要通过初始化分支 PR 同步，禁止 force push。"
        fi
    else
        REMOTE_SYNC_STATE="diverged"
        if [ "$MODE" = "apply" ]; then
            status="ok"
            detail="本地 ${DEFAULT_BRANCH} 与 origin/${DEFAULT_BRANCH} 已分叉（远端 ${left_count}、本地 ${right_count}）；apply 将推送初始化分支并创建 PR，禁止 force push。"
        else
            status="needs_user_action"
            detail="本地 ${DEFAULT_BRANCH} 与 origin/${DEFAULT_BRANCH} 已分叉（远端 ${left_count}、本地 ${right_count}）；默认通过初始化分支 PR 同步，禁止 force push。"
        fi
    fi

    add_item "{\"kind\":\"remote_sync\",\"status\":\"${status}\",\"state\":\"${REMOTE_SYNC_STATE}\",\"remote_ahead\":${left_count},\"local_ahead\":${right_count},\"description_nl\":\"$(json_escape "$detail")\"}" "$status"
}

push_initialization_pr() {
    local short_sha init_branch init_issue_url init_issue_number issue_output issue_rc pr_body push_output push_rc pr_output pr_rc

    short_sha="$(git -C "$TARGET" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown')"
    init_branch="dayu-harness/init-${short_sha}"

    set +e
    issue_output="$(gh issue create --repo "$REPOSITORY" --title "chore: initialize Dayu Harness" --body "Track the Dayu Harness initialization PR for ${DEFAULT_BRANCH}. This issue is created by github-remote.sh so initialization remains issue-first and PR lint can close the loop automatically." 2>&1)"
    issue_rc=$?
    set -e
    if [ "$issue_rc" -eq 0 ] && [ -n "$issue_output" ]; then
        init_issue_url="$issue_output"
        init_issue_number="${init_issue_url##*/}"
        add_item "{\"kind\":\"issue\",\"action\":\"create\",\"number\":\"$(json_escape "$init_issue_number")\",\"status\":\"ok\",\"description_nl\":\"已创建 Dayu Harness 初始化 Issue #${init_issue_number}。\"}" "ok"
    else
        add_item "{\"kind\":\"issue\",\"action\":\"create\",\"status\":\"error\",\"description_nl\":\"初始化 Issue 创建失败，已停止创建初始化 PR，避免生成无法通过 PR lint 的半成品：$(json_escape "$issue_output")\"}" "error"
        return 1
    fi

    pr_body="## Summary
<!-- dayu-harness:summary -->

- Initialize Dayu Harness governance through an initialization branch.
- Keep remote ${DEFAULT_BRANCH} synchronized through a PR without force push.

## Implementation notes
<!-- dayu-harness:implementation-notes -->

- Remote ${DEFAULT_BRANCH} may already be ahead, diverged, or protected from direct local pushes.
- This PR contains the managed initialization output staged by Dayu Harness.

## Test plan
<!-- dayu-harness:test-plan -->

- [x] \`docs/harness/sensors/scripts/validate.sh --json .\`
- [x] \`git push -u origin HEAD:${init_branch}\`

Final PR: yes"
    pr_body="${pr_body}
Closes #${init_issue_number}"

    set +e
    push_output="$(git -C "$TARGET" push -u origin "HEAD:${init_branch}" 2>&1)"
    push_rc=$?
    set -e

    if [ "$push_rc" -ne 0 ]; then
        add_item "{\"kind\":\"remote\",\"action\":\"push_init_branch\",\"branch\":\"$(json_escape "$init_branch")\",\"status\":\"error\",\"description_nl\":\"初始化分支推送失败：$(json_escape "$push_output")\"}" "error"
        return 1
    fi

    add_item "{\"kind\":\"remote\",\"action\":\"push_init_branch\",\"branch\":\"$(json_escape "$init_branch")\",\"status\":\"ok\",\"description_nl\":\"已推送初始化分支 ${init_branch}，未使用 force push。\"}" "ok"

    set +e
    pr_output="$(gh pr create --repo "$REPOSITORY" --base "$DEFAULT_BRANCH" --head "$init_branch" --title "chore: initialize Dayu Harness" --body "$pr_body" 2>&1)"
    pr_rc=$?
    set -e

    if [ "$pr_rc" -eq 0 ]; then
        add_item "{\"kind\":\"pull_request\",\"action\":\"create\",\"branch\":\"$(json_escape "$init_branch")\",\"base\":\"$(json_escape "$DEFAULT_BRANCH")\",\"status\":\"ok\",\"description_nl\":\"已基于 ${DEFAULT_BRANCH} 创建初始化 PR。\"}" "ok"
        return 0
    fi

    add_item "{\"kind\":\"pull_request\",\"action\":\"create\",\"branch\":\"$(json_escape "$init_branch")\",\"base\":\"$(json_escape "$DEFAULT_BRANCH")\",\"status\":\"error\",\"description_nl\":\"初始化 PR 创建失败：$(json_escape "$pr_output")\"}" "error"
    return 1
}

push_default_branch() {
    if [ "$REMOTE_SYNC_STATE" = "remote_missing" ]; then
        DAYU_HARNESS_ALLOW_DEFAULT_BRANCH_CREATION=1 git -C "$TARGET" push -u origin "HEAD:$DEFAULT_BRANCH" >/dev/null 2>&1
    else
        git -C "$TARGET" push -u origin "HEAD:$DEFAULT_BRANCH" >/dev/null 2>&1
    fi
}

default_branch_direct_push_blocked() {
    local hook="$TARGET/.husky/pre-push"
    [ -f "$hook" ] || return 1
    grep -Fq 'direct push to $ref_name is not allowed' "$hook" 2>/dev/null || grep -Fq 'direct push to' "$hook" 2>/dev/null
}

check_mode() {
    local desc
    local status
    if [ "$STATUS_ERROR" -gt 0 ]; then
        status="error"
    elif [ "$STATUS_NEED_USER_ACTION" -gt 0 ]; then
        status="needs_user_action"
    elif [ "$STATUS_NEED_INIT" -gt 0 ]; then
        status="needs_initialization"
    else
        status="ok"
    fi

    desc="远端检查完成，未写入远端配置。"
    if [ -z "$REPOSITORY" ]; then
        if [ "$status" = "ok" ]; then
            status="needs_initialization"
        fi
        desc="未能解析仓库信息；建议设置 DAYU_HARNESS_GITHUB_REPOSITORY 或配置 origin。"
    fi
    if [ "$HAS_GIT" = "true" ] && [ -d "$TARGET/.git" ]; then
        assess_remote_sync_state
        status="$(summary_status check)"
    fi
    emit_output "$status" "$desc"
}

apply_mode() {
    local push_ok="false"
    if [ -z "$DAYU_GITHUB_VISIBILITY" ]; then
        DAYU_GITHUB_VISIBILITY="private"
    fi

    if [ "$DAYU_GITHUB_VISIBILITY" != "private" ] && [ "$DAYU_GITHUB_VISIBILITY" != "public" ]; then
        add_item '{"kind":"visibility","name":"DAYU_HARNESS_GITHUB_VISIBILITY","status":"error","description_nl":"DAYU_HARNESS_GITHUB_VISIBILITY 必须为 private 或 public。"}' "error"
        emit_output "error" "可见性参数无效。"
        exit 0
    fi

    if [ "$GH_AUTH_OK" != "true" ]; then
        emit_output "needs_user_action" "未登录 GitHub CLI，无法执行远端创建。"
        exit 0
    fi

    if [ -z "$REPOSITORY" ]; then
        add_item '{"kind":"repository","name":"repository","status":"needs_user_action","description_nl":"未指定仓库且无 origin，无法自动创建。请设置 DAYU_HARNESS_GITHUB_REPOSITORY。"}' "needs_user_action"
        emit_output "needs_user_action" "远端仓库未解析，apply 无法继续。"
        exit 0
    fi
    if [ "$REPO_MISMATCH" = "true" ]; then
        emit_output "needs_user_action" "origin 与指定 GitHub 仓库不一致，已停止以避免推送和远端设置落到不同仓库。"
        exit 0
    fi

    if [ "$HAS_GIT" = "true" ] && [ -d "$TARGET/.git" ]; then
        if git -C "$TARGET" remote get-url origin >/dev/null 2>&1; then
            REPO_HAS_ORIGIN="true"
        fi
    fi

    if [ "$HAS_GIT" = "true" ] && [ -d "$TARGET/.git" ]; then
        if [ "$REPO_HAS_ORIGIN" != "true" ]; then
            if gh api "repos/$REPOSITORY" >/dev/null 2>&1; then
                if git -C "$TARGET" remote add origin "https://github.com/${REPOSITORY}.git" >/dev/null 2>&1 || git -C "$TARGET" remote set-url origin "https://github.com/${REPOSITORY}.git" >/dev/null 2>&1; then
                    REPO_HAS_ORIGIN="true"
                    add_item '{"kind":"remote","action":"bind","status":"ok","description_nl":"远端仓库已存在，已绑定 origin。"}' "ok"
                else
                    add_item '{"kind":"remote","action":"bind","status":"error","description_nl":"远端仓库已存在，但绑定 origin 失败。"}' "error"
                    emit_output "error" "绑定已有仓库失败。"
                    exit 0
                fi
            elif (cd "$TARGET" && gh repo create "$REPOSITORY" --"$DAYU_GITHUB_VISIBILITY" --source=. --remote=origin >/dev/null 2>&1); then
                add_item "{\"kind\":\"remote\",\"action\":\"create\",\"status\":\"ok\",\"description_nl\":\"已创建仓库并尝试设置 origin（参数：--${DAYU_GITHUB_VISIBILITY}）。\"}" "ok"
            else
                add_item '{"kind":"remote","action":"create","status":"error","description_nl":"gh repo create 执行失败。"}' "error"
                emit_output "error" "仓库创建失败。"
                exit 0
            fi
        else
            add_item '{"kind":"remote","action":"create","status":"ok","description_nl":"检测到已存在 origin，已保留现有远端。"}' "ok"
        fi
    fi

    if [ "$HAS_GIT" = "true" ] && [ -d "$TARGET/.git" ]; then
        if ! git -C "$TARGET" remote get-url origin >/dev/null 2>&1; then
            if [ "$REPOSITORY" != "" ]; then
                git -C "$TARGET" remote add origin "https://github.com/${REPOSITORY}.git" >/dev/null 2>&1 || \
                git -C "$TARGET" remote set-url origin "https://github.com/${REPOSITORY}.git" >/dev/null 2>&1 || true
            fi
        fi

        if [ -z "$DEFAULT_BRANCH" ]; then
            DEFAULT_BRANCH="$(normalize_branch_name "$(git -C "$TARGET" rev-parse --abbrev-ref HEAD 2>/dev/null || true)")"
        fi
        ensure_default_branch_fallback
        assess_remote_sync_state
        if [ "$REMOTE_SYNC_STATE" = "behind" ] || [ "$REMOTE_SYNC_STATE" = "diverged" ] || { [ "$REMOTE_SYNC_STATE" = "ahead" ] && default_branch_direct_push_blocked; }; then
            if push_initialization_pr; then
                push_ok="branch_pr"
            fi
        elif push_default_branch; then
            push_ok="true"
            add_item '{"kind":"remote","action":"push","status":"ok","description_nl":"已执行 git push -u origin <default_branch>。"}' "ok"
        else
            add_item '{"kind":"remote","action":"push","status":"error","description_nl":"git push -u origin <default_branch> 执行失败。"}' "error"
        fi
    else
        add_item '{"kind":"tool","name":"git","status":"needs_initialization","description_nl":"缺少 Git 仓库上下文，无法执行 push。"}' "needs_initialization"
    fi

    if [ "$push_ok" = "true" ]; then
        sync_default_branch_after_push
    fi
    apply_repository_settings
    apply_workflow_permissions
    apply_ruleset_file "$TARGET/.github/rulesets/protect-main.json" "protect-main"
    apply_ruleset_file "$TARGET/.github/rulesets/protect-tags.json" "protect-tags"

    emit_output "$(summary_status apply)" "apply 已执行完成。"
}

apply_repository_settings() {
    local settings_file="$TARGET/.github/repository/pull-request-settings.json"
    local allow_auto_merge delete_branch_on_merge api_output api_rc
    [ "$NEED_REPOSITORY_SETTINGS" = "true" ] || return 0
    [ -f "$settings_file" ] || return 0
    [ -n "$REPOSITORY" ] || return 0
    [ "$GH_AUTH_OK" = "true" ] || return 0

    allow_auto_merge="$(jq -r '.allow_auto_merge // true' "$settings_file" 2>/dev/null || echo true)"
    delete_branch_on_merge="$(jq -r '.delete_branch_on_merge // true' "$settings_file" 2>/dev/null || echo true)"

    set +e
    api_output="$(gh api -X PATCH "repos/$REPOSITORY" -F "allow_auto_merge=$allow_auto_merge" -F "delete_branch_on_merge=$delete_branch_on_merge" 2>&1)"
    api_rc=$?
    set -e

    if [ "$api_rc" -eq 0 ]; then
        add_item "{\"kind\":\"repository_settings\",\"action\":\"patch\",\"status\":\"ok\",\"description_nl\":\"已同步 GitHub 仓库设置 allow_auto_merge=${allow_auto_merge}, delete_branch_on_merge=${delete_branch_on_merge}。\"}" "ok"
    else
        add_item "{\"kind\":\"repository_settings\",\"action\":\"patch\",\"status\":\"error\",\"description_nl\":\"GitHub 仓库设置同步失败：$(json_escape "$api_output")\"}" "error"
    fi
}

apply_workflow_permissions() {
    local api_output api_rc
    [ "$NEED_WORKFLOW_PERMISSIONS" = "true" ] || return 0
    [ -n "$REPOSITORY" ] || return 0
    [ "$GH_AUTH_OK" = "true" ] || return 0

    set +e
    api_output="$(gh api -X PUT "repos/$REPOSITORY/actions/permissions/workflow" -f "default_workflow_permissions=write" -F "can_approve_pull_request_reviews=true" 2>&1)"
    api_rc=$?
    set -e

    if [ "$api_rc" -eq 0 ]; then
        add_item '{"kind":"workflow_permissions","action":"put","status":"ok","description_nl":"已同步 GitHub Actions workflow permissions：default_workflow_permissions=write，can_approve_pull_request_reviews=true。"}' "ok"
    else
        add_item "{\"kind\":\"workflow_permissions\",\"action\":\"put\",\"status\":\"error\",\"description_nl\":\"GitHub Actions workflow permissions 同步失败：$(json_escape "$api_output")\"}" "error"
    fi
}

sync_default_branch_after_push() {
    local api_output api_rc
    [ -n "$REPOSITORY" ] || return 0
    [ -n "$DEFAULT_BRANCH" ] || return 0
    [ "$GH_AUTH_OK" = "true" ] || return 0
    [ "$REMOTE_DEFAULT_BRANCH_MISMATCH" = "true" ] || return 0

    set +e
    api_output="$(gh api -X PATCH "repos/$REPOSITORY" -F "default_branch=$DEFAULT_BRANCH" 2>&1)"
    api_rc=$?
    set -e

    if [ "$api_rc" -eq 0 ]; then
        REMOTE_DEFAULT_BRANCH="$DEFAULT_BRANCH"
        REMOTE_DEFAULT_BRANCH_MISMATCH="false"
        add_item "{\"kind\":\"default_branch\",\"action\":\"patch\",\"status\":\"ok\",\"description_nl\":\"已将 GitHub 远端默认分支同步为 ${DEFAULT_BRANCH}。\"}" "ok"
    else
        add_item "{\"kind\":\"default_branch\",\"action\":\"patch\",\"status\":\"error\",\"description_nl\":\"同步 GitHub 远端默认分支失败：$(json_escape "$api_output")\"}" "error"
    fi
}

rulesets_api_payload() {
    gh api "repos/$REPOSITORY/rulesets" 2>/dev/null || true
}

ruleset_id_for_name() {
    local rulesets_json="$1"
    local ruleset_name="$2"
    printf '%s' "$rulesets_json" | jq -r --arg name "$ruleset_name" 'if type == "array" then .[]? elif type == "object" then (.rulesets // [])[]? else empty end | select(.name == $name) | (.id // empty)' 2>/dev/null | sed -n '1p'
}

apply_ruleset_file() {
    local file="$1"
    local fallback_name="$2"
    local ruleset_name rulesets_json ruleset_id api_output api_rc method endpoint action
    [ -f "$file" ] || return 0
    [ -n "$REPOSITORY" ] || return 0
    [ "$GH_AUTH_OK" = "true" ] || return 0

    ruleset_name="$(jq -r '.name // empty' "$file" 2>/dev/null || true)"
    [ -n "$ruleset_name" ] || ruleset_name="$fallback_name"
    [ "${#REQUIRED_RULESETS[@]}" -gt 0 ] || return 0
    contains_item "$ruleset_name" "${REQUIRED_RULESETS[@]}" || return 0

    rulesets_json="$(rulesets_api_payload)"
    ruleset_id="$(ruleset_id_for_name "$rulesets_json" "$ruleset_name")"
    if [ -n "$ruleset_id" ]; then
        method="PUT"
        endpoint="repos/$REPOSITORY/rulesets/$ruleset_id"
        action="update"
    else
        method="POST"
        endpoint="repos/$REPOSITORY/rulesets"
        action="create"
    fi

    set +e
    api_output="$(gh api -X "$method" "$endpoint" --input "$file" 2>&1)"
    api_rc=$?
    set -e

    if [ "$api_rc" -eq 0 ]; then
        add_item "{\"kind\":\"ruleset\",\"name\":\"$(json_escape "$ruleset_name")\",\"action\":\"$action\",\"status\":\"ok\",\"description_nl\":\"已通过 GitHub Rulesets API ${action} ruleset：$(json_escape "$ruleset_name")。\"}" "ok"
    else
        add_item "{\"kind\":\"ruleset\",\"name\":\"$(json_escape "$ruleset_name")\",\"action\":\"$action\",\"status\":\"error\",\"description_nl\":\"GitHub Rulesets API ${action} 失败：$(json_escape "$api_output")\"}" "error"
    fi
}

verify_mode() {
    local status
    if [ -z "$REPOSITORY" ]; then
        emit_output "needs_initialization" "仓库信息缺失，无法执行 verify。"
        exit 0
    fi
    if [ "$GH_AUTH_OK" != "true" ]; then
        emit_output "needs_user_action" "未登录 GitHub CLI，无法读取 verify 所需信息。"
        exit 0
    fi

    if [ -z "$REPO_VIEW_JSON" ]; then
        REPO_VIEW_JSON="$(gh api "repos/$REPOSITORY" 2>/dev/null || true)"
    fi
    if [ -n "$REPO_VIEW_JSON" ]; then
        REMOTE_DEFAULT_BRANCH="$(normalize_branch_name "$(printf '%s' "$REPO_VIEW_JSON" | jq -r '.default_branch // ""' 2>/dev/null || true)")"
        DEFAULT_BRANCH="$REMOTE_DEFAULT_BRANCH"
        if [ -n "$REQUESTED_DEFAULT_BRANCH" ]; then
            DEFAULT_BRANCH="$(normalize_branch_name "$REQUESTED_DEFAULT_BRANCH")"
        fi
        VISIBILITY="$(printf '%s' "$REPO_VIEW_JSON" | jq -r '.visibility // ""' 2>/dev/null || true)"
        ALLOWED_AUTO_MERGE="$(printf '%s' "$REPO_VIEW_JSON" | jq -r '.allow_auto_merge // ""' 2>/dev/null || true)"
        DELETE_BRANCH_ON_MERGE="$(printf '%s' "$REPO_VIEW_JSON" | jq -r '.delete_branch_on_merge // ""' 2>/dev/null || true)"
    else
        add_item '{"kind":"remote","name":"repos","status":"error","description_nl":"无法读取仓库对象。"}' "error"
    fi

    local branches_lines=""
    local rulesets_lines=""
    local secrets_lines=""
    local variables_lines=""
    local missing_rulesets=""
    local missing_secrets=""
    local missing_variables=""
    local missing_branches=""
    local missing_default_branch=""
    local present_default_branch=""
    local missing_settings=""
    local present_settings=""
    local missing_workflow_permissions=""
    local present_workflow_permissions=""
    local branch_to_json
    local branches_json
    local rulesets_json
    local secrets_json
    local variables_json
    local workflow_permissions_json
    local default_workflow_permissions=""
    local can_approve_pull_request_reviews=""
    local need_branch_verify="false"

    branches_json="$(gh api "repos/$REPOSITORY/branches" 2>/dev/null || true)"
    rulesets_json="$(gh api "repos/$REPOSITORY/rulesets" 2>/dev/null || true)"
    secrets_json="$(gh api "repos/$REPOSITORY/actions/secrets" 2>/dev/null || true)"
    variables_json="$(gh api "repos/$REPOSITORY/actions/variables" 2>/dev/null || true)"
    workflow_permissions_json="$(gh api "repos/$REPOSITORY/actions/permissions/workflow" 2>/dev/null || true)"

    branches_lines="$(parse_resource_names "$branches_json" "branches")"
    rulesets_lines="$(parse_resource_names "$rulesets_json" "rulesets")"
    secrets_lines="$(parse_resource_names "$secrets_json" "secrets")"
    variables_lines="$(parse_resource_names "$variables_json" "variables")"

    if [ -z "${DEFAULT_BRANCH}" ]; then
        DEFAULT_BRANCH="${TARGET_BRANCH:-main}"
    fi
    if [ -n "$REQUESTED_DEFAULT_BRANCH" ]; then
        need_branch_verify="true"
    fi
    if [ "${#REQUIRED_RULESETS[@]}" -gt 0 ]; then
        for req in "${REQUIRED_RULESETS[@]}"; do
            if [ "$req" = "protect-main" ]; then
                need_branch_verify="true"
                break
            fi
        done
    fi
    present_default_branch="${REMOTE_DEFAULT_BRANCH:-${DEFAULT_BRANCH}}"
    if [ -n "$REQUESTED_DEFAULT_BRANCH" ] && [ -n "$REMOTE_DEFAULT_BRANCH" ] && [ "$REMOTE_DEFAULT_BRANCH" != "$DEFAULT_BRANCH" ]; then
        missing_default_branch="$DEFAULT_BRANCH"
    fi
    if [ -n "$DEFAULT_BRANCH" ] && [ "$DEFAULT_BRANCH" != "" ] && [ "$DEFAULT_BRANCH" != "null" ]; then
        if ! contains_line "$DEFAULT_BRANCH" "$branches_lines"; then
            missing_branches="${DEFAULT_BRANCH}"
        fi
    fi

    if [ "$NEED_REPOSITORY_SETTINGS" = "true" ]; then
        if [ "${ALLOWED_AUTO_MERGE}" != "true" ]; then
            if [ -n "$missing_settings" ]; then
                missing_settings+=$'\n'
            fi
            missing_settings+="allow_auto_merge"
        else
            present_settings+="allow_auto_merge"
        fi
        if [ "${DELETE_BRANCH_ON_MERGE}" != "true" ]; then
            if [ -n "$missing_settings" ]; then
                missing_settings+=$'\n'
            fi
            missing_settings+="delete_branch_on_merge"
        else
            if [ -n "$present_settings" ]; then
                present_settings+=$'\n'
            fi
            present_settings+="delete_branch_on_merge"
        fi
    fi

    if [ "$NEED_WORKFLOW_PERMISSIONS" = "true" ]; then
        default_workflow_permissions="$(printf '%s' "$workflow_permissions_json" | jq -r '.default_workflow_permissions // ""' 2>/dev/null || true)"
        can_approve_pull_request_reviews="$(printf '%s' "$workflow_permissions_json" | jq -r '.can_approve_pull_request_reviews // ""' 2>/dev/null || true)"
        if [ "$default_workflow_permissions" != "write" ]; then
            missing_workflow_permissions+="default_workflow_permissions=write"
        else
            present_workflow_permissions+="default_workflow_permissions=write"
        fi
        if [ "$can_approve_pull_request_reviews" != "true" ]; then
            if [ -n "$missing_workflow_permissions" ]; then
                missing_workflow_permissions+=$'\n'
            fi
            missing_workflow_permissions+="can_approve_pull_request_reviews=true"
        else
            if [ -n "$present_workflow_permissions" ]; then
                present_workflow_permissions+=$'\n'
            fi
            present_workflow_permissions+="can_approve_pull_request_reviews=true"
        fi
    fi

    if [ "${#REQUIRED_RULESETS[@]}" -gt 0 ]; then
        for req in "${REQUIRED_RULESETS[@]}"; do
            if ! contains_line "$req" "$rulesets_lines"; then
                if [ -n "$missing_rulesets" ]; then
                    missing_rulesets+=$'\n'
                fi
                missing_rulesets+="$req"
                continue
            fi
            if [ "$req" = "protect-main" ] && [ -n "$DEFAULT_BRANCH" ]; then
                if ! printf '%s' "$rulesets_json" | jq -e --arg ref "refs/heads/$DEFAULT_BRANCH" 'if type == "array" then .[]? elif type == "object" then (.rulesets // [])[]? else empty end | select(.name == "protect-main") | (.conditions.ref_name.include // []) | index($ref)' >/dev/null 2>&1; then
                    if [ -n "$missing_rulesets" ]; then
                        missing_rulesets+=$'\n'
                    fi
                    missing_rulesets+="protect-main:refs/heads/$DEFAULT_BRANCH"
                fi
            fi
        done
    fi

    if [ "${#REQUIRED_SECRETS[@]}" -gt 0 ]; then
        for req in "${REQUIRED_SECRETS[@]}"; do
            if ! contains_line "$req" "$secrets_lines"; then
                if [ -n "$missing_secrets" ]; then
                    missing_secrets+=$'\n'
                fi
                missing_secrets+="$req"
            fi
        done
    fi

    if [ "${#REQUIRED_VARIABLES[@]}" -gt 0 ]; then
        for req in "${REQUIRED_VARIABLES[@]}"; do
            if ! contains_line "$req" "$variables_lines"; then
                if [ -n "$missing_variables" ]; then
                    missing_variables+=$'\n'
                fi
                missing_variables+="$req"
            fi
        done
    fi

    if [ -n "$missing_branches" ]; then
        missing_branches="$(printf '%s' "$missing_branches")"
    fi

    branch_to_json="$(to_json_array_from_lines "$branches_lines")"
    local required_rulesets_json="[]"
    local required_secrets_json="[]"
    local required_variables_json="[]"
    if [ "${#REQUIRED_RULESETS[@]}" -gt 0 ]; then
        required_rulesets_json="$(to_json_array "${REQUIRED_RULESETS[@]}")"
    fi
    if [ "${#REQUIRED_SECRETS[@]}" -gt 0 ]; then
        required_secrets_json="$(to_json_array "${REQUIRED_SECRETS[@]}")"
    fi
    if [ "${#REQUIRED_VARIABLES[@]}" -gt 0 ]; then
        required_variables_json="$(to_json_array "${REQUIRED_VARIABLES[@]}")"
    fi

    if [ "$NEED_REPOSITORY_SETTINGS" = "true" ]; then
        add_resource_item \
          "repository_settings" \
          "$( [ -n "$missing_settings" ] && echo missing || echo ok )" \
          "$(to_json_array allow_auto_merge delete_branch_on_merge)" \
          "$(to_json_array_from_lines "$present_settings")" \
          "$(to_json_array_from_lines "$missing_settings")" \
          "仓库设置 allow_auto_merge/delete_branch_on_merge 当前值：allow_auto_merge=${ALLOWED_AUTO_MERGE:-unknown}；delete_branch_on_merge=${DELETE_BRANCH_ON_MERGE:-unknown}。"
    fi

    if [ "$NEED_WORKFLOW_PERMISSIONS" = "true" ]; then
        add_resource_item \
          "workflow_permissions" \
          "$( [ -n "$missing_workflow_permissions" ] && echo missing || echo ok )" \
          "$(to_json_array default_workflow_permissions=write can_approve_pull_request_reviews=true)" \
          "$(to_json_array_from_lines "$present_workflow_permissions")" \
          "$(to_json_array_from_lines "$missing_workflow_permissions")" \
          "检测 GitHub Actions workflow permissions 当前值：default_workflow_permissions=${default_workflow_permissions:-unknown}；can_approve_pull_request_reviews=${can_approve_pull_request_reviews:-unknown}。"
    fi

    if [ -n "$REQUESTED_DEFAULT_BRANCH" ]; then
        add_resource_item \
          "default_branch" \
          "$( [ -n "$missing_default_branch" ] && echo missing || echo ok )" \
          "$(to_json_array "$DEFAULT_BRANCH")" \
          "$(to_json_array "$present_default_branch")" \
          "$(to_json_array_from_lines "$missing_default_branch")" \
          "检测 GitHub 远端默认分支是否与本地治理默认分支一致。"
    fi

    if [ "$need_branch_verify" = "true" ]; then
        add_resource_item \
          "branches" \
          "$( [ -n "$missing_branches" ] && echo missing || echo ok )" \
          "$(to_json_array "$DEFAULT_BRANCH")" \
          "$branch_to_json" \
          "$(to_json_array_from_lines "$missing_branches")" \
          "检测分支列表，当前默认分支：${DEFAULT_BRANCH:-unknown}。"
    fi

    add_resource_item \
      "rulesets" \
      "$( [ -n "$missing_rulesets" ] && echo missing || echo ok )" \
      "$required_rulesets_json" \
      "$(to_json_array_from_lines "$rulesets_lines")" \
      "$(to_json_array_from_lines "$missing_rulesets")" \
      "检测到的 rulesets 未匹配全部预期，protect-main 还会校验具体默认分支 ref。"

    add_resource_item \
      "secrets" \
      "$( [ -n "$missing_secrets" ] && echo missing || echo ok )" \
      "$required_secrets_json" \
      "$(to_json_array_from_lines "$secrets_lines")" \
      "$(to_json_array_from_lines "$missing_secrets")" \
      "检测到的 repository secrets 未包含必需列表。"

    add_resource_item \
      "variables" \
      "$( [ -n "$missing_variables" ] && echo missing || echo ok )" \
      "$required_variables_json" \
      "$(to_json_array_from_lines "$variables_lines")" \
      "$(to_json_array_from_lines "$missing_variables")" \
      "检测到的 repository variables 未包含必需列表。"

    status="$(summary_status verify)"
    emit_output "$status" "verify 完成，包含远端配置缺失项会在 items 中返回。"
}

case "$MODE" in
    check)
        check_mode
        ;;
    apply)
        apply_mode
        ;;
    verify)
        verify_mode
        ;;
    *)
        echo '{"status":"error","error":"unsupported mode","description_nl":"请使用 --check、--apply 或 --verify。"}'
        exit 2
        ;;
esac
