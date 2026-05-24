# Protect v* release tags from deletion and overwrite.
if [ -z "${DAYU_HARNESS_PRE_PUSH_INPUT:-}" ]; then
    for DAYU_HARNESS_TMP_CANDIDATE in "${DAYU_HARNESS_TMPDIR:-}" "${TMPDIR:-}" ".git/dayu-harness-tmp" ".dayu-harness-tmp" "/tmp"; do
        [ -n "$DAYU_HARNESS_TMP_CANDIDATE" ] || continue
        mkdir -p "$DAYU_HARNESS_TMP_CANDIDATE" 2>/dev/null || true
        DAYU_HARNESS_PRE_PUSH_INPUT="$(mktemp "${DAYU_HARNESS_TMP_CANDIDATE%/}/dayu-harness-pre-push.XXXXXX" 2>/dev/null || true)"
        if [ -n "$DAYU_HARNESS_PRE_PUSH_INPUT" ]; then
            break
        fi
    done
    if [ -z "${DAYU_HARNESS_PRE_PUSH_INPUT:-}" ]; then
        echo "ERROR: unable to create temporary pre-push input file." >&2
        exit 1
    fi
    cat > "$DAYU_HARNESS_PRE_PUSH_INPUT"
    export DAYU_HARNESS_PRE_PUSH_INPUT
    trap 'rm -f "$DAYU_HARNESS_PRE_PUSH_INPUT"' EXIT
    unset DAYU_HARNESS_TMP_CANDIDATE
fi

while read -r local_ref local_sha remote_ref remote_sha; do
    ref_name=$(echo "$remote_ref" | sed 's|refs/heads/||' | sed 's|refs/tags/||')

    if echo "$remote_ref" | grep -q 'refs/tags/v'; then
        if [ "$local_sha" = "0000000000000000000000000000000000000000" ]; then
            echo "ERROR: deleting release tag $ref_name is not allowed."
            exit 1
        fi

        if [ "$remote_sha" != "0000000000000000000000000000000000000000" ]; then
            echo "ERROR: overwriting release tag $ref_name is not allowed."
            echo "Create a new version tag instead."
            exit 1
        fi
    fi
done < "$DAYU_HARNESS_PRE_PUSH_INPUT"
