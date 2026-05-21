#!/usr/bin/env bash
# Compare zh-CN and English Dayu Harness deployment outputs.
#
# This helper is intentionally scoped to deployed governance artifacts. It
# excludes run-time traces such as .git, node_modules, Claude logs, and smoke
# records so local Claude CLI smoke tests can be compared deterministically.
set -euo pipefail

JSON_MODE=false
ZH_DIR=""
EN_DIR=""

usage() {
    cat <<'EOF'
Usage:
  compare-i18n-deployments.sh [--json] <zh-deployment-dir> <en-deployment-dir>

Checks:
  - deployment artifact file trees match after excluding runtime traces
  - root GitHub constraints are not deployed
  - Git constraints are deployed in both locales
  - deployed validators pass with matching summaries
  - Markdown structure stays aligned across locales
  - non-translated machine files stay identical
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --json)
            JSON_MODE=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            if [ -z "$ZH_DIR" ]; then
                ZH_DIR="$1"
            elif [ -z "$EN_DIR" ]; then
                EN_DIR="$1"
            else
                echo "Unexpected argument: $1" >&2
                usage >&2
                exit 2
            fi
            shift
            ;;
    esac
done

if [ -z "$ZH_DIR" ] || [ -z "$EN_DIR" ]; then
    usage >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "compare-i18n-deployments.sh requires jq" >&2
    exit 2
fi

ZH_DIR="$(cd "$ZH_DIR" 2>/dev/null && pwd)" || {
    echo "Cannot resolve zh deployment dir: $ZH_DIR" >&2
    exit 2
}
EN_DIR="$(cd "$EN_DIR" 2>/dev/null && pwd)" || {
    echo "Cannot resolve en deployment dir: $EN_DIR" >&2
    exit 2
}

TMP_ROOT="${TMPDIR:-/tmp}"
mkdir -p "$TMP_ROOT"
TMP_DIR="$(mktemp -d "$TMP_ROOT/dayu-i18n-compare.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
CHECKS_FILE="$TMP_DIR/checks.jsonl"
: > "$CHECKS_FILE"

record_check() {
    local name="$1"
    local status="$2"
    local detail="$3"
    jq -cn --arg name "$name" --arg status "$status" --arg detail "$detail" \
        '{name:$name,status:$status,detail:$detail}' >> "$CHECKS_FILE"
}

collect_files() {
    local root="$1"
    find "$root" \
        -path "$root/.git" -prune \
        -o -path "$root/node_modules" -prune \
        -o -path "$root/.claude" -prune \
        -o -path "$root/.claude-dayu-plugin" -prune \
        -o -path "$root/.typescript" -prune \
        -o -type f -print |
        sed "s#^$root/##" |
        grep -Ev '(^|/)(claude-debug.*\.log|claude-session\.log|claude-interaction-record\.md|script-smoke\.log|latest|.*\.typescript)$' |
        sort
}

collect_dirs() {
    local root="$1"
    find "$root" -mindepth 1 \
        -path "$root/.git" -prune \
        -o -path "$root/node_modules" -prune \
        -o -path "$root/.claude" -prune \
        -o -path "$root/.claude-dayu-plugin" -prune \
        -o -path "$root/.typescript" -prune \
        -o -type d -print |
        sed "s#^$root/##" |
        sed '/^$/d' |
        sort
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

normalize_json_artifact() {
    local file="$1"
    local rel="$2"

    case "$rel" in
        package.json)
            jq -S 'del(.name)' "$file"
            ;;
        package-lock.json)
            jq -S 'del(.name) | if (.packages? and .packages[""]?) then .packages[""] |= del(.name) else . end' "$file"
            ;;
        *)
            jq -S '.' "$file"
            ;;
    esac
}

validator_summary() {
    local root="$1"
    local script_rel="$2"
    local out_file="$3"

    if [ ! -f "$root/$script_rel" ]; then
        return 1
    fi

    bash "$root/$script_rel" --json "$root" > "$out_file" 2>/dev/null
}

compare_validator() {
    local script_rel="$1"
    local zh_out="$TMP_DIR/zh-${script_rel//\//_}.json"
    local en_out="$TMP_DIR/en-${script_rel//\//_}.json"

    if ! validator_summary "$ZH_DIR" "$script_rel" "$zh_out"; then
        record_check "Validator: $script_rel" "fail" "zh-CN validator failed or is missing"
        return
    fi
    if ! validator_summary "$EN_DIR" "$script_rel" "$en_out"; then
        record_check "Validator: $script_rel" "fail" "English validator failed or is missing"
        return
    fi

    local zh_summary
    local en_summary
    zh_summary="$(jq -S '.summary' "$zh_out")"
    en_summary="$(jq -S '.summary' "$en_out")"

    if [ "$zh_summary" = "$en_summary" ]; then
        record_check "Validator: $script_rel" "pass" "validator summaries match"
    else
        record_check "Validator: $script_rel" "fail" "validator summaries differ"
    fi
}

ZH_FILES="$TMP_DIR/zh-files.txt"
EN_FILES="$TMP_DIR/en-files.txt"
ZH_DIRS="$TMP_DIR/zh-dirs.txt"
EN_DIRS="$TMP_DIR/en-dirs.txt"
collect_files "$ZH_DIR" > "$ZH_FILES"
collect_files "$EN_DIR" > "$EN_FILES"
collect_dirs "$ZH_DIR" > "$ZH_DIRS"
collect_dirs "$EN_DIR" > "$EN_DIRS"

if diff -u "$ZH_FILES" "$EN_FILES" > "$TMP_DIR/file-tree.diff"; then
    file_count="$(wc -l < "$ZH_FILES" | tr -d '[:space:]')"
    record_check "Deployment file tree" "pass" "artifact file tree matches: ${file_count} files"
else
    record_check "Deployment file tree" "fail" "artifact file tree differs: $(cat "$TMP_DIR/file-tree.diff")"
fi

if diff -u "$ZH_DIRS" "$EN_DIRS" > "$TMP_DIR/dir-tree.diff"; then
    dir_count="$(wc -l < "$ZH_DIRS" | tr -d '[:space:]')"
    record_check "Deployment directory tree" "pass" "artifact directory tree matches: ${dir_count} directories"
else
    record_check "Deployment directory tree" "fail" "artifact directory tree differs: $(cat "$TMP_DIR/dir-tree.diff")"
fi

if [ ! -e "$ZH_DIR/.github" ] && [ ! -e "$EN_DIR/.github" ]; then
    record_check "No GitHub constraints" "pass" "root .github is absent in both deployments"
else
    record_check "No GitHub constraints" "fail" "root .github exists in at least one deployment"
fi

missing_git=()
for rel in ".husky/commit-msg" "commitlint.config.cjs" ".gitignore"; do
    [ -e "$ZH_DIR/$rel" ] || missing_git+=("zh:$rel")
    [ -e "$EN_DIR/$rel" ] || missing_git+=("en:$rel")
done
if [ "${#missing_git[@]}" -eq 0 ]; then
    record_check "Git constraints" "pass" "commit-msg hook, commitlint config, and .gitignore exist in both deployments"
else
    record_check "Git constraints" "fail" "missing Git constraint artifacts: ${missing_git[*]}"
fi

compare_validator "docs/harness/sensors/scripts/validate.sh"
compare_validator "docs/harness/sensors/scripts/audit.sh"
compare_validator "docs/harness/sensors/scripts/check-consistency.sh"

content_failures=()
while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    [ -f "$EN_DIR/$rel" ] || continue

    if cmp -s "$ZH_DIR/$rel" "$EN_DIR/$rel"; then
        continue
    fi

    case "$rel" in
        *.md)
            zh_sig="$TMP_DIR/zh-${rel//\//_}.sig"
            en_sig="$TMP_DIR/en-${rel//\//_}.sig"
            markdown_format_signature "$ZH_DIR/$rel" > "$zh_sig"
            markdown_format_signature "$EN_DIR/$rel" > "$en_sig"
            if ! diff -u "$zh_sig" "$en_sig" > /dev/null; then
                content_failures+=("$rel(markdown structure)")
            fi
            ;;
        package.json|package-lock.json)
            zh_json="$TMP_DIR/zh-${rel//\//_}.json"
            en_json="$TMP_DIR/en-${rel//\//_}.json"
            normalize_json_artifact "$ZH_DIR/$rel" "$rel" > "$zh_json"
            normalize_json_artifact "$EN_DIR/$rel" "$rel" > "$en_json"
            if ! diff -u "$zh_json" "$en_json" > /dev/null; then
                content_failures+=("$rel(json artifact)")
            fi
            ;;
        docs/harness/sensors/scripts/*.sh)
            if ! bash -n "$ZH_DIR/$rel" || ! bash -n "$EN_DIR/$rel"; then
                content_failures+=("$rel(shell syntax)")
            fi
            ;;
        *)
            content_failures+=("$rel(machine file)")
            ;;
    esac
done < "$ZH_FILES"

if [ "${#content_failures[@]}" -eq 0 ]; then
    record_check "Artifact content parity" "pass" "all non-identical artifacts are accepted locale mirrors"
else
    record_check "Artifact content parity" "fail" "unexpected non-language differences: ${content_failures[*]}"
fi

if command -v rg >/dev/null 2>&1; then
    if rg -n \
        --glob '*.md' \
        --glob '!node_modules/**' \
        --glob '!.git/**' \
        --glob '!.claude/**' \
        --glob '!claude-*.log' \
        --glob '!claude-interaction-record.md' \
        '[\p{Han}]' "$EN_DIR" > "$TMP_DIR/en-cjk.txt"; then
        record_check "English markdown language" "fail" "English markdown contains CJK text: $(sed -n '1,5p' "$TMP_DIR/en-cjk.txt")"
    else
        record_check "English markdown language" "pass" "English markdown deployment contains no CJK text"
    fi
else
    record_check "English markdown language" "pass" "rg unavailable; skipped CJK text scan"
fi

failed_count="$(jq -s '[.[] | select(.status == "fail")] | length' "$CHECKS_FILE")"
passed_count="$(jq -s '[.[] | select(.status == "pass")] | length' "$CHECKS_FILE")"
total_count="$(jq -s 'length' "$CHECKS_FILE")"
overall_status="pass"
if [ "$failed_count" -gt 0 ]; then
    overall_status="fail"
fi

if [ "$JSON_MODE" = true ]; then
    jq -s \
        --arg status "$overall_status" \
        --argjson total "$total_count" \
        --argjson passed "$passed_count" \
        --argjson failed "$failed_count" \
        '{status:$status, summary:{total:$total, passed:$passed, failed:$failed}, checks:.}' \
        "$CHECKS_FILE"
else
    echo "i18n deployment comparison: $overall_status"
    jq -r '. | "- [\(.status)] \(.name): \(.detail)"' "$CHECKS_FILE"
fi

[ "$failed_count" -eq 0 ]
