#!/usr/bin/env bash
# install-gitignore.sh — 安装/合并 .gitignore
# 用法: install-gitignore.sh <target-root> [--check|--apply merge|replace|skip]
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

MODE="default"
STRATEGY=""
TARGET=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check)
            MODE="check"
            shift
            ;;
        --apply)
            MODE="apply"
            STRATEGY="${2:-}"
            shift 2
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo '{"status":"error","error":"usage: install-gitignore.sh <target-root> [--check|--apply merge|replace|skip]"}' >&2
    exit 2
fi
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
    echo '{"status":"error","error":"target not found"}' >&2
    exit 2
}

GITIGNORE_PATH="$TARGET/.gitignore"
SNAPSHOT_DIR="$SKILL_DIR/assets/gitignore/github"
UNIVERSAL_TEMPLATE="$SKILL_DIR/assets/gitignore/universal.gitignore"
PROJECT_TYPES=()

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
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

find_any_file() {
    local pattern="$1"
    find "$TARGET" \
        -path "$TARGET/.git" -prune \
        -o -path "$TARGET/node_modules" -prune \
        -o -path "$TARGET/.claude" -prune \
        -o -name "$pattern" -type f -print -quit 2>/dev/null
}

add_type() {
    local type="$1"
    local existing
    for existing in "${PROJECT_TYPES[@]+"${PROJECT_TYPES[@]}"}"; do
        [ "$existing" = "$type" ] && return 0
    done
    PROJECT_TYPES+=( "$type" )
}

detect_project_types() {
    PROJECT_TYPES=()

    if [ -f "$TARGET/package.json" ] || [ -f "$TARGET/package-lock.json" ] || [ -f "$TARGET/pnpm-lock.yaml" ] || [ -f "$TARGET/yarn.lock" ]; then
        add_type "Node"
    fi
    if [ -f "$TARGET/requirements.txt" ] || [ -f "$TARGET/setup.py" ] || [ -f "$TARGET/pyproject.toml" ] || [ -n "$(find_any_file '*.py')" ]; then
        add_type "Python"
    fi
    if [ -f "$TARGET/go.mod" ] || [ -n "$(find_any_file '*.go')" ]; then
        add_type "Go"
    fi
    if [ -f "$TARGET/Cargo.toml" ] || [ -n "$(find_any_file '*.rs')" ]; then
        add_type "Rust"
    fi
    if [ -f "$TARGET/pom.xml" ] || [ -f "$TARGET/build.gradle" ] || [ -f "$TARGET/build.gradle.kts" ] || [ -n "$(find_any_file '*.java')" ]; then
        add_type "Java"
    fi
    if [ -n "$(find_any_file '*.sln')" ] || [ -n "$(find_any_file '*.csproj')" ] || [ -n "$(find_any_file '*.fsproj')" ] || [ -n "$(find_any_file '*.vbproj')" ]; then
        add_type "VisualStudio"
    fi

    if [ "${#PROJECT_TYPES[@]}" -eq 0 ]; then
        add_type "Node"
    fi
}

template_path_for_type() {
    local type="$1"
    case "$type" in
        Node|Python|Go|Rust|Java|VisualStudio)
            printf '%s/%s.gitignore' "$SNAPSHOT_DIR" "$type"
            ;;
        *)
            return 1
            ;;
    esac
}

emit_dayu_local_block() {
    cat <<'EOF'
# === Dayu Harness local exclusions ===
.claude/
skills-lock.json
EOF
}

project_types_json() {
    local out="["
    local sep=""
    local type
    for type in "${PROJECT_TYPES[@]}"; do
        out="${out}${sep}\"$(json_escape "$type")\""
        sep=","
    done
    out="${out}]"
    printf '%s' "$out"
}

emit_combined_template() {
    local type template
    if [ -f "$UNIVERSAL_TEMPLATE" ]; then
        echo "# === universal.gitignore ==="
        cat "$UNIVERSAL_TEMPLATE"
        echo ""
    fi

    for type in "${PROJECT_TYPES[@]}"; do
        template="$(template_path_for_type "$type" || true)"
        [ -n "$template" ] || continue
        [ -f "$template" ] || continue
        echo "# === github/gitignore ${type}.gitignore snapshot ==="
        cat "$template"
        echo ""
    done

    emit_dayu_local_block
}

missing_lines_from_template() {
    local template_file="$1"
    local existing_file="$2"

    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        if [ -f "$existing_file" ] && grep -Fxq -- "$line" "$existing_file" 2>/dev/null; then
            continue
        fi
        printf '%s\n' "$line"
    done < "$template_file"
}

missing_lines_from_stream() {
    local existing_file="$1"

    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        if [ -f "$existing_file" ] && grep -Fxq -- "$line" "$existing_file" 2>/dev/null; then
            continue
        fi
        printf '%s\n' "$line"
    done
}

collect_missing_for_type() {
    local type="$1"
    local template
    if [ "$type" = "Dayu" ]; then
        emit_dayu_local_block | missing_lines_from_stream "$GITIGNORE_PATH"
        return 0
    fi

    template="$(template_path_for_type "$type" || true)"
    [ -n "$template" ] && [ -f "$template" ] || return 0
    missing_lines_from_template "$template" "$GITIGNORE_PATH"
}

append_missing_section() {
    local header="$1"
    local content="$2"
    [ -n "$content" ] || return 0

    {
        echo ""
        echo "# === Added by dayu-harness: ${header} ==="
        printf '%s\n' "$content"
    } >> "$GITIGNORE_PATH"
}

detect_project_types

if [ "$MODE" = "check" ]; then
    ITEMS=()
    ERROR_COUNT=0
    TOTAL_MISSING=0
    ANY_EXISTING=false
    [ -f "$GITIGNORE_PATH" ] && ANY_EXISTING=true

    check_type() {
        local type="$1"
        local template="$2"
        local missing_count=0
        local incoming_lines=0
        local sample=""
        local status="clean"
        local strategies='["merge","replace","skip"]'
        local description=""

        if [ "$type" != "Dayu" ] && { [ -z "$template" ] || [ ! -f "$template" ]; }; then
            ERROR_COUNT=$((ERROR_COUNT + 1))
            ITEMS+=( "{\"file\":\".gitignore\",\"type\":\"$(json_escape "$type")\",\"status\":\"error\",\"strategies\":[\"skip\"],\"error\":\"Template not found\",\"description_nl\":\"Missing github/gitignore snapshot for ${type}.\"}" )
            return 0
        fi

        if [ "$type" = "Dayu" ]; then
            incoming_lines="$(emit_dayu_local_block | wc -l | tr -d ' ')"
        else
            incoming_lines="$(wc -l < "$template" | tr -d ' ')"
        fi

        if [ -f "$GITIGNORE_PATH" ]; then
            missing_output="$(collect_missing_for_type "$type")"
            if [ -n "$missing_output" ]; then
                missing_count="$(printf '%s\n' "$missing_output" | wc -l | tr -d ' ')"
                sample="$(printf '%s\n' "$missing_output" | sed -n '1,8p' | paste -sd ', ' -)"
                TOTAL_MISSING=$((TOTAL_MISSING + missing_count))
                status="conflict"
                description="${missing_count} pattern(s) from ${type} are missing from existing .gitignore."
            else
                description="Existing .gitignore already contains required ${type} patterns."
            fi
        else
            description="No existing .gitignore. ${incoming_lines} ${type} pattern line(s) are ready for install."
        fi

        ITEMS+=( "{\"file\":\".gitignore\",\"type\":\"$(json_escape "$type")\",\"status\":\"$status\",\"strategies\":${strategies},\"incoming_lines\":${incoming_lines},\"missing_count\":${missing_count},\"missing_sample\":\"$(json_escape "$sample")\",\"description_nl\":\"$(json_escape "$description")\"}" )
    }

    if [ -f "$UNIVERSAL_TEMPLATE" ]; then
        check_type "universal" "$UNIVERSAL_TEMPLATE"
    else
        ERROR_COUNT=$((ERROR_COUNT + 1))
        ITEMS+=( '{"file":".gitignore","type":"universal","status":"error","strategies":["skip"],"error":"Template not found","description_nl":"Missing universal.gitignore asset."}' )
    fi

    for type in "${PROJECT_TYPES[@]}"; do
        check_type "$type" "$(template_path_for_type "$type" || true)"
    done
    check_type "Dayu" ""

    TOP_STATUS="clean"
    SUMMARY="No existing .gitignore found. Ready for clean install."
    DESC_NL="The project .gitignore can be created from selected templates and Dayu local exclusions."
    if [ "$ERROR_COUNT" -gt 0 ]; then
        TOP_STATUS="error"
        SUMMARY="Errors encountered during .gitignore template check."
        DESC_NL="Missing .gitignore template assets must be restored before installation."
    elif [ "$ANY_EXISTING" = true ] && [ "$TOTAL_MISSING" -gt 0 ]; then
        TOP_STATUS="conflict"
        SUMMARY="Existing .gitignore found with ${TOTAL_MISSING} missing pattern(s). Use merge to append missing patterns."
        DESC_NL="Existing .gitignore will not be overwritten automatically. Use merge to append only missing template and Dayu local exclusion lines."
    elif [ "$ANY_EXISTING" = true ]; then
        SUMMARY="Existing .gitignore already contains required selected patterns."
        DESC_NL="No .gitignore changes are required."
    fi

    printf '{"status":"%s","detected_templates":[' "$TOP_STATUS"
    sep=""
    for type in "${PROJECT_TYPES[@]}"; do
        printf '%s"%s"' "$sep" "$(json_escape "$type")"
        sep=","
    done
    printf '],"items":[%s],"summary":"%s","description_nl":"%s"}\n' \
        "$(IFS=,; echo "${ITEMS[*]}")" \
        "$(json_escape "$SUMMARY")" \
        "$(json_escape "$DESC_NL")"
    exit 0
fi

if [ "$MODE" = "apply" ]; then
    case "$STRATEGY" in
        merge|replace|skip) ;;
        *)
            echo '{"status":"error","error":"--apply requires strategy: merge, replace, or skip"}' >&2
            exit 2
            ;;
    esac

    if [ "$STRATEGY" = "skip" ]; then
        echo '{"status":"ok","action":"skip","detail":".gitignore skipped per user request.","description_nl":".gitignore 已按用户选择跳过。"}'
        exit 0
    fi

    if [ "$STRATEGY" = "replace" ] || [ ! -f "$GITIGNORE_PATH" ]; then
        emit_combined_template > "$GITIGNORE_PATH"
        echo "{\"status\":\"ok\",\"action\":\"$STRATEGY\",\"detected_templates\":$(project_types_json),\"detail\":\".gitignore written from selected templates and Dayu local exclusions.\",\"description_nl\":\".gitignore 已写入选定模板和 Dayu 本地排除段。\"}"
        exit 0
    fi

    added_count=0
    missing=""
    if [ -f "$UNIVERSAL_TEMPLATE" ]; then
        missing="$(missing_lines_from_template "$UNIVERSAL_TEMPLATE" "$GITIGNORE_PATH")"
        if [ -n "$missing" ]; then
            append_missing_section "universal.gitignore" "$missing"
            added_count=$((added_count + $(printf '%s\n' "$missing" | wc -l | tr -d ' ')))
        fi
    fi

    for type in "${PROJECT_TYPES[@]}"; do
        missing="$(collect_missing_for_type "$type")"
        if [ -n "$missing" ]; then
            append_missing_section "github/gitignore ${type}.gitignore snapshot" "$missing"
            added_count=$((added_count + $(printf '%s\n' "$missing" | wc -l | tr -d ' ')))
        fi
    done

    missing="$(emit_dayu_local_block | missing_lines_from_stream "$GITIGNORE_PATH")"
    if [ -n "$missing" ]; then
        append_missing_section "Dayu Harness local exclusions" "$missing"
        added_count=$((added_count + $(printf '%s\n' "$missing" | wc -l | tr -d ' ')))
    fi

    echo "{\"status\":\"ok\",\"action\":\"merge\",\"added_count\":${added_count},\"detail\":\"Appended ${added_count} missing pattern(s) to .gitignore.\",\"description_nl\":\"已向现有 .gitignore 追加 ${added_count} 条缺失规则，保留用户原有规则。\"}"
    exit 0
fi

if [ -f "$GITIGNORE_PATH" ]; then
    echo "--- 检测到已有 .gitignore ---"
    bash "$0" "$TARGET" --check
    echo ""
    echo "使用 --apply merge 追加缺失规则，或使用 --apply skip 保留现状。"
else
    emit_combined_template > "$GITIGNORE_PATH"
    echo "  ✓ .gitignore"
fi
