#!/usr/bin/env bats
# audit.sh 单元测试

setup() {
    TEST_ROOT="${BATS_TEST_DIRNAME}/.tmp"
    mkdir -p "$TEST_ROOT"
    TEST_DIR="$(mktemp -d "$TEST_ROOT/audit.XXXXXX")"
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
