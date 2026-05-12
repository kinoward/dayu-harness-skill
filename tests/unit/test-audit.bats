#!/usr/bin/env bats
# audit.sh 单元测试

setup() {
    TEST_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "audit.sh detects missing CLAUDE.md" {
    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/scripts/audit.sh" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "CLAUDE.md 不存在" ]]
}

@test "audit.sh detects valid CLAUDE.md" {
    echo "@AGENTS.md" > "$TEST_DIR/CLAUDE.md"
    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/scripts/audit.sh" "$TEST_DIR"
    [[ "$output" =~ "CLAUDE.md 存在且引用 @AGENTS.md" ]]
}

@test "audit.sh detects missing AGENTS.md" {
    echo "@AGENTS.md" > "$TEST_DIR/CLAUDE.md"
    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/scripts/audit.sh" "$TEST_DIR"
    [[ "$output" =~ "根 AGENTS.md 不存在" ]]
}

@test "audit.sh detects existing AGENTS.md" {
    echo "@AGENTS.md" > "$TEST_DIR/CLAUDE.md"
    echo "# Test" > "$TEST_DIR/AGENTS.md"
    mkdir -p "$TEST_DIR/docs/practices"
    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/scripts/audit.sh" "$TEST_DIR"
    [[ "$output" =~ "根 AGENTS.md 存在" ]]
}
