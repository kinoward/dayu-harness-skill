#!/usr/bin/env bats
# diff-helper.sh 单元测试

setup() {
    TEST_DIR="$(mktemp -d)"
    F1="$TEST_DIR/file1.txt"
    F2="$TEST_DIR/file2.txt"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "diff-helper check detects existing file" {
    echo "test" > "$F1"
    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/scripts/diff-helper.sh" check "$F1"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "已存在" ]]
}

@test "diff-helper check detects missing file" {
    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/scripts/diff-helper.sh" check "$TEST_DIR/nonexistent.txt"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "不存在" ]]
}

@test "diff-helper describe shows no change for identical files" {
    echo "line1" > "$F1"
    echo "line1" > "$F2"
    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/scripts/diff-helper.sh" describe "$F1" "$F2"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "相同" ]]
}

@test "diff-helper describe shows changes for different files" {
    echo "line1" > "$F1"
    echo "line2" > "$F2"
    run bash "${BATS_TEST_DIRNAME}/../../templates/docs/scripts/diff-helper.sh" describe "$F1" "$F2"
    [[ "$output" =~ "新增" ]] || [[ "$output" =~ "移除" ]]
}
