#!/usr/bin/env bats
# audit.sh 单元测试

setup() {
    TEST_ROOT="${BATS_TEST_DIRNAME}/.tmp"
    mkdir -p "$TEST_ROOT"
    TEST_DIR="$(mktemp -d "$TEST_ROOT/audit.XXXXXX")"
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "audit.sh detects missing CLAUDE.md" {
    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/harness/sensors/scripts/audit.sh" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "CLAUDE.md 不存在" ]]
}

@test "audit.sh detects valid CLAUDE.md" {
    echo "@AGENTS.md" > "$TEST_DIR/CLAUDE.md"
    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/harness/sensors/scripts/audit.sh" "$TEST_DIR"
    [[ "$output" =~ "CLAUDE.md 存在且引用 @AGENTS.md" ]]
}

@test "audit.sh detects missing AGENTS.md" {
    echo "@AGENTS.md" > "$TEST_DIR/CLAUDE.md"
    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/harness/sensors/scripts/audit.sh" "$TEST_DIR"
    [[ "$output" =~ "根 AGENTS.md 不存在" ]]
}

@test "audit.sh detects existing AGENTS.md" {
    echo "@AGENTS.md" > "$TEST_DIR/CLAUDE.md"
    echo "# Test" > "$TEST_DIR/AGENTS.md"
    mkdir -p "$TEST_DIR/docs/harness/guides"
    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/harness/sensors/scripts/audit.sh" "$TEST_DIR"
    [[ "$output" =~ "根 AGENTS.md 存在" ]]
}

@test "audit.sh detects missing harness scripts AGENTS index" {
    echo "@AGENTS.md" > "$TEST_DIR/CLAUDE.md"
    echo "# Test" > "$TEST_DIR/AGENTS.md"
    mkdir -p "$TEST_DIR/docs/harness/sensors/scripts"

    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/harness/sensors/scripts/audit.sh" "$TEST_DIR"

    [[ "$output" =~ "docs/harness/sensors/scripts/ 存在但缺少 AGENTS.md" ]]
}

@test "audit.sh detects executable harness scripts" {
    echo "@AGENTS.md" > "$TEST_DIR/CLAUDE.md"
    echo "# Test" > "$TEST_DIR/AGENTS.md"
    mkdir -p "$TEST_DIR/docs/harness/sensors/scripts"
    echo "# scripts" > "$TEST_DIR/docs/harness/sensors/scripts/AGENTS.md"
    for script in audit.sh validate.sh diff-helper.sh check-consistency.sh; do
        printf '#!/usr/bin/env bash\n' > "$TEST_DIR/docs/harness/sensors/scripts/$script"
        chmod +x "$TEST_DIR/docs/harness/sensors/scripts/$script"
    done

    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/harness/sensors/scripts/audit.sh" "$TEST_DIR"

    [[ "$output" =~ "docs/harness/sensors/scripts/audit.sh" ]]
    [[ "$output" =~ "docs/harness/sensors/scripts/AGENTS.md" ]]
}

@test "core-only scaffold passes optional-link checks" {
    local project_dir="$TEST_DIR/core-only"
    mkdir -p "$project_dir"

    run bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply
    [ "$status" -eq 0 ]

    run bash "$REPO_ROOT/templates/docs/harness/sensors/scripts/check-consistency.sh" --json "$project_dir"
    [ "$status" -eq 0 ]

    run bash -c '"$1" --json "$2" 2>/dev/null' _ "$REPO_ROOT/templates/docs/harness/sensors/scripts/audit.sh" "$project_dir"
    [ "$status" -eq 0 ]
}

@test "check-consistency fails on non-optional broken AGENTS link" {
    local project_dir="$TEST_DIR/broken-nonoptional"
    mkdir -p "$project_dir"
    run bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply
    [ "$status" -eq 0 ]

    echo "- [缺失的必选文档](docs/design-docs/does-not-exist.md)" >> "$project_dir/AGENTS.md"
    run bash "$REPO_ROOT/templates/docs/harness/sensors/scripts/check-consistency.sh" --json "$project_dir"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.summary.failed >= 1'
}

@test "check-consistency fails on illegal optional marker" {
    local project_dir="$TEST_DIR/broken-optional"
    mkdir -p "$project_dir"
    run bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply
    [ "$status" -eq 0 ]

    echo "- [缺失的可选文档](docs/design-docs/does-not-exist.md) 可选：unknown.capability" >> "$project_dir/AGENTS.md"
    run bash "$REPO_ROOT/templates/docs/harness/sensors/scripts/check-consistency.sh" --json "$project_dir"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.summary.failed >= 1'
}

@test "audit.sh --json fails on non-optional broken root AGENTS link" {
    local project_dir="$TEST_DIR/json-root-broken-nonoptional"
    mkdir -p "$project_dir"
    run bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply
    [ "$status" -eq 0 ]

    echo "- [缺失的必选文档](docs/design-docs/does-not-exist.md)" >> "$project_dir/AGENTS.md"

    run bash -c '"$1" --json "$2" 2>/dev/null' _ "$REPO_ROOT/templates/docs/harness/sensors/scripts/audit.sh" "$project_dir"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.summary.failed >= 1'
    echo "$output" | jq -e '.results | any(.check == "AGENTS.md 链接: docs/design-docs/does-not-exist.md" and .status == "fail")'
}

@test "audit.sh --json fails on illegal optional marker in root AGENTS link" {
    local project_dir="$TEST_DIR/json-root-illegal-optional"
    mkdir -p "$project_dir"
    run bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply
    [ "$status" -eq 0 ]

    echo "- [缺失的可选文档](docs/design-docs/does-not-exist.md) 可选：unknown.capability" >> "$project_dir/AGENTS.md"

    run bash -c '"$1" --json "$2" 2>/dev/null' _ "$REPO_ROOT/templates/docs/harness/sensors/scripts/audit.sh" "$project_dir"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.summary.failed >= 1'
    echo "$output" | jq -e '.results | any(.check == "AGENTS.md 链接: docs/design-docs/does-not-exist.md" and .status == "fail" and (.detail | contains("可选 capability 未在白名单")))'
}
