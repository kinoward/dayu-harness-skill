# Protect main/master branches from destructive pushes.
if [ -z "${DAYU_HARNESS_PRE_PUSH_INPUT:-}" ]; then
    DAYU_HARNESS_PRE_PUSH_INPUT="$(mktemp "${TMPDIR:-/tmp}/dayu-harness-pre-push.XXXXXX")"
    cat > "$DAYU_HARNESS_PRE_PUSH_INPUT"
    export DAYU_HARNESS_PRE_PUSH_INPUT
    trap 'rm -f "$DAYU_HARNESS_PRE_PUSH_INPUT"' EXIT
fi

while read -r local_ref local_sha remote_ref remote_sha; do
    ref_name=$(echo "$remote_ref" | sed 's|refs/heads/||' | sed 's|refs/tags/||')

    if [ "$remote_ref" = "refs/heads/main" ] || [ "$remote_ref" = "refs/heads/master" ]; then
        if [ "$local_sha" = "0000000000000000000000000000000000000000" ]; then
            echo "ERROR: deleting $ref_name is not allowed."
            echo "Use repository settings for exceptional branch administration."
            exit 1
        fi

        echo "ERROR: direct push to $ref_name is not allowed."
        echo "Use a feature branch and pull request workflow."
        exit 1
    fi
done < "$DAYU_HARNESS_PRE_PUSH_INPUT"
