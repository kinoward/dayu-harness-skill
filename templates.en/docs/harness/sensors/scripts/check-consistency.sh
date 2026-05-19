#!/usr/bin/env bash
# =============================================================================
# Documentation consistency checks (C1-C4)
# Checks the completeness and integrity of AGENTS.md documentation structure.
#
# Usage:
#   check-consistency.sh [project_root] [--json]
#   check-consistency.sh --json [project_root]
#
# Exit codes: 0=all pass, 1=at least one failure, 2=script error
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
PROJECT_ROOT="."
JSON_MODE=false
ALLOWED_OPTIONAL_CAPABILITIES=(
    "ai.execution"
    "ai.memory"
    "git.commit-format"
    "github.branch-protection"
    "github.pr"
    "github.release-please"
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
            echo "Usage: check-consistency.sh [project_root] [--json]"
            echo ""
            echo "Check AGENTS.md documentation structure:"
            echo "  C1  Link validity   - Verify local links in AGENTS.md are reachable"
            echo "  C2  Index count     - Verify explicit document counts match actual links"
            echo "  C3  Orphan detection - Detect .md files under docs/ not referenced by any AGENTS.md"
            echo "  C4  Script integrity - Verify referenced scripts/config files exist and are executable"
            echo ""
            echo "Options:"
            echo "  --json    Output structured JSON to stdout"
            echo "  --help    Show this help message"
            exit 0
            ;;
        *)
            PROJECT_ROOT="$arg"
            ;;
    esac
done

# Normalize project root path
_input_root="$PROJECT_ROOT"
PROJECT_ROOT="$(cd "$_input_root" 2>/dev/null && pwd)" || {
    echo "Error: cannot enter project directory '$_input_root'" >&2
    exit 2
}

# ---------------------------------------------------------------------------
# Temporary files (shared across functions)
# ---------------------------------------------------------------------------
TMP_WORKDIR=""
if [ -n "${TMPDIR:-}" ] && [ -d "${TMPDIR:-}" ] && [ -w "${TMPDIR:-}" ]; then
    TMP_WORKDIR="$(mktemp -d "${TMPDIR%/}/dayu-harness.XXXXXX" 2>/dev/null || true)"
fi
if [ -z "$TMP_WORKDIR" ]; then
    TMP_WORKDIR="$PROJECT_ROOT/.dayu-harness-tmp.$$"
    mkdir -p "$TMP_WORKDIR" || {
        echo "Error: cannot create temporary directory '$TMP_WORKDIR'" >&2
        exit 2
    }
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
# Helper functions
# ---------------------------------------------------------------------------

# Resolve a relative path: given AGENTS.md directory and target link, return path relative to project root.
# Parameters: $1 = AGENTS.md directory (relative to project root), $2 = link target
resolve_relative_path() {
    local base_dir="$1"
    local target="$2"

    # Strip URL fragment.
    target="${target%%\#*}"

    # Empty target.
    [ -z "$target" ] && { echo ""; return; }

    # Remove leading slash.
    case "$target" in
        /*)
            target="${target#/}"
            ;;
    esac

    # If the link already starts with a docs/ prefix, it may already be project-root relative.
    # Check whether target exists from the project root.
    if [ -f "$PROJECT_ROOT/$target" ] || [ -d "$PROJECT_ROOT/$target" ]; then
        echo "$target"
        return
    fi

    # Combine base_dir and target, then normalize path.
    local combined
    if [ "$base_dir" = "." ]; then
        combined="$target"
    else
        combined="$base_dir/$target"
    fi

    # Normalize .. and .
    while echo "$combined" | grep -q '/\.\./\|/\.\.$\|/\./\|/\.$'; do
        combined=$(echo "$combined" | sed 's|/\./|/|g; s|/\.$||')
        combined=$(echo "$combined" | sed 's|/[^/]*/\.\./|/|g; s|/[^/]*/\.\.$||')
    done

    echo "$combined"
}

# Extract all markdown links from a file.
# Parameters: $1 = absolute file path
# Output: each line: "line_number<TAB>target<TAB>raw_line"
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

# Escape JSON strings
json_escape() {
    local s="$1"
    s=$(echo "$s" | sed 's/\\/\\\\/g; s/"/\\"/g')
    # Replace newlines with literal \n.
    s=$(echo "$s" | awk 'BEGIN{ORS="\\n"}{print}' | sed 's/\\n$//')
    echo "$s"
}

# Count array elements by counting lines in a file.
count_lines() {
    local file="$1"
    if [ -f "$file" ]; then
        wc -l < "$file" | tr -d ' '
    else
        echo 0
    fi
}

# Convert each file line to a quoted JSON array element.
# Use sed rather than a loop to avoid subshell issues.
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
# Find all AGENTS.md files
# ---------------------------------------------------------------------------
find_agents_files() {
    # Include root AGENTS.md, then AGENTS.md under docs/ and its descendants.
    [ -f "$PROJECT_ROOT/AGENTS.md" ] && echo "AGENTS.md"
    if [ -d "$PROJECT_ROOT/docs" ]; then
        find "$PROJECT_ROOT/docs" -name "AGENTS.md" -type f 2>/dev/null | while IFS= read -r f; do
            echo "${f#"$PROJECT_ROOT"/}"
        done
    fi
}

# ---------------------------------------------------------------------------
# C1: Link validity
# ---------------------------------------------------------------------------
run_c1() {
    local broken_count=0

    # Clear issue files and reference tracking file.
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

            # Skip external links.
            if is_external_link "$link"; then
                continue
            fi

            # Resolve relative path.
            resolved="$(resolve_relative_path "$base_dir" "$link")"
            [ -z "$resolved" ] && continue

            # Check if target exists.
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
                        echo "$agents_file:$link_line\t$resolved\tOptional capability not in allowlist: $optional_capability" >> "$C1_ISSUES_FILE"
                    fi
                else
                    echo "$agents_file:$link_line\t$resolved\tTarget does not exist" >> "$C1_ISSUES_FILE"
                fi
            else
                # Record referenced paths for C3.
                echo "${resolved%/}" >> "$REFERENCED_FILE"
            fi
        done

        # Record local paths wrapped in backticks in AGENTS.md.
        # Core indexes may expose optional capability entry points in backticks and must include a valid capability ID.
        # Keep these paths for glob/placeholder cases to support orphan detection.
        # If these paths exist, they should count as referenced to avoid false orphan reports during full deployment.
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

    # Deduplicate referenced files.
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
# C2: Index count consistency
# ---------------------------------------------------------------------------
# Check whether explicitly stated document counts in AGENTS.md match actual list links.
# Supported count terms:
#   - Legacy Chinese units: item, article, entry, record
#   - English: items, documents, docs, files, entries
run_c2() {
    local mismatch_count=0
    : > "$C2_ISSUES_FILE"

    find_agents_files | while IFS= read -r agents_file; do
        [ -z "$agents_file" ] && continue
        full_path="$PROJECT_ROOT/$agents_file"
        [ -f "$full_path" ] || continue

        # Extract all explicit count claims.
        # Pattern: number + optional spaces + count unit.
        count_pattern='[0-9]+[[:space:]]*(个|篇|项|条|items|documents|docs|files|entries)'

        count_claims=$(grep -oE "$count_pattern" "$full_path" 2>/dev/null || true)
        [ -z "$count_claims" ] && continue

        # Count list item links in the directory index (or Directory Index) section.
        actual_count="$(count_directory_index_links "$full_path")"

        # Process each count declaration.
        echo "$count_claims" | while IFS= read -r claim; do
            [ -z "$claim" ] && continue

            claimed_num=$(echo "$claim" | grep -oE '[0-9]+' | head -1)

            # Find the line number of the count declaration.
            claim_line=$(grep -nF "$claim" "$full_path" 2>/dev/null | head -1 | cut -d: -f1)

            scope_count=$actual_count
            scope_desc="$agents_file"

            if [ -n "$claim_line" ] && [ "$claim_line" -gt 0 ] 2>/dev/null; then
                # Check whether this declaration is near a subdirectory AGENTS.md reference.
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
                echo "$agents_file declared '$claim', but found $scope_count list item links in $scope_desc" >> "$C2_ISSUES_FILE"
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
# C3: Orphan detection
# ---------------------------------------------------------------------------
run_c3() {
    local orphan_count=0
    : > "$C3_ISSUES_FILE"

    if [ ! -d "$PROJECT_ROOT/docs" ]; then
        echo "C3_PASS"
        return
    fi

    # Collect all .md files under docs/.
    find "$PROJECT_ROOT/docs" -name "*.md" -type f 2>/dev/null | while IFS= read -r md_file; do
        [ -z "$md_file" ] && continue
        rel_path="${md_file#"$PROJECT_ROOT"/}"

        # Check whether each file is referenced.
        if ! grep -Fqx "$rel_path" "$REFERENCED_FILE" 2>/dev/null; then
            # Also check directory-style references (for example, docs/harness/guides/ instead of docs/harness/guides/AGENTS.md).
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
# C4: Script integrity
# ---------------------------------------------------------------------------
run_c4() {
    local script_issue_count=0
    : > "$C4_ISSUES_FILE"

    # Collect all referenced script/config file paths.
    refs_file="$TMP_WORKDIR/c4-refs.txt"
    : > "$refs_file"

    # Extract references from all AGENTS.md files.
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

    # Extract references from harness guide/review documents.
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

    # Deduplicate references.
    if [ -s "$refs_file" ]; then
        sort -u "$refs_file" > "${refs_file}.tmp" && mv "${refs_file}.tmp" "$refs_file"
    fi

    # Check each reference, focusing on scripts and config files.
    while IFS= read -r ref; do
        [ -z "$ref" ] && continue

        case "$ref" in
            *.sh|*.bash|.husky/*|commitlint.config.*|*.config.*|.prettierrc*|.eslintrc*)
                ;;
            *) continue ;;
        esac

        full_ref="$PROJECT_ROOT/$ref"

        if [ ! -f "$full_ref" ]; then
            echo "$ref (file does not exist)" >> "$C4_ISSUES_FILE"
            continue
        fi

        # For script files, verify executable bit.
        case "$ref" in
            *.sh|*.bash|.husky/*)
                if [ ! -x "$full_ref" ]; then
                    echo "$ref (not executable)" >> "$C4_ISSUES_FILE"
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
# Output
# ---------------------------------------------------------------------------

# Build text output
output_text() {
    local c1_status="$1"
    local c2_status="$2"
    local c3_status="$3"
    local c4_status="$4"

    echo "=== Documentation Consistency Check ==="
    echo "Project path: $PROJECT_ROOT"
    echo ""

    # C1
    echo "--- C1: Link validity ---"
    if [ "$c1_status" = "pass" ]; then
        echo "  Status: pass"
        echo "  All local links in AGENTS.md are valid."
    else
        echo "  Status: fail"
        echo "  Found $(count_lines "$C1_ISSUES_FILE") broken link(s):"
        while IFS= read -r issue; do
            [ -z "$issue" ] && continue
            echo "    ✗ $issue"
        done < "$C1_ISSUES_FILE"
    fi
    echo ""

    # C2
    echo "--- C2: Index count ---"
    if [ "$c2_status" = "pass" ]; then
        echo "  Status: pass"
        echo "  All explicitly declared document counts match actual links."
    else
        echo "  Status: fail"
        echo "  Found $(count_lines "$C2_ISSUES_FILE") count mismatch(es):"
        while IFS= read -r issue; do
            [ -z "$issue" ] && continue
            echo "    ✗ $issue"
        done < "$C2_ISSUES_FILE"
    fi
    echo ""

    # C3
    echo "--- C3: Orphan detection ---"
    if [ "$c3_status" = "pass" ]; then
        echo "  Status: pass"
        echo "  No unreferenced .md files under docs/."
    else
        echo "  Status: fail"
        echo "  Found $(count_lines "$C3_ISSUES_FILE") orphan document(s):"
        while IFS= read -r issue; do
            [ -z "$issue" ] && continue
            echo "    ✗ $issue"
        done < "$C3_ISSUES_FILE"
    fi
    echo ""

    # C4
    echo "--- C4: Script integrity ---"
    if [ "$c4_status" = "pass" ]; then
        echo "  Status: pass"
        echo "  All referenced scripts and config files exist and are executable."
    else
        echo "  Status: fail"
        echo "  Found $(count_lines "$C4_ISSUES_FILE") issue(s):"
        while IFS= read -r issue; do
            [ -z "$issue" ] && continue
            echo "    ✗ $issue"
        done < "$C4_ISSUES_FILE"
    fi
    echo ""

    # Summary
    echo "=== Check summary ==="
    local total=4
    local passed=0
    local failed=0
    [ "$c1_status" = "pass" ] && passed=$((passed + 1)) || failed=$((failed + 1))
    [ "$c2_status" = "pass" ] && passed=$((passed + 1)) || failed=$((failed + 1))
    [ "$c3_status" = "pass" ] && passed=$((passed + 1)) || failed=$((failed + 1))
    [ "$c4_status" = "pass" ] && passed=$((passed + 1)) || failed=$((failed + 1))

    echo "Total: $total, Passed: $passed, Failed: $failed"
}

# Build JSON output
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

    # Natural-language summary.
    local desc=""
    if [ "$failed" -eq 0 ]; then
        desc="All 4 checks passed. Documentation consistency is healthy."
    else
        desc="Found $failed check failure(s) that need attention."
        c1issues=$(count_lines "$C1_ISSUES_FILE")
        c2issues=$(count_lines "$C2_ISSUES_FILE")
        c3issues=$(count_lines "$C3_ISSUES_FILE")
        c4issues=$(count_lines "$C4_ISSUES_FILE")
        [ "$c1issues" -gt 0 ] && desc="$desc C1: $c1issues broken link(s);"
        [ "$c2issues" -gt 0 ] && desc="$desc C2: $c2issues count mismatch(es);"
        [ "$c3issues" -gt 0 ] && desc="$desc C3: $c3issues orphan document(s);"
        [ "$c4issues" -gt 0 ] && desc="$desc C4: $c4issues script/config issue(s);"
    fi
    desc=$(json_escape "$desc")

    # C1 detail
    c1_count=$(count_lines "$C1_ISSUES_FILE")
    if [ "$c1_count" -eq 0 ]; then
        c1_detail="All local links in AGENTS.md are valid."
    else
        c1_detail="Found $c1_count broken link(s)."
    fi
    c1_detail=$(json_escape "$c1_detail")

    # C2 detail
    c2_count=$(count_lines "$C2_ISSUES_FILE")
    if [ "$c2_count" -eq 0 ]; then
        c2_detail="All explicitly declared document counts match actual links."
    else
        c2_detail="Found $c2_count count mismatch(es)."
    fi
    c2_detail=$(json_escape "$c2_detail")

    # C3 detail
    c3_count=$(count_lines "$C3_ISSUES_FILE")
    if [ "$c3_count" -eq 0 ]; then
        c3_detail="No unreferenced .md files under docs/."
    else
        c3_detail="Found $c3_count unreferenced .md files in docs/."
    fi
    c3_detail=$(json_escape "$c3_detail")

    # C4 detail
    c4_count=$(count_lines "$C4_ISSUES_FILE")
    if [ "$c4_count" -eq 0 ]; then
        c4_detail="All referenced scripts and config files exist and are executable."
    else
        c4_detail="Found $c4_count script/config issue(s)."
    fi
    c4_detail=$(json_escape "$c4_detail")

    # Build issues arrays for each check.
    c1_issues_json=$(file_to_json_array "$C1_ISSUES_FILE")
    c2_issues_json=$(file_to_json_array "$C2_ISSUES_FILE")
    c3_issues_json=$(file_to_json_array "$C3_ISSUES_FILE")
    c4_issues_json=$(file_to_json_array "$C4_ISSUES_FILE")

    c1_status_json="pass"; [ "$c1_status" != "pass" ] && c1_status_json="fail"
    c2_status_json="pass"; [ "$c2_status" != "pass" ] && c2_status_json="fail"
    c3_status_json="pass"; [ "$c3_status" != "pass" ] && c3_status_json="fail"
    c4_status_json="pass"; [ "$c4_status" != "pass" ] && c4_status_json="fail"

    cat <<JSONEOF
{
  "checks": [
    {"id":"C1","name":"Link validity","status":"$c1_status_json","issues":[$c1_issues_json],"detail":"$c1_detail"},
    {"id":"C2","name":"Index count","status":"$c2_status_json","issues":[$c2_issues_json],"detail":"$c2_detail"},
    {"id":"C3","name":"Orphan detection","status":"$c3_status_json","issues":[$c3_issues_json],"detail":"$c3_detail"},
    {"id":"C4","name":"Script integrity","status":"$c4_status_json","issues":[$c4_issues_json],"detail":"$c4_detail"}
  ],
  "summary": {"total":$total,"passed":$passed,"failed":$failed},
  "description_nl":"$desc"
}
JSONEOF
}

# ---------------------------------------------------------------------------
# Main flow
# ---------------------------------------------------------------------------
main() {
    # Must run C1 first because it populates REFERENCED_FILE, which C3 depends on.
    c1_result="$(run_c1)"

    c2_result="$(run_c2)"

    c3_result="$(run_c3)"

    c4_result="$(run_c4)"

    # Parse results.
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

    # Exit status.
    if [ "$c1_status" = "fail" ] || [ "$c2_status" = "fail" ] || [ "$c3_status" = "fail" ] || [ "$c4_status" = "fail" ]; then
        exit 1
    fi
    exit 0
}

main
