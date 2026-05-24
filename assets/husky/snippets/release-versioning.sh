# Protect v* release tags from deletion and overwrite.
if [ -z "${DAYU_HARNESS_PRE_PUSH_INPUT:-}" ]; then
    dayu_tmp_dir="${TMPDIR:-${PWD:-.}/.dayu/tmp}"
    if ! mkdir -p "$dayu_tmp_dir" 2>/dev/null || [ ! -w "$dayu_tmp_dir" ]; then
        dayu_tmp_dir="${PWD:-.}/.dayu/tmp"
        mkdir -p "$dayu_tmp_dir"
    fi
    DAYU_HARNESS_PRE_PUSH_INPUT="$(mktemp "$dayu_tmp_dir/dayu-harness-pre-push.XXXXXX")"
    cat > "$DAYU_HARNESS_PRE_PUSH_INPUT"
    export DAYU_HARNESS_PRE_PUSH_INPUT
    trap 'rm -f "$DAYU_HARNESS_PRE_PUSH_INPUT"' EXIT
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
