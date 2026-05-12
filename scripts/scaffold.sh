#!/usr/bin/env bash
# scaffold.sh — 主脚手架：复制模板文档 + 安装选定资产
# 用法:
#   scaffold.sh <target-root> [--dry-run] [--apply] [--only <category>]
#   scaffold.sh <target-root>                          # default: dry-run + prompt
#   scaffold.sh <target-root> --dry-run                # JSON preview
#   scaffold.sh <target-root> --apply                  # execute + validate
#   scaffold.sh <target-root> --apply --only docs     # docs only
#   scaffold.sh <target-root> --apply --only husky    # husky only
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES_DIR="$SKILL_DIR/templates"
ASSETS_DIR="$SKILL_DIR/assets"
SCRIPTS_DIR="$SKILL_DIR/scripts"
VALIDATE_SCRIPT="$TEMPLATES_DIR/docs/scripts/validate.sh"

# Parse args
MODE="prompt"  # prompt | dry-run | apply
ONLY_CATEGORY="all"
ENABLED_CATEGORIES=""
TARGET=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) MODE="dry-run"; shift ;;
        --apply) MODE="apply"; shift ;;
        --only)
            ONLY_CATEGORY="${2:-}"
            shift 2
            ;;
        --enable)
            ENABLED_CATEGORIES="${2:-}"
            shift 2
            ;;
        *) TARGET="$1"; shift ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo "用法: scaffold.sh <target-root> [--dry-run|--apply] [--only <category>] [--enable cat1,cat2,...]" >&2
    echo "" >&2
    echo "Categories: docs, husky, commitlint, workflows, eslint, prettier, lint-staged, gitignore, all" >&2
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

# ============================================================
# Q&A answer to category mapping
# ============================================================
# Q3 (提交信息格式校验)    → husky, commitlint
# Q4 (Git 内容语言规范)    → bundled in husky commit-msg hook
# Q5 (PR 工作流规范)       → workflows (pr-lint.yml, issue-lint.yml)
# Q6 (分支与发布管理)      → workflows (rulesets, pre-push hook bundled in husky)
# Q7 (代码风格与质量)      → eslint, prettier, lint-staged
# Q8 (测试策略)            → docs (practices/testing-strategy.md)
# Q9 (开发环境纪律)        → docs (practices/dev-hygiene.md, scripts/)
# Q10 (AI 协作风格)        → docs (practices/ai-collaboration.md)
# Q11 (决策记录 ADR)       → docs (decisions/)
# Q12 (排障知识库)         → docs (troubleshooting/)
# Q13 (版本化研究院)       → docs (research/)
# Q14 (项目专属文档)       → docs (project/)
# Q15 (历史归档)           → docs (archive/)
# gitignore                → gitignore (always offered)
# ============================================================

# Define all deployable files per category
# Format: "src_relative_to_SKILL_DIR|dst_relative_to_TARGET"

get_docs_files() {
    # Core entry files
    echo "templates/CLAUDE.md|CLAUDE.md"
    echo "templates/AGENTS.md|AGENTS.md"

    # docs/ hierarchy
    echo "templates/docs/AGENTS.md|docs/AGENTS.md"
    echo "templates/docs/doc-maintenance.md|docs/doc-maintenance.md"

    # Practices
    echo "templates/docs/practices/AGENTS.md|docs/practices/AGENTS.md"
    echo "templates/docs/practices/ai-collaboration.md|docs/practices/ai-collaboration.md"
    echo "templates/docs/practices/branch-and-release.md|docs/practices/branch-and-release.md"
    echo "templates/docs/practices/commit-guidelines.md|docs/practices/commit-guidelines.md"
    echo "templates/docs/practices/dev-hygiene.md|docs/practices/dev-hygiene.md"
    echo "templates/docs/practices/git-language-policy.md|docs/practices/git-language-policy.md"
    echo "templates/docs/practices/pr-guidelines.md|docs/practices/pr-guidelines.md"
    echo "templates/docs/practices/testing-strategy.md|docs/practices/testing-strategy.md"

    # Decisions
    echo "templates/docs/decisions/AGENTS.md|docs/decisions/AGENTS.md"
    echo "templates/docs/decisions/adr-template.md|docs/decisions/adr-template.md"

    # Troubleshooting
    echo "templates/docs/troubleshooting/AGENTS.md|docs/troubleshooting/AGENTS.md"

    # Research
    echo "templates/docs/research/AGENTS.md|docs/research/AGENTS.md"

    # Project
    echo "templates/docs/project/AGENTS.md|docs/project/AGENTS.md"

    # Archive
    echo "templates/docs/archive/AGENTS.md|docs/archive/AGENTS.md"
    echo "templates/docs/archive/project/AGENTS.md|docs/archive/project/AGENTS.md"

    # Scripts (always deployed)
    echo "templates/docs/scripts/audit.sh|docs/scripts/audit.sh"
    echo "templates/docs/scripts/validate.sh|docs/scripts/validate.sh"
    echo "templates/docs/scripts/diff-helper.sh|docs/scripts/diff-helper.sh"
    echo "templates/docs/scripts/check-consistency.sh|docs/scripts/check-consistency.sh"
}

get_husky_files() {
    echo "assets/husky/commit-msg|.husky/commit-msg"
    echo "assets/husky/pre-commit|.husky/pre-commit"
    echo "assets/husky/pre-push|.husky/pre-push"
}

get_commitlint_files() {
    echo "assets/commitlint/commitlint.config.cjs|commitlint.config.cjs"
}

get_workflows_files() {
    echo "assets/github/workflows/pr-lint.yml|.github/workflows/pr-lint.yml"
    echo "assets/github/workflows/issue-lint.yml|.github/workflows/issue-lint.yml"
    echo "assets/github/scripts/pr_body_structure.py|.github/scripts/pr_body_structure.py"
    echo "assets/github/rulesets/protect-main.json|.github/rulesets/protect-main.json"
    echo "assets/github/rulesets/protect-tags.json|.github/rulesets/protect-tags.json"
}

get_eslint_files() {
    echo "assets/eslint/eslint.config.js|eslint.config.js"
}

get_prettier_files() {
    echo "assets/prettier/.prettierrc|.prettierrc"
}

get_lintstaged_files() {
    echo "assets/lint-staged/.lintstagedrc.json|.lintstagedrc.json"
}

get_gitignore_files() {
    echo "assets/gitignore/universal.gitignore|.gitignore"
}

# Get descriptions for each category
get_category_description() {
    local cat="$1"
    case "$cat" in
        docs)
            echo "Documentation templates — AGENTS.md, CLAUDE.md, docs/ hierarchy (practices, decisions, troubleshooting, research, project, archive), and maintenance scripts (audit.sh, validate.sh, diff-helper.sh, check-consistency.sh)"
            ;;
        husky)
            echo "Husky git hooks — commit-msg (Conventional Commits + CJK detection), pre-commit (lint-staged), pre-push (branch protection)"
            ;;
        commitlint)
            echo "Commitlint configuration — commitlint.config.cjs with @commitlint/config-conventional rules"
            ;;
        workflows)
            echo "GitHub CI — pr-lint.yml, issue-lint.yml workflows, pr_body_structure.py script, branch/tag rulesets"
            ;;
        eslint)
            echo "ESLint configuration — eslint.config.js (flat config) with recommended rules"
            ;;
        prettier)
            echo "Prettier configuration — .prettierrc with standard formatting options"
            ;;
        lint-staged)
            echo "lint-staged configuration — .lintstagedrc.json with pre-commit formatting and linting"
            ;;
        gitignore)
            echo "Gitignore — universal.gitignore (with language-specific variants auto-detected during install)"
            ;;
    esac
}

# Resolve which categories to process
resolve_categories() {
    local cats=""
    if [ -n "$ENABLED_CATEGORIES" ]; then
        cats="$ENABLED_CATEGORIES"
    elif [ "$ONLY_CATEGORY" = "all" ]; then
        cats="docs,husky,commitlint,workflows,eslint,prettier,lint-staged,gitignore"
    else
        cats="$ONLY_CATEGORY"
    fi
    echo "$cats" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$'
}

# Count files in a category
count_category_files() {
    local cat="$1"
    case "$cat" in
        docs) get_docs_files | wc -l | tr -d ' ' ;;
        husky) get_husky_files | wc -l | tr -d ' ' ;;
        commitlint) get_commitlint_files | wc -l | tr -d ' ' ;;
        workflows) get_workflows_files | wc -l | tr -d ' ' ;;
        eslint) get_eslint_files | wc -l | tr -d ' ' ;;
        prettier) get_prettier_files | wc -l | tr -d ' ' ;;
        lint-staged) get_lintstaged_files | wc -l | tr -d ' ' ;;
        gitignore) get_gitignore_files | wc -l | tr -d ' ' ;;
        *) echo "0" ;;
    esac
}

# Get files for a category
get_category_files() {
    local cat="$1"
    case "$cat" in
        docs) get_docs_files ;;
        husky) get_husky_files ;;
        commitlint) get_commitlint_files ;;
        workflows) get_workflows_files ;;
        eslint) get_eslint_files ;;
        prettier) get_prettier_files ;;
        lint-staged) get_lintstaged_files ;;
        gitignore) get_gitignore_files ;;
    esac
}

# ===================== --dry-run mode =====================
do_dry_run() {
    local categories
    categories=$(resolve_categories)

    local ITEMS=""
    local CATEGORY_SUMMARIES=""
    local TOTAL_FILES=0
    local TOTAL_EXISTING=0
    local TOTAL_NEW=0
    local ALL_CLEAN="true"

    for cat in $categories; do
        local cat_file_count=$(count_category_files "$cat")
        local cat_new=0
        local cat_existing=0
        local cat_items=""

        while IFS='|' read -r src_rel dst_rel; do
            [ -z "$src_rel" ] && continue
            local src_path="$SKILL_DIR/$src_rel"
            local dst_path="$TARGET/$dst_rel"

            if [ ! -f "$src_path" ]; then
                [ -n "$cat_items" ] && cat_items+=","
                cat_items+="{\"src\":\"$src_rel\",\"dst\":\"$dst_rel\",\"exists_in_target\":false,\"available\":false,\"description_nl\":\"Source template not found: $src_rel\"}"
                continue
            fi

            local src_lines=$(wc -l < "$src_path" | tr -d ' ')

            if [ -f "$dst_path" ]; then
                cat_existing=$((cat_existing + 1))
                ALL_CLEAN="false"
                local dst_lines=$(wc -l < "$dst_path" | tr -d ' ')
                [ -n "$cat_items" ] && cat_items+=","
                cat_items+="{\"src\":\"$src_rel\",\"dst\":\"$dst_rel\",\"exists_in_target\":true,\"target_lines\":$dst_lines,\"source_lines\":$src_lines,\"description_nl\":\"Existing file found ($dst_lines lines). Skill version has $src_lines lines. Review diff before replacing.\"}"
            else
                cat_new=$((cat_new + 1))
                [ -n "$cat_items" ] && cat_items+=","
                cat_items+="{\"src\":\"$src_rel\",\"dst\":\"$dst_rel\",\"exists_in_target\":false,\"source_lines\":$src_lines,\"description_nl\":\"New file ($src_lines lines). Ready for clean install.\"}"
            fi
        done < <(get_category_files "$cat")

        TOTAL_FILES=$((TOTAL_FILES + cat_file_count))
        TOTAL_NEW=$((TOTAL_NEW + cat_new))
        TOTAL_EXISTING=$((TOTAL_EXISTING + cat_existing))

        local cat_desc=$(get_category_description "$cat")
        [ -n "$CATEGORY_SUMMARIES" ] && CATEGORY_SUMMARIES+=","
        CATEGORY_SUMMARIES+="{\"category\":\"$cat\",\"files_total\":$cat_file_count,\"files_new\":$cat_new,\"files_existing\":$cat_existing,\"description\":\"$(json_escape "$cat_desc")\",\"items\":[$cat_items]}"
    done

    local TOP_STATUS="clean"
    [ "$ALL_CLEAN" != "true" ] && TOP_STATUS="conflict"

    local SUMMARY="Preview of ${TOTAL_FILES} file(s) across $(echo "$categories" | wc -l | tr -d ' ') categories."
    [ "$TOTAL_EXISTING" -gt 0 ] && SUMMARY="$SUMMARY ${TOTAL_EXISTING} file(s) already exist and may create conflicts."

    local DESC_NL
    if [ "$TOP_STATUS" = "clean" ]; then
        DESC_NL="All ${TOTAL_FILES} files are new — no existing files would be overwritten. Safe to apply."
    else
        DESC_NL="${TOTAL_NEW} new file(s) will be created, ${TOTAL_EXISTING} existing file(s) will be replaced or merged. Review each item's status before applying."
    fi

    cat <<JSONEOF
{
  "mode": "dry-run",
  "target": "$(json_escape "$TARGET")",
  "status": "$TOP_STATUS",
  "categories": [$CATEGORY_SUMMARIES],
  "summary": "$(json_escape "$SUMMARY")",
  "total_files": $TOTAL_FILES,
  "files_new": $TOTAL_NEW,
  "files_existing": $TOTAL_EXISTING,
  "description_nl": "$(json_escape "$DESC_NL")"
}
JSONEOF
}

# ===================== --apply mode =====================
do_apply() {
    local categories
    categories=$(resolve_categories)

    local APPLIED=""
    local SKIPPED=""
    local ERRORS=""
    local APPLIED_COUNT=0
    local SKIPPED_COUNT=0

    # Install selected categories
    for cat in $categories; do
        # For asset categories with dedicated install scripts, delegate
        case "$cat" in
            husky|commitlint|workflows|eslint|prettier|lint-staged|gitignore)
                local script_name="install-${cat}.sh"
                # Map category name to script name (handle lint-staged → lint_staged, workflows → github-workflows)
                case "$cat" in
                    lint-staged) script_name="install-lint-staged.sh" ;;
                    workflows) script_name="install-github-workflows.sh" ;;
                    gitignore) script_name="install-gitignore.sh" ;;
                esac

                local installer="$SCRIPTS_DIR/$script_name"
                if [ -x "$installer" ]; then
                    local result
                    result=$("$installer" "$TARGET" --apply replace 2>/dev/null) || true
                    if echo "$result" | grep -q '"status":"ok"'; then
                        local detail
                        detail=$(echo "$result" | grep -o '"detail":"[^"]*"' | head -1 | sed 's/"detail":"//;s/"//' || echo "installed")
                        APPLIED="${APPLIED}${cat} "
                        APPLIED_COUNT=$((APPLIED_COUNT + 1))
                    elif echo "$result" | grep -q '"status":"partial"'; then
                        APPLIED="${APPLIED}${cat}(partial) "
                        APPLIED_COUNT=$((APPLIED_COUNT + 1))
                    else
                        local err_detail=$(echo "$result" | grep -o '"error":"[^"]*"' | head -1 | sed 's/"error":"//;s/"//' || echo "unknown error")
                        ERRORS="${ERRORS}${cat}: ${err_detail}; "
                    fi
                else
                    ERRORS="${ERRORS}${cat}: installer not found or not executable; "
                fi
                ;;
            docs)
                # Handle docs directly
                while IFS='|' read -r src_rel dst_rel; do
                    [ -z "$src_rel" ] && continue
                    local src_path="$SKILL_DIR/$src_rel"
                    local dst_path="$TARGET/$dst_rel"

                    if [ ! -f "$src_path" ]; then
                        ERRORS="${ERRORS}${dst_rel}: source not found; "
                        continue
                    fi

                    mkdir -p "$(dirname "$dst_path")"
                    if [ -f "$dst_path" ]; then
                        SKIPPED="${SKIPPED}${dst_rel} "
                        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
                    else
                        cp "$src_path" "$dst_path"
                        APPLIED="${APPLIED}${dst_rel} "
                        APPLIED_COUNT=$((APPLIED_COUNT + 1))
                    fi

                    # Make scripts executable
                    if echo "$dst_rel" | grep -q '^docs/scripts/'; then
                        chmod +x "$dst_path"
                    fi
                done < <(get_docs_files)
                ;;
        esac
    done

    APPLIED=$(echo "$APPLIED" | xargs 2>/dev/null || true)
    SKIPPED=$(echo "$SKIPPED" | xargs 2>/dev/null || true)
    ERRORS=$(echo "$ERRORS" | sed 's/; $//' 2>/dev/null || true)

    local OVERALL="ok"
    [ -n "$ERRORS" ] && OVERALL="error"

    echo '{}' >/dev/null  # no-op, JSON output below

    # Run validate.sh if available
    local VALIDATION_RESULT="skipped"
    if [ -f "$VALIDATE_SCRIPT" ] && [ -x "$VALIDATE_SCRIPT" ]; then
        if bash "$VALIDATE_SCRIPT" --json "$TARGET" 2>/dev/null; then
            VALIDATION_RESULT="passed"
        else
            VALIDATION_RESULT="failed (exit code $?)"
        fi
    fi

    cat <<JSONEOF
{
  "mode": "apply",
  "target": "$(json_escape "$TARGET")",
  "status": "$OVERALL",
  "applied_count": $APPLIED_COUNT,
  "applied": "$(json_escape "$APPLIED")",
  "skipped_count": $SKIPPED_COUNT,
  "skipped": "$(json_escape "$SKIPPED")",
  "errors": "$(json_escape "$ERRORS")",
  "validation": "$(json_escape "$VALIDATION_RESULT")",
  "description_nl": "$(json_escape "Scaffold applied: ${APPLIED_COUNT} file(s) created/copied. Validation: ${VALIDATION_RESULT}.")"
}
JSONEOF
}

# ===================== Main =====================
case "$MODE" in
    dry-run)
        do_dry_run
        ;;
    apply)
        do_apply
        ;;
    prompt)
        # Default: show dry-run preview + prompt for confirmation
        do_dry_run
        echo "" >&2
        echo "=== 以上为预览 (dry-run) ===" >&2
        echo "执行 scaffold.sh --apply 以实际复制文件。" >&2
        echo "或使用 --only <category> 限制范围。" >&2
        ;;
esac
