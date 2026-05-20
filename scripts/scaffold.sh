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
OUTPUT_BASE="$(pwd)"

MODE="prompt"
TARGET=""
ENABLED_CATEGORIES=""
ONLY_CATEGORY="all"
ONLY_EXPLICIT="false"
STRATEGY=""
LOCALE="zh-CN"

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
    echo "用法: scaffold.sh <target-root> [--dry-run|--apply] [--enable ids] [--only category] [--strategy merge|replace|skip] [--locale zh-CN|en]"
    echo "说明:"
    echo "  - default=true 的必选能力始终部署；--enable 在必选集上追加能力"
    echo "  - --enable 与 --only 支持逗号分隔；--only 保留历史兼容，不会排除必选能力"
    echo "  - --only 兼容历史分类: docs/husky/commitlint/workflows/eslint/prettier/lint-staged/gitignore/release-please"
    echo "  - --enable 兼容旧能力 id，并会展开到新的原子能力或 preset"
    echo "  - --only all 表示部署全部公开能力；内部能力只通过依赖展开"
    echo "  - --apply 默认不替换已存在文件；安装器 clean 时自动 merge，已有配置需通过 --strategy 声明安全策略"
    echo "  - --locale 选择模板语言。默认 zh-CN；en 将优先使用 manifest.template_files_i18n.en（如存在）"
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
                    if cp "$src_path" "$dst_path"; then
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

    DRY_FILES=0
    DRY_NEW=0
    DRY_EXISTING=0
    DRY_MISSING=0
    DRY_INST_MISSING=0

    local cap_id
    for cap_id in "${capability_ids[@]}"; do
        local manifest_path
        manifest_path="$(manifest_path_for_id "$cap_id")"

        local cap_desc cap_desc_nl cap_default dependencies_json acceptance_json installer_json
        cap_desc="$(json_escape "$(jq -r '.description // empty' "$manifest_path")")"
        cap_desc_nl="$(json_escape "$(jq -r '.description_nl // empty' "$manifest_path")")"
        cap_default="$(jq -r '.default // false' "$manifest_path")"
        dependencies_json="$(jq -c '.dependencies // []' "$manifest_path")"
        acceptance_json="$(jq -c '.acceptance // []' "$manifest_path")"
        installer_json="$(jq -c '.installer // null' "$manifest_path")"

        local pre_new=$DRY_NEW
        local pre_existing=$DRY_EXISTING
        local pre_missing=$DRY_MISSING
        local pre_inst_missing=$DRY_INST_MISSING

        DRY_ITEMS=()
        collect_file_entries "$manifest_path" "template" "dry"
        collect_file_entries "$manifest_path" "asset" "dry"
        collect_installer_entry_dry "$manifest_path" "$cap_id"

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
        capability_jsons+=( "{\"id\":\"$cap_id\",\"description\":\"$cap_desc\",\"description_nl\":\"$cap_desc_nl\",\"default\":$cap_default,\"dependencies\":$dependencies_json,\"acceptance\":$acceptance_json,\"installer\":$installer_json,\"status\":\"$status\",\"files_total\":$((cap_new + cap_existing)),\"files_new\":$cap_new,\"files_existing\":$cap_existing,\"files_missing\":$cap_missing,\"items\":[$items_json]}" )
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

    cat <<JSONEOF
{
  "mode":"dry-run",
  "target":"$(json_escape "$TARGET_DISPLAY")",
  "status":"$top_status",
  "environment":${environment_json},
  "capabilities":[${capabilities_json}],
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
    if [ "$environment_status" != "ok" ]; then
        cat <<JSONEOF
{
  "mode":"apply",
  "target":"$(json_escape "$TARGET_DISPLAY")",
  "status":"$environment_status",
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
        local cap_desc cap_desc_nl cap_default dependencies_json acceptance_json installer_json
        cap_desc="$(json_escape "$(jq -r '.description // empty' "$manifest_path")")"
        cap_desc_nl="$(json_escape "$(jq -r '.description_nl // empty' "$manifest_path")")"
        cap_default="$(jq -r '.default // false' "$manifest_path")"
        dependencies_json="$(jq -c '.dependencies // []' "$manifest_path")"
        acceptance_json="$(jq -c '.acceptance // []' "$manifest_path")"
        installer_json="$(jq -c '.installer // null' "$manifest_path")"

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
        capability_jsons+=( "{\"id\":\"$cap_id\",\"description\":\"$cap_desc\",\"description_nl\":\"$cap_desc_nl\",\"default\":$cap_default,\"dependencies\":$dependencies_json,\"acceptance\":$acceptance_json,\"installer\":$installer_json,\"status\":\"$status\",\"files_total\":$((cap_new + cap_existing)),\"files_new\":$cap_new,\"files_existing\":$cap_existing,\"items\":[$items_json]}" )
    done

    local overall_status="ok"
    if [ "$APPLY_ERROR" -gt 0 ] || [ "$APPLY_MISSING" -gt 0 ]; then
        overall_status="error"
    elif [ "$APPLY_STRATEGY_REQUIRED" -gt 0 ]; then
        overall_status="needs_strategy"
    elif [ "$APPLY_PARTIAL" -gt 0 ] || [ "$APPLY_SKIPPED" -gt 0 ]; then
        overall_status="partial"
    fi

    local validation_status="skipped"
    local validation_desc=""
    if [ -f "$VALIDATE_SCRIPT" ] && [ -x "$VALIDATE_SCRIPT" ]; then
        set +e
        validate_output="$(bash "$VALIDATE_SCRIPT" --json "$TARGET" 2>&1)"
        validate_rc=$?
        set -e
        if [ "$validate_rc" -eq 0 ]; then
            validation_status="passed"
        else
            validation_status="failed"
            validation_desc="$(echo "$validate_output" | jq -r '.description_nl // .summary // "validate failed"' 2>/dev/null || echo "validate failed")"
        fi
    fi

    local top_desc="Apply completed with status $overall_status."
    if [ "$overall_status" = "needs_strategy" ]; then
        top_desc="Apply required a strategy for installer-backed capabilities. Re-run with an allowed --strategy value."
    elif [ "$overall_status" = "partial" ]; then
        if [ "$STRATEGY" = "skip" ]; then
            top_desc="Apply completed with partial changes. Installer-managed components were skipped, while static files were still processed."
        else
            top_desc="Apply completed with partial changes. Existing targets were skipped by default."
        fi
    elif [ "$overall_status" = "error" ]; then
        top_desc="Apply encountered errors. Resolve conflicts and retry."
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
  "environment":${environment_json},
  "capabilities":[${capabilities_json}],
  "summary":"Applied capability set: $(json_escape "$summary")",
  "description_nl":"$(json_escape "$top_desc")",
  "applied_count":$APPLY_NEW,
  "skipped_count":$APPLY_SKIPPED,
  "files_total":$((APPLY_NEW + APPLY_EXISTING)),
  "files_new":$APPLY_NEW,
  "files_existing":$APPLY_EXISTING,
  "validation":"$(json_escape "$validation_status")",
  "validation_description_nl":"$(json_escape "$validation_desc")",
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
