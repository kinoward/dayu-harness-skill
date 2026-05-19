#!/usr/bin/env bash
# check-i18n-drift.sh — 检查 README 与模板树是否存在语言版本漂移
# 用法:
#   check-i18n-drift.sh [--json] [repo-root]
#   check-i18n-drift.sh --json [repo-root]
#
# 退出码: 0=通过, 1=存在漂移, 2=脚本错误
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DEFAULT="$SCRIPT_DIR/.."
ROOT_DEFAULT="$(cd "$ROOT_DEFAULT" && pwd)"

JSON_MODE=false
TARGET=""

usage() {
    echo "用法: check-i18n-drift.sh [--json] [repo-root]"
    echo "  --json    输出机器可读 JSON"
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --json)
            JSON_MODE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

if [ -z "$TARGET" ]; then
    TARGET="$ROOT_DEFAULT"
fi

TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || {
    echo "错误: 无法解析项目路径 '$TARGET'。" >&2
    exit 2
}

if ! command -v jq >/dev/null 2>&1; then
    echo "错误: check-i18n-drift 依赖 jq。" >&2
    exit 2
fi

README_FILES=(
    "README.md"
    "README.en.md"
)

TEMPLATES_DIR="$TARGET/templates"
TEMPLATES_EN_DIR="$TARGET/templates.en"
CAPABILITIES_DIR="$TARGET/capabilities"
QAA_FILE="$TARGET/Q&A-TEMPLATE.md"

TOTAL=0
PASSED=0
FAILED=0
CHECKS=""

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

join_json() {
    local out=""
    for item in "$@"; do
        [ -z "$item" ] && continue
        if [ -z "$out" ]; then
            out="$item"
        else
            out="$out,$item"
        fi
    done
    printf '%s' "$out"
}

record_check() {
    local name="$1"
    local status="$2"
    local detail="$3"

    TOTAL=$((TOTAL + 1))
    if [ "$status" = "pass" ]; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
    fi

    local escaped_name
    local escaped_detail
    escaped_name=$(json_escape "$name")
    escaped_detail=$(json_escape "$detail")

    local item
    item="{\"name\":\"${escaped_name}\",\"status\":\"${status}\",\"detail\":\"${escaped_detail}\"}"
    if [ -n "$CHECKS" ]; then
        CHECKS+=",$item"
    else
        CHECKS="$item"
    fi
}

collect_relative_files() {
    local root="$1"
    if [ ! -d "$root" ]; then
        return
    fi
    find "$root" -type f | sed "s#^$root/##" | sort
}

heading_signature() {
    local file="$1"
    awk '
{
    line=$0
    gsub(/^[[:space:]]+/, "", line)
    if (line ~ /^#{1,6}[[:space:]]+/) {
        n=0
        while (substr(line, n + 1, 1) == "#") {
            n = n + 1
        }
        if (n >= 1 && n <= 6) {
            printf "%d ", n
        }
    }
}' "$file" | sed 's/[[:space:]]*$//'
}

markdown_format_signature() {
    local file="$1"
    awk '
BEGIN {
    in_code = 0
}
{
    line = $0
    trimmed = line
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", trimmed)

    if (trimmed ~ /^```/) {
        print "code-fence"
        in_code = !in_code
        next
    }
    if (in_code) {
        print "code-line"
        next
    }
    if (trimmed == "") {
        next
    }
    if (trimmed ~ /^#{1,6}[[:space:]]+/) {
        match(trimmed, /^#+/)
        print "heading:" RLENGTH
        next
    }
    if (trimmed ~ /^[-*+][[:space:]]+/) {
        match(line, /^[[:space:]]*/)
        print "unordered-list:" RLENGTH
        next
    }
    if (trimmed ~ /^[0-9]+\.[[:space:]]+/) {
        match(line, /^[[:space:]]*/)
        print "ordered-list:" RLENGTH
        next
    }
    if (trimmed ~ /^>[[:space:]]*/) {
        print "blockquote"
        next
    }
    if (trimmed ~ /^\|.*\|$/) {
        print "table-row"
        next
    }
    if (trimmed ~ /^---+$/) {
        print "horizontal-rule"
        next
    }
    if (trimmed ~ /^<!--.*-->$/) {
        print "html-comment"
        next
    }
    if (trimmed ~ /^<\/?[A-Za-z][^>]*>$/) {
        sub(/[[:space:]].*/, ">", trimmed)
        print "html-tag:" trimmed
        next
    }
    if (trimmed ~ /^\[[^]]+\]:[[:space:]]*/) {
        print "reference-link"
        next
    }
    if (trimmed ~ /^\[.*\]\(.*\)/) {
        print "link-line"
        next
    }
}' "$file"
}

check_readme_pair() {
    for readme in "${README_FILES[@]}"; do
        if [ -f "$TARGET/$readme" ]; then
            record_check "README pair" "pass" "存在 $readme"
        else
            record_check "README pair" "fail" "缺失 README 文件: $readme"
        fi
    done

    if [ -f "$TARGET/README.md" ] && [ -f "$TARGET/README.en.md" ]; then
        local sig_zh
        local sig_en
        sig_zh="$(markdown_format_signature "$TARGET/README.md")"
        sig_en="$(markdown_format_signature "$TARGET/README.en.md")"
        if [ "$sig_zh" = "$sig_en" ]; then
            record_check "README format parity" "pass" "README.md 与 README.en.md 的 Markdown 格式签名一致"
        else
            record_check "README format parity" "fail" "README.md 与 README.en.md 的 Markdown 格式签名不一致"
        fi
    fi
}

check_template_trees() {
    if [ ! -d "$TEMPLATES_DIR" ]; then
        record_check "Template tree mirror" "fail" "templates 目录不存在: $TEMPLATES_DIR"
        return
    fi
    if [ ! -d "$TEMPLATES_EN_DIR" ]; then
        record_check "Template tree mirror" "fail" "templates.en 目录不存在: $TEMPLATES_EN_DIR"
        return
    fi

    local zh_tmp
    local en_tmp
    zh_tmp="$(mktemp)"
    en_tmp="$(mktemp)"
    local mirror_failed=0
    local heading_failed=0
    local format_failed=0

    collect_relative_files "$TEMPLATES_DIR" > "$zh_tmp"
    collect_relative_files "$TEMPLATES_EN_DIR" > "$en_tmp"

    while IFS= read -r missing_in_en; do
        [ -z "$missing_in_en" ] && continue
        record_check "Template tree mirror" "fail" "templates.en 缺少 $missing_in_en"
        mirror_failed=1
    done < <(comm -23 "$zh_tmp" "$en_tmp")

    while IFS= read -r missing_in_zh; do
        [ -z "$missing_in_zh" ] && continue
        record_check "Template tree mirror" "fail" "templates 缺少 $missing_in_zh（仅存在 templates.en）"
        mirror_failed=1
    done < <(comm -13 "$zh_tmp" "$en_tmp")

    if diff -q "$zh_tmp" "$en_tmp" >/dev/null; then
        :
    else
        mirror_failed=1
    fi

    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        if [[ "$rel" != *.md ]]; then
            continue
        fi

        if [ ! -f "$TEMPLATES_EN_DIR/$rel" ]; then
            continue
        fi

        local sig_zh
        local sig_en
        sig_zh="$(heading_signature "$TEMPLATES_DIR/$rel")"
        sig_en="$(heading_signature "$TEMPLATES_EN_DIR/$rel")"

        if [ "$sig_zh" != "$sig_en" ]; then
            record_check "Template heading parity" "fail" "Markdown 标题层级序列不一致: templates/$rel 与 templates.en/$rel (${sig_zh:-[none]} vs ${sig_en:-[none]})"
            heading_failed=1
        fi

        sig_zh="$(markdown_format_signature "$TEMPLATES_DIR/$rel")"
        sig_en="$(markdown_format_signature "$TEMPLATES_EN_DIR/$rel")"

        if [ "$sig_zh" != "$sig_en" ]; then
            record_check "Template format parity" "fail" "Markdown 格式签名不一致: templates/$rel 与 templates.en/$rel"
            format_failed=1
        fi
    done < "$zh_tmp"

    rm -f "$zh_tmp" "$en_tmp"

    if [ "$mirror_failed" -eq 0 ]; then
        record_check "Template tree mirror" "pass" "templates 与 templates.en 文件树完全一致"
    fi

    if [ "$heading_failed" -eq 0 ]; then
        record_check "Template heading parity" "pass" "检测到的 Markdown 文件标题层级序列一致"
    fi

    if [ "$format_failed" -eq 0 ]; then
        record_check "Template format parity" "pass" "templates 与 templates.en 的 Markdown 格式签名一致"
    fi
}

check_capability_mapping() {
    if [ ! -d "$CAPABILITIES_DIR" ]; then
        record_check "Capability English template mapping" "fail" "capabilities 目录不存在: $CAPABILITIES_DIR"
        return
    fi

    local template_entry_count=0
    local mapped_count=0
    local mapping_fail=0

    shopt -s nullglob
    local manifest_path
    for manifest_path in "$CAPABILITIES_DIR"/*.json; do
        local entries
        if ! entries=$(jq -c '.template_files // [] | .[]' "$manifest_path" 2>/dev/null); then
            record_check "Capability English template mapping" "fail" "无法解析 manifest JSON: ${manifest_path##*/}"
            continue
        fi

        local capability
        capability=$(jq -r '.id // empty' "$manifest_path")
        if [ -z "$capability" ]; then
            continue
        fi

        while IFS= read -r entry; do
            [ -z "$entry" ] && continue

            local src
            local dst
            local src_en
            local explicit_src_en
            local inferred_src_en
            local mapped_in_legacy
            local has_en_mapping
            local en_ref_exists

            src=$(jq -r '.src // empty' <<<"$entry")
            [ -z "$src" ] && continue
            [[ "$src" != templates/* ]] && continue
            dst=$(jq -r '.dst // empty' <<<"$entry")

            template_entry_count=$((template_entry_count + 1))
            explicit_src_en=$(jq -r '.src_en // empty' <<<"$entry")
            inferred_src_en="${src/#templates\//templates.en/}"
            src_en=""

            if [ -n "$explicit_src_en" ] && [ "$explicit_src_en" != "null" ]; then
                src_en="$explicit_src_en"
            else
                src_en="$inferred_src_en"
            fi

            if [ ! -f "$TARGET/$src" ]; then
                record_check "Capability English template mapping" "fail" "能力 $capability 的模板源文件不存在: $src"
                continue
            fi

            if [ -n "$explicit_src_en" ] && [ "$explicit_src_en" != "null" ]; then
                mapped_in_legacy=0
                if [[ "$explicit_src_en" == templates.en/* ]]; then
                    mapped_in_legacy=1
                fi
                if [ "$mapped_in_legacy" -eq 0 ]; then
                    record_check "Capability English template mapping" "fail" "能力 $capability 的 src_en 非法: $explicit_src_en"
                    mapping_fail=1
                    continue
                fi
                if [ ! -f "$TARGET/$explicit_src_en" ]; then
                    record_check "Capability English template mapping" "fail" "能力 $capability 的英文本不存在: $explicit_src_en（声明自 $src）"
                    mapping_fail=1
                    continue
                fi
                if [ -n "$dst" ] && [ "$dst" != "null" ]; then
                    en_ref_exists="$(jq -r --arg dst "$dst" --arg src "$explicit_src_en" '.template_files_i18n.en // [] | any(.dst == $dst and .src == $src)' "$manifest_path")"
                    if [ "$en_ref_exists" != "true" ]; then
                        record_check "Capability English template mapping" "fail" "能力 $capability 未在 template_files_i18n.en 声明模板映射: $src -> $explicit_src_en"
                        mapping_fail=1
                        continue
                    fi
                fi
                mapped_count=$((mapped_count + 1))
                continue
            fi

            if [ -n "$dst" ] && [ "$dst" != "null" ]; then
                src_en="$inferred_src_en"
                has_en_mapping="$(jq -r --arg dst "$dst" --arg src "$src_en" '.template_files_i18n.en // [] | any(.dst == $dst and .src == $src)' "$manifest_path")"
            else
                has_en_mapping="false"
            fi

            if [ "$has_en_mapping" != "true" ]; then
                record_check "Capability English template mapping" "fail" "能力 $capability 缺少 template_files_i18n.en 映射: $src -> $src_en"
                mapping_fail=1
                continue
            fi

            mapped_count=$((mapped_count + 1))
        done <<< "$entries"
    done
    shopt -u nullglob

    if [ "$template_entry_count" -eq 0 ]; then
        record_check "Capability English template mapping" "pass" "未发现可检查的 templates 模板条目"
        return
    fi

    if [ "$mapping_fail" -eq 0 ] && [ "$mapped_count" -eq "$template_entry_count" ]; then
        record_check "Capability English template mapping" "pass" "所有模板条目都声明了英文学段映射并可访问"
        return
    fi

    if [ "$mapping_fail" -eq 0 ]; then
        record_check "Capability English template mapping" "fail" "部分模板条目缺少英文学段映射"
    fi
}

check_qna_guidance() {
    if [ ! -f "$QAA_FILE" ]; then
        record_check "Q&A locale guidance" "fail" "Q&A-TEMPLATE.md 不存在"
        return
    fi

    if ! grep -Fq -- '--locale' "$QAA_FILE"; then
        record_check "Q&A locale guidance" "fail" "Q&A 未说明 locale 选择入口"
        return
    fi

    if ! grep -Eq '语言|locale|Locale' "$QAA_FILE"; then
        record_check "Q&A locale guidance" "fail" "Q&A 未出现语言选择相关说明"
        return
    fi

    if ! grep -Eq 'zh-CN|English|en' "$QAA_FILE"; then
        record_check "Q&A locale guidance" "fail" "Q&A 未明确语言选项（zh-CN / en）"
        return
    fi

    if ! grep -Eq '默认|推荐|中文' "$QAA_FILE"; then
        record_check "Q&A locale guidance" "fail" "Q&A 未明确中文默认或推荐策略"
        return
    fi

    if ! grep -Fq '双语提问总规则' "$QAA_FILE"; then
        record_check "Q&A locale guidance" "fail" "Q&A 未声明 Skill 运行时提问必须中英双语"
        return
    fi

    if ! grep -Fq 'Please choose the documentation language' "$QAA_FILE"; then
        record_check "Q&A locale guidance" "fail" "部署语言问题缺少英文说明"
        return
    fi

    if ! grep -Fq '[1] 中文（默认，推荐）/ Chinese (default, recommended)' "$QAA_FILE"; then
        record_check "Q&A locale guidance" "fail" "部署语言默认选项未按中英双语展示"
        return
    fi

    if ! grep -Fq '选项 / Options' "$QAA_FILE"; then
        record_check "Q&A locale guidance" "fail" "Q&A 选项未使用中英双语 Options 标记"
        return
    fi

    if ! grep -Fq '启用 / Enable' "$QAA_FILE"; then
        record_check "Q&A locale guidance" "fail" "可选能力启用选项缺少英文"
        return
    fi

    if ! grep -Fq '跳过 / Skip' "$QAA_FILE"; then
        record_check "Q&A locale guidance" "fail" "可选能力跳过选项缺少英文"
        return
    fi

    if ! grep -Fq '自定义需求 / Custom request' "$QAA_FILE"; then
        record_check "Q&A locale guidance" "fail" "可选能力自定义需求选项缺少英文"
        return
    fi

    if ! grep -Fq '请选择 / Please choose' "$QAA_FILE"; then
        record_check "Q&A locale guidance" "fail" "融合模式选择提示缺少英文"
        return
    fi

    if ! grep -Fq '保留现有配置 / Keep the existing configuration' "$QAA_FILE"; then
        record_check "Q&A locale guidance" "fail" "融合模式保留选项缺少英文"
        return
    fi

    record_check "Q&A locale guidance" "pass" "Q&A 包含中文默认推荐的部署语言选择、双语提问规则和双语选项"
}

check_readme_pair
check_template_trees
check_capability_mapping
check_qna_guidance

if [ "$FAILED" -eq 0 ]; then
    STATUS="pass"
    DESCRIPTION="i18n 漂移检查通过。中文 README、英文 README 镜像、README 格式签名、templates 镜像树、模板标题层级、模板格式签名、能力英文字段与 Q&A 指南都正常。"
else
    STATUS="needs_fix"
    DESCRIPTION="检测到 i18n 漂移问题：${FAILED} 项失败。请修正后重试。"
fi

if [ "$JSON_MODE" = true ]; then
    cat <<JSONEOF
{
  "status": "${STATUS}",
  "target": "$(json_escape "$TARGET")",
  "checks": [${CHECKS}],
  "summary": {
    "total": ${TOTAL},
    "passed": ${PASSED},
    "failed": ${FAILED}
  },
  "description_nl": "$(json_escape "$DESCRIPTION")"
}
JSONEOF
else
    echo "=== i18n Drift Check ==="
    echo "项目路径: $TARGET"
    echo "状态: $STATUS"
    echo "描述: $DESCRIPTION"
    echo ""
    echo "结果:
"
    echo "$CHECKS"
fi

if [ "$STATUS" = "pass" ]; then
    exit 0
fi
exit 1
