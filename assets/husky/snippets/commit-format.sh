# Conventional Commits format validation.
COMMIT_MSG_FILE="${COMMIT_MSG_FILE:-${1:-}}"
if [ -z "$COMMIT_MSG_FILE" ]; then
    echo "ERROR: commit message file path is missing."
    exit 2
fi

if command -v npx &> /dev/null && [ -f "commitlint.config.cjs" ]; then
    if npx --no-install commitlint --version >/dev/null 2>&1; then
        npx --no-install commitlint --edit "$COMMIT_MSG_FILE" 2>/dev/null || {
            echo ""
            echo "ERROR: commit message does not follow Conventional Commits format."
            echo "Format: type(scope): description"
            echo "Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert"
            exit 1
        }
    else
        echo "SKIP: commitlint package is not installed locally."
    fi
fi
