# Protect default/main/master branches from destructive pushes.
if [ -z "${DAYU_HARNESS_PRE_PUSH_INPUT:-}" ]; then
    DAYU_HARNESS_PRE_PUSH_INPUT="$(mktemp "${TMPDIR:-/tmp}/dayu-harness-pre-push.XXXXXX")"
    cat > "$DAYU_HARNESS_PRE_PUSH_INPUT"
    export DAYU_HARNESS_PRE_PUSH_INPUT
    trap 'rm -f "$DAYU_HARNESS_PRE_PUSH_INPUT"' EXIT
fi

while read -r local_ref local_sha remote_ref remote_sha; do
    ref_name=$(echo "$remote_ref" | sed 's|refs/heads/||' | sed 's|refs/tags/||')

    protected_branches="${DAYU_HARNESS_PROTECTED_BRANCHES:-__DAYU_DEFAULT_BRANCH__ main master}"
    protected_match=false
    for protected_branch in $protected_branches; do
        [ -z "$protected_branch" ] && continue
        if [ "$remote_ref" = "refs/heads/$protected_branch" ]; then
            protected_match=true
            break
        fi
    done

    if [ "$protected_match" = true ]; then
        if [ "$local_sha" = "0000000000000000000000000000000000000000" ]; then
            echo "ERROR: deleting $ref_name is not allowed."
            echo "Use repository settings for exceptional branch administration."
            exit 1
        fi

        if [ "${DAYU_HARNESS_ALLOW_DEFAULT_BRANCH_CREATION:-}" = "1" ] && [ "$remote_sha" = "0000000000000000000000000000000000000000" ]; then
            continue
        fi

        echo "ERROR: direct push to $ref_name is not allowed."
        echo "Use a feature branch and pull request workflow."
        exit 1
    fi
done < "$DAYU_HARNESS_PRE_PUSH_INPUT"
