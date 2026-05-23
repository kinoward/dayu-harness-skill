#!/usr/bin/env bash
# =============================================================================
# 文档一致性检查 (C1-C4)
# 检查 AGENTS.md 文档体系的完整性
#
# 用法:
#   check-consistency.sh [project_root] [--json]
#   check-consistency.sh --json [project_root]
#
# 退出码: 0=全部通过, 1=存在失败, 2=脚本错误
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------
PROJECT_ROOT="."
JSON_MODE=false
ALLOWED_OPTIONAL_CAPABILITIES=(
    "ai.execution"
    "ai.memory"
    "git.commit-format"
    "github.branch-protection"
    "github.pr"
    "github.repository-settings"
    "github.issue"
    "github.release-please"
    "quality.tdd"
    "knowledge.archive"
    "knowledge.adr"
    "knowledge.research"
    "knowledge.troubleshooting"
    "project.context"
    "project.gitignore"
    "quality.node-tooling"
    "quality.practices"
    "release.versioning"
)

for arg in "$@"; do
    case "$arg" in
        --json)
            JSON_MODE=true
            ;;
        --help|-h)
            echo "用法: check-consistency.sh [project_root] [--json]"
            echo ""
            echo "检查 AGENTS.md 文档体系的完整性:"
            echo "  C1  链接有效性  - 验证 AGENTS.md 中的本地链接是否可达"
            echo "  C2  索引计数    - 验证显式声明的文档数量与实际一致"
            echo "  C3  孤儿检测    - 检测 docs/ 下未被任何 AGENTS.md 引用的 .md 文件"
            echo "  C4  脚本完整性  - 验证引用的脚本和配置文件存在且可执行"
            echo ""
            echo "选项:"
            echo "  --json    输出结构化 JSON 到 stdout"
            echo "  --help    显示此帮助信息"
            exit 0
            ;;
        *)
            PROJECT_ROOT="$arg"
            ;;
    esac
done

# 规范化项目根路径
_input_root="$PROJECT_ROOT"
PROJECT_ROOT="$(cd "$_input_root" 2>/dev/null && pwd)" || {
    echo "错误: 无法进入项目目录 '$_input_root'" >&2
    exit 2
}

# ---------------------------------------------------------------------------
# 临时文件（用于跨函数共享数据）
# ---------------------------------------------------------------------------
TMP_WORKDIR=""
if [ -n "${TMPDIR:-}" ] && [ -d "${TMPDIR:-}" ] && [ -w "${TMPDIR:-}" ]; then
    TMP_WORKDIR="$(mktemp -d "${TMPDIR%/}/dayu-harness.XXXXXX" 2>/dev/null || true)"
fi
if [ -z "$TMP_WORKDIR" ] && [ -d "/tmp" ] && [ -w "/tmp" ]; then
    TMP_WORKDIR="$(mktemp -d "/tmp/dayu-harness.XXXXXX" 2>/dev/null || true)"
fi
if [ -z "$TMP_WORKDIR" ]; then
    echo "错误: 无法创建临时目录。请设置可写 TMPDIR，或确保 /tmp 可写；一致性检查不会回退写入项目目录。" >&2
    exit 2
fi

C1_ISSUES_FILE="$TMP_WORKDIR/c1-issues.txt"
C2_ISSUES_FILE="$TMP_WORKDIR/c2-issues.txt"
C3_ISSUES_FILE="$TMP_WORKDIR/c3-issues.txt"
C4_ISSUES_FILE="$TMP_WORKDIR/c4-issues.txt"
REFERENCED_FILE="$TMP_WORKDIR/referenced.txt"
: > "$C1_ISSUES_FILE"
: > "$C2_ISSUES_FILE"
: > "$C3_ISSUES_FILE"
: > "$C4_ISSUES_FILE"
: > "$REFERENCED_FILE"

cleanup() {
    rm -f "$C1_ISSUES_FILE" "$C2_ISSUES_FILE" "$C3_ISSUES_FILE" "$C4_ISSUES_FILE" "$REFERENCED_FILE"
    rmdir "$TMP_WORKDIR" 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------

# 解析相对路径：给定 AGENTS.md 所在目录和链接目标，返回相对于项目根的路径
# 参数: $1 = AGENTS.md 所在目录（相对于项目根）, $2 = 链接目标
resolve_relative_path() {
    local base_dir="$1"
    local target="$2"

    # 去掉 URL fragment
    target="${target%%\#*}"

    # 空目标
    [ -z "$target" ] && { echo ""; return; }

    # 如果以 / 开头，去掉前导 /
    case "$target" in
        /*)
            target="${target#/}"
            ;;
    esac

    # 如果链接以 docs/ 等已知前缀开头，可能已经是相对于项目根的路径
    # 检查 target 是否已存在于项目根
    if [ -f "$PROJECT_ROOT/$target" ] || [ -d "$PROJECT_ROOT/$target" ]; then
        echo "$target"
        return
    fi

    # 拼接 base_dir 和 target，然后规范化
    local combined
    if [ "$base_dir" = "." ]; then
        combined="$target"
    else
        combined="$base_dir/$target"
    fi

    # 规范化 .. 和 .
    while echo "$combined" | grep -q '/\.\./\|/\.\.$\|/\./\|/\.$'; do
        combined=$(echo "$combined" | sed 's|/\./|/|g; s|/\.$||')
        combined=$(echo "$combined" | sed 's|/[^/]*/\.\./|/|g; s|/[^/]*/\.\.$||')
    done

    echo "$combined"
}

# 从文件中提取所有 markdown 链接
# 参数: $1 = 文件路径（绝对路径）
# 输出: 每行 "line_number<TAB>target<TAB>raw_line"
extract_markdown_links() {
    local file="$1"
    [ -f "$file" ] || return 0

    awk '
    {
        line = $0
        while (match(line, /\[[^]]+\]\([^)]*\)/)) {
            raw = substr(line, RSTART, RLENGTH)
            target = raw
            sub(/^.*\(/, "", target)
            sub(/\).*/, "", target)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", target)
            print NR "\t" target "\t" $0
            line = substr(line, RSTART + RLENGTH)
        }
    }
    ' "$file"
}

is_external_link() {
    local path="$1"
    case "$path" in
        http://*|https://*|mailto:*|\#*) return 0 ;;
        *) return 1 ;;
    esac
}

is_allowed_optional_capability() {
    local capability="$1"
    local item
    [ -z "$capability" ] && return 1

    for item in "${ALLOWED_OPTIONAL_CAPABILITIES[@]}"; do
        [ "$item" = "$capability" ] && return 0
    done
    return 1
}

extract_optional_capability() {
    local raw_line="$1"
    local capability=""
    local clean_line

    clean_line="${raw_line//\`/}"
    if [[ "$clean_line" =~ (可选|Optional)[：:][[:space:]]*([A-Za-z0-9._-]+) ]]; then
        capability="${BASH_REMATCH[2]}"
    fi

    printf '%s' "$capability"
}

is_directory_index_header() {
    local line="$1"
    [[ "$line" =~ ^[[:space:]]*#{1,6}[[:space:]]*(目录索引|Directory Index)[[:space:]]*$ ]]
}

# JSON 字符串转义
json_escape() {
    local s="$1"
    s=$(echo "$s" | sed 's/\\/\\\\/g; s/"/\\"/g')
    # 将换行符替换为 \n
    s=$(echo "$s" | awk 'BEGIN{ORS="\\n"}{print}' | sed 's/\\n$//')
    echo "$s"
}

# 获取数组元素数量（从文件中读取行数）
count_lines() {
    local file="$1"
    if [ -f "$file" ]; then
        wc -l < "$file" | tr -d ' '
    else
        echo 0
    fi
}

# 将文件中的每一行输出为带引号的 JSON 字符串数组元素
# 使用 sed 而非循环，避免 subshell 问题
file_to_json_array() {
    local file="$1"
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        return 0
    fi
    local first=true
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        if [ "$first" = true ]; then
            first=false
        else
            printf ','
        fi
        printf '"%s"' "$(json_escape "$line")"
    done < "$file"
}

count_directory_index_links() {
    local file="$1"
    [ -f "$file" ] || { echo 0; return; }

    local found_index=0
    local in_index=0
    local count=0
    local line

    while IFS= read -r line; do
        if is_directory_index_header "$line"; then
            found_index=1
            in_index=1
            continue
        fi

        if [ "$in_index" -eq 1 ]; then
            if echo "$line" | grep -qE '^[[:space:]]*#{1,6}[[:space:]]+'; then
                break
            fi
            if echo "$line" | grep -qE '^[[:space:]]*[-*][[:space:]]+\[.+\]\([^)]+\)'; then
                count=$((count + 1))
            fi
        fi
    done < "$file"

    if [ "$found_index" -eq 0 ]; then
        count=$(grep -cE '^[[:space:]]*[-*][[:space:]]+\[.+\]\([^)]+\)' "$file" 2>/dev/null || echo 0)
    fi

    echo "$count"
}

# ---------------------------------------------------------------------------
# 查找所有 AGENTS.md 文件
# ---------------------------------------------------------------------------
find_agents_files() {
    # 查找根目录、docs/、以及 docs/ 的所有子目录中的 AGENTS.md
    [ -f "$PROJECT_ROOT/AGENTS.md" ] && echo "AGENTS.md"
    if [ -d "$PROJECT_ROOT/docs" ]; then
        find "$PROJECT_ROOT/docs" -name "AGENTS.md" -type f 2>/dev/null | while IFS= read -r f; do
            echo "${f#"$PROJECT_ROOT"/}"
        done
    fi
}

# ---------------------------------------------------------------------------
# C1: 链接有效性
# ---------------------------------------------------------------------------
run_c1() {
    local broken_count=0

    # 清空 issue 文件和引用文件
    : > "$C1_ISSUES_FILE"
    : > "$REFERENCED_FILE"

    find_agents_files | while IFS= read -r agents_file; do
        [ -z "$agents_file" ] && continue

        base_dir="$(dirname "$agents_file")"

        extract_markdown_links "$PROJECT_ROOT/$agents_file" | while IFS=$'\t' read -r link_line link raw_line; do
            link_line="${link_line-}"
            link="${link-}"
            raw_line="${raw_line-}"
            [ -z "$link" ] && continue

            # 跳过外部链接
            if is_external_link "$link"; then
                continue
            fi

            # 解析相对路径
            resolved="$(resolve_relative_path "$base_dir" "$link")"
            [ -z "$resolved" ] && continue

            # 检查目标是否存在
            full_path="$PROJECT_ROOT/$resolved"
            exists=false
            if [ -f "$full_path" ]; then
                exists=true
            elif [ -d "$full_path" ]; then
                exists=true
            fi

            if [ "$exists" = false ]; then
                optional_capability="$(extract_optional_capability "$raw_line")"
                if [ -n "$optional_capability" ]; then
                    if ! is_allowed_optional_capability "$optional_capability"; then
                        echo "$agents_file:$link_line\t$resolved\t可选 capability 未在白名单: $optional_capability" >> "$C1_ISSUES_FILE"
                    fi
                else
                    echo "$agents_file:$link_line\t$resolved\t目标不存在" >> "$C1_ISSUES_FILE"
                fi
            else
                # 记录被引用路径（用于 C3）
                echo "${resolved%/}" >> "$REFERENCED_FILE"
            fi
        done

        # 记录 AGENTS.md 中用反引号声明的本地路径。
        # Core 索引允许链接可选 capability 入口，但必须带合法 capability id；
        # 同时保留反引号路径用于通配/占位场景，便于孤儿检测。
        # 若这些路径实际存在，仍应计入 C3 引用，避免全量部署时误报孤儿。
        grep -oE '`[^`]+`' "$PROJECT_ROOT/$agents_file" 2>/dev/null | \
            sed 's/^`//;s/`$//' | while IFS= read -r code_path; do
                [ -z "$code_path" ] && continue
                resolved="$(resolve_relative_path "$base_dir" "$code_path")"
                [ -z "$resolved" ] && continue

                full_path="$PROJECT_ROOT/$resolved"
                if [ -f "$full_path" ] || [ -d "$full_path" ]; then
                    echo "${resolved%/}" >> "$REFERENCED_FILE"
                fi
            done
    done

    # 去重引用文件
    if [ -s "$REFERENCED_FILE" ]; then
        sort -u "$REFERENCED_FILE" > "${REFERENCED_FILE}.tmp" && mv "${REFERENCED_FILE}.tmp" "$REFERENCED_FILE"
    fi

    broken_count=$(count_lines "$C1_ISSUES_FILE")
    if [ "$broken_count" -eq 0 ]; then
        echo "C1_PASS"
    else
        echo "C1_FAIL"
    fi
}

# ---------------------------------------------------------------------------
# C2: 索引计数一致性
# ---------------------------------------------------------------------------
# 检查 AGENTS.md 中显式声明的文档数量是否与实际列出的链接数一致
# 支持的计数模式:
#   - 中文: N 个, N 篇, N 项, N 条
#   - 英文: N items, N documents, N docs, N files, N entries
run_c2() {
    local mismatch_count=0
    : > "$C2_ISSUES_FILE"

    find_agents_files | while IFS= read -r agents_file; do
        [ -z "$agents_file" ] && continue
        full_path="$PROJECT_ROOT/$agents_file"
        [ -f "$full_path" ] || continue

        # 提取所有显式计数声明
        # 模式: 数字 + 可选空格 + 计数词
        count_pattern='[0-9]+[[:space:]]*(个|篇|项|条|items|documents|docs|files|entries)'

        count_claims=$(grep -oE "$count_pattern" "$full_path" 2>/dev/null || true)
        [ -z "$count_claims" ] && continue

        # 统计该文件目录索引（或 Directory Index）中的列表项链接数
        actual_count="$(count_directory_index_links "$full_path")"

        # 处理每个计数声明
        echo "$count_claims" | while IFS= read -r claim; do
            [ -z "$claim" ] && continue

            claimed_num=$(echo "$claim" | grep -oE '[0-9]+' | head -1)

            # 查找计数声明所在行
            claim_line=$(grep -nF "$claim" "$full_path" 2>/dev/null | head -1 | cut -d: -f1)

            scope_count=$actual_count
            scope_desc="$agents_file"

            if [ -n "$claim_line" ] && [ "$claim_line" -gt 0 ] 2>/dev/null; then
                # 查找该声明附近是否引用了子目录 AGENTS.md
                start_line=$((claim_line > 5 ? claim_line - 5 : 1))
                context=$(tail -n "+$start_line" "$full_path" 2>/dev/null | head -11 || true)

                sub_agents=$(echo "$context" | grep -oE '\[[^]]*\]\(([^)]+/)?AGENTS\.md\)' | head -1 || true)

                if [ -n "$sub_agents" ]; then
                    sub_path=$(echo "$sub_agents" | sed -E 's/\[[^]]*\]\(([^)]*)\)/\1/')
                    base_dir="$(dirname "$agents_file")"
                    resolved_sub="$(resolve_relative_path "$base_dir" "$sub_path")"

                    if [ -f "$PROJECT_ROOT/$resolved_sub" ]; then
                        scope_count="$(count_directory_index_links "$PROJECT_ROOT/$resolved_sub")"
                        scope_desc="$resolved_sub"
                    fi
                fi
            fi

            if [ "$claimed_num" != "$scope_count" ]; then
                echo "$agents_file 声明了 '$claim'，但实际在 $scope_desc 中找到 $scope_count 个列表项链接" >> "$C2_ISSUES_FILE"
            fi
        done
    done

    mismatch_count=$(count_lines "$C2_ISSUES_FILE")
    if [ "$mismatch_count" -eq 0 ]; then
        echo "C2_PASS"
    else
        echo "C2_FAIL"
    fi
}

# ---------------------------------------------------------------------------
# C3: 孤儿检测
# ---------------------------------------------------------------------------
run_c3() {
    local orphan_count=0
    : > "$C3_ISSUES_FILE"

    if [ ! -d "$PROJECT_ROOT/docs" ]; then
        echo "C3_PASS"
        return
    fi

    # 收集 docs/ 下的所有 .md 文件
    find "$PROJECT_ROOT/docs" -name "*.md" -type f 2>/dev/null | while IFS= read -r md_file; do
        [ -z "$md_file" ] && continue
        rel_path="${md_file#"$PROJECT_ROOT"/}"

        # 检查是否被引用
        if ! grep -Fqx "$rel_path" "$REFERENCED_FILE" 2>/dev/null; then
            # 也检查是否被作为目录引用（例如 docs/harness/guides/ 而非 docs/harness/guides/AGENTS.md）
            dir_part=$(dirname "$rel_path")
            if ! grep -Fqx "$dir_part" "$REFERENCED_FILE" 2>/dev/null; then
                echo "$rel_path" >> "$C3_ISSUES_FILE"
            fi
        fi
    done

    orphan_count=$(count_lines "$C3_ISSUES_FILE")
    if [ "$orphan_count" -eq 0 ]; then
        echo "C3_PASS"
    else
        echo "C3_FAIL"
    fi
}

# ---------------------------------------------------------------------------
# C4: 脚本完整性
# ---------------------------------------------------------------------------
run_c4() {
    local script_issue_count=0
    : > "$C4_ISSUES_FILE"

    # 收集所有被引用的脚本/配置文件路径
    refs_file="$TMP_WORKDIR/c4-refs.txt"
    : > "$refs_file"

    # 从所有 AGENTS.md 中提取引用
    find_agents_files | while IFS= read -r agents_file; do
        [ -z "$agents_file" ] && continue
        full_path="$PROJECT_ROOT/$agents_file"
        [ -f "$full_path" ] || continue

        base_dir="$(dirname "$agents_file")"
        extract_markdown_links "$full_path" | while IFS=$'\t' read -r _line_no link _raw; do
            [ -z "$link" ] && continue
            if is_external_link "$link"; then
                continue
            fi
            resolved="$(resolve_relative_path "$base_dir" "$link")"
            [ -z "$resolved" ] && continue
            echo "$resolved" >> "$refs_file"
        done
    done

    # 从 harness guide/review 文档中提取引用
    if [ -d "$PROJECT_ROOT/docs/harness" ]; then
        find "$PROJECT_ROOT/docs/harness/guides" "$PROJECT_ROOT/docs/harness/sensors/reviews" -name "*.md" -type f 2>/dev/null | while IFS= read -r practice_file; do
            [ -f "$practice_file" ] || continue
            rel="${practice_file#"$PROJECT_ROOT"/}"
            dir="$(dirname "$rel")"
            extract_markdown_links "$practice_file" | while IFS=$'\t' read -r _line_no link _raw; do
                [ -z "$link" ] && continue
                if is_external_link "$link"; then
                    continue
                fi
                resolved="$(resolve_relative_path "$dir" "$link")"
                [ -z "$resolved" ] && continue
                echo "$resolved" >> "$refs_file"
            done
        done
    fi

    # 去重
    if [ -s "$refs_file" ]; then
        sort -u "$refs_file" > "${refs_file}.tmp" && mv "${refs_file}.tmp" "$refs_file"
    fi

    # 检查每个引用：关注脚本和配置文件
    while IFS= read -r ref; do
        [ -z "$ref" ] && continue

        case "$ref" in
            *.sh|*.bash|.husky/*|commitlint.config.*|*.config.*|.prettierrc*|.eslintrc*)
                ;;
            *) continue ;;
        esac

        full_ref="$PROJECT_ROOT/$ref"

        if [ ! -f "$full_ref" ]; then
            echo "$ref (文件不存在)" >> "$C4_ISSUES_FILE"
            continue
        fi

        # 对于脚本文件，检查可执行性
        case "$ref" in
            *.sh|*.bash|.husky/*)
                if [ ! -x "$full_ref" ]; then
                    echo "$ref (不可执行)" >> "$C4_ISSUES_FILE"
                fi
                ;;
        esac
    done < "$refs_file"

    rm -f "$refs_file"

    script_issue_count=$(count_lines "$C4_ISSUES_FILE")
    if [ "$script_issue_count" -eq 0 ]; then
        echo "C4_PASS"
    else
        echo "C4_FAIL"
    fi
}

# ---------------------------------------------------------------------------
# 输出
# ---------------------------------------------------------------------------

# 构建文本输出
output_text() {
    local c1_status="$1"
    local c2_status="$2"
    local c3_status="$3"
    local c4_status="$4"

    echo "=== 文档一致性检查 ==="
    echo "项目路径: $PROJECT_ROOT"
    echo ""

    # C1
    echo "--- C1: 链接有效性 ---"
    if [ "$c1_status" = "pass" ]; then
        echo "  状态: 通过"
        echo "  所有 AGENTS.md 中的本地链接均有效。"
    else
        echo "  状态: 失败"
        echo "  发现 $(count_lines "$C1_ISSUES_FILE") 个断链:"
        while IFS= read -r issue; do
            [ -z "$issue" ] && continue
            echo "    ✗ $issue"
        done < "$C1_ISSUES_FILE"
    fi
    echo ""

    # C2
    echo "--- C2: 索引计数 ---"
    if [ "$c2_status" = "pass" ]; then
        echo "  状态: 通过"
        echo "  所有显式声明的文档计数与实际一致。"
    else
        echo "  状态: 失败"
        echo "  发现 $(count_lines "$C2_ISSUES_FILE") 处计数不一致:"
        while IFS= read -r issue; do
            [ -z "$issue" ] && continue
            echo "    ✗ $issue"
        done < "$C2_ISSUES_FILE"
    fi
    echo ""

    # C3
    echo "--- C3: 孤儿检测 ---"
    if [ "$c3_status" = "pass" ]; then
        echo "  状态: 通过"
        echo "  docs/ 下没有未被引用的 .md 文件。"
    else
        echo "  状态: 失败"
        echo "  发现 $(count_lines "$C3_ISSUES_FILE") 个孤儿文档:"
        while IFS= read -r issue; do
            [ -z "$issue" ] && continue
            echo "    ✗ $issue"
        done < "$C3_ISSUES_FILE"
    fi
    echo ""

    # C4
    echo "--- C4: 脚本完整性 ---"
    if [ "$c4_status" = "pass" ]; then
        echo "  状态: 通过"
        echo "  所有引用的脚本和配置文件均存在且可执行。"
    else
        echo "  状态: 失败"
        echo "  发现 $(count_lines "$C4_ISSUES_FILE") 个问题:"
        while IFS= read -r issue; do
            [ -z "$issue" ] && continue
            echo "    ✗ $issue"
        done < "$C4_ISSUES_FILE"
    fi
    echo ""

    # 摘要
    echo "=== 检查摘要 ==="
    local total=4
    local passed=0
    local failed=0
    [ "$c1_status" = "pass" ] && passed=$((passed + 1)) || failed=$((failed + 1))
    [ "$c2_status" = "pass" ] && passed=$((passed + 1)) || failed=$((failed + 1))
    [ "$c3_status" = "pass" ] && passed=$((passed + 1)) || failed=$((failed + 1))
    [ "$c4_status" = "pass" ] && passed=$((passed + 1)) || failed=$((failed + 1))

    echo "总计: $total, 通过: $passed, 失败: $failed"
}

# 构建 JSON 输出
output_json() {
    local c1_status="$1"
    local c2_status="$2"
    local c3_status="$3"
    local c4_status="$4"

    local total=4
    local passed=0
    local failed=0
    [ "$c1_status" = "pass" ] && passed=$((passed + 1)) || failed=$((failed + 1))
    [ "$c2_status" = "pass" ] && passed=$((passed + 1)) || failed=$((failed + 1))
    [ "$c3_status" = "pass" ] && passed=$((passed + 1)) || failed=$((failed + 1))
    [ "$c4_status" = "pass" ] && passed=$((passed + 1)) || failed=$((failed + 1))

    # 自然语言摘要
    local desc=""
    if [ "$failed" -eq 0 ]; then
        desc="全部 4 项检查通过，文档体系一致性良好。"
    else
        desc="发现 $failed 项问题需要处理。"
        c1issues=$(count_lines "$C1_ISSUES_FILE")
        c2issues=$(count_lines "$C2_ISSUES_FILE")
        c3issues=$(count_lines "$C3_ISSUES_FILE")
        c4issues=$(count_lines "$C4_ISSUES_FILE")
        [ "$c1issues" -gt 0 ] && desc="$desc C1: $c1issues 个断链;"
        [ "$c2issues" -gt 0 ] && desc="$desc C2: $c2issues 处计数不一致;"
        [ "$c3issues" -gt 0 ] && desc="$desc C3: $c3issues 个孤儿文档;"
        [ "$c4issues" -gt 0 ] && desc="$desc C4: $c4issues 个脚本问题;"
    fi
    desc=$(json_escape "$desc")

    # C1 detail
    c1_count=$(count_lines "$C1_ISSUES_FILE")
    if [ "$c1_count" -eq 0 ]; then
        c1_detail="所有 AGENTS.md 中的本地链接均有效。"
    else
        c1_detail="发现 $c1_count 个断链。"
    fi
    c1_detail=$(json_escape "$c1_detail")

    # C2 detail
    c2_count=$(count_lines "$C2_ISSUES_FILE")
    if [ "$c2_count" -eq 0 ]; then
        c2_detail="所有显式声明的文档计数与实际一致。"
    else
        c2_detail="发现 $c2_count 处计数不一致。"
    fi
    c2_detail=$(json_escape "$c2_detail")

    # C3 detail
    c3_count=$(count_lines "$C3_ISSUES_FILE")
    if [ "$c3_count" -eq 0 ]; then
        c3_detail="docs/ 下没有未被引用的 .md 文件。"
    else
        c3_detail="发现 $c3_count 个未被任何 AGENTS.md 引用的 .md 文件。"
    fi
    c3_detail=$(json_escape "$c3_detail")

    # C4 detail
    c4_count=$(count_lines "$C4_ISSUES_FILE")
    if [ "$c4_count" -eq 0 ]; then
        c4_detail="所有引用的脚本和配置文件均存在且可执行。"
    else
        c4_detail="发现 $c4_count 个脚本/配置文件问题。"
    fi
    c4_detail=$(json_escape "$c4_detail")

    # 构建每个 check 的 issues JSON 数组
    c1_issues_json=$(file_to_json_array "$C1_ISSUES_FILE")
    c2_issues_json=$(file_to_json_array "$C2_ISSUES_FILE")
    c3_issues_json=$(file_to_json_array "$C3_ISSUES_FILE")
    c4_issues_json=$(file_to_json_array "$C4_ISSUES_FILE")

    c1_status_json="pass"; [ "$c1_status" != "pass" ] && c1_status_json="fail"
    c2_status_json="pass"; [ "$c2_status" != "pass" ] && c2_status_json="fail"
    c3_status_json="pass"; [ "$c3_status" != "pass" ] && c3_status_json="fail"
    c4_status_json="pass"; [ "$c4_status" != "pass" ] && c4_status_json="fail"

    printf '{\n'
    printf '  "checks": [\n'
    printf '    {"id":"C1","name":"链接有效性","status":"%s","issues":[%s],"detail":"%s"},\n' "$c1_status_json" "$c1_issues_json" "$c1_detail"
    printf '    {"id":"C2","name":"索引计数","status":"%s","issues":[%s],"detail":"%s"},\n' "$c2_status_json" "$c2_issues_json" "$c2_detail"
    printf '    {"id":"C3","name":"孤儿检测","status":"%s","issues":[%s],"detail":"%s"},\n' "$c3_status_json" "$c3_issues_json" "$c3_detail"
    printf '    {"id":"C4","name":"脚本完整性","status":"%s","issues":[%s],"detail":"%s"}\n' "$c4_status_json" "$c4_issues_json" "$c4_detail"
    printf '  ],\n'
    printf '  "summary": {"total":%s,"passed":%s,"failed":%s},\n' "$total" "$passed" "$failed"
    printf '  "description_nl":"%s"\n' "$desc"
    printf '}\n'
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
main() {
    # 必须先运行 C1（它填充 REFERENCED_FILE，C3 依赖它）
    c1_result="$(run_c1)"

    c2_result="$(run_c2)"

    c3_result="$(run_c3)"

    c4_result="$(run_c4)"

    # 解析结果
    c1_status="pass"
    c2_status="pass"
    c3_status="pass"
    c4_status="pass"
    [ "$c1_result" = "C1_FAIL" ] && c1_status="fail"
    [ "$c2_result" = "C2_FAIL" ] && c2_status="fail"
    [ "$c3_result" = "C3_FAIL" ] && c3_status="fail"
    [ "$c4_result" = "C4_FAIL" ] && c4_status="fail"

    if [ "$JSON_MODE" = true ]; then
        output_json "$c1_status" "$c2_status" "$c3_status" "$c4_status"
    else
        output_text "$c1_status" "$c2_status" "$c3_status" "$c4_status"
    fi

    # 退出码
    if [ "$c1_status" = "fail" ] || [ "$c2_status" = "fail" ] || [ "$c3_status" = "fail" ] || [ "$c4_status" = "fail" ]; then
        exit 1
    fi
    exit 0
}

main
