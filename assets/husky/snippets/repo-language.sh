# CJK character detection for commit messages.
COMMIT_MSG_FILE="${COMMIT_MSG_FILE:-${1:-}}"
if [ -z "$COMMIT_MSG_FILE" ]; then
    echo "ERROR: commit message file path is missing."
    exit 2
fi

if grep -q -- "<!-- skip-cjk-check -->" "$COMMIT_MSG_FILE"; then
    echo "SKIP: commit message contains <!-- skip-cjk-check --> marker."
else
    CJK_MATCHES=$(perl -Mutf8 '-Mopen=:std,:encoding(UTF-8)' -ne 'print "$.:$_" if /[\x{4E00}-\x{9FFF}\x{3040}-\x{309F}\x{30A0}-\x{30FF}\x{AC00}-\x{D7AF}\x{3000}-\x{303F}\x{FF00}-\x{FFEF}]/' "$COMMIT_MSG_FILE" 2>/dev/null || true)
    if [ -n "$CJK_MATCHES" ]; then
        echo ""
        echo "ERROR: commit message contains CJK characters."
        echo "Commit messages must be in English. See docs/harness/guides/git-language-policy.md"
        echo ""
        echo "Offending lines:"
        printf '%s\n' "$CJK_MATCHES"
        exit 1
    fi
fi
