#!/usr/bin/env bats
# audit.sh 单元测试

setup() {
    TEST_ROOT="${BATS_TEST_DIRNAME}/.tmp"
    mkdir -p "$TEST_ROOT"
    TEST_DIR="$(mktemp -d "$TEST_ROOT/audit.XXXXXX")"
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

    WRAPPER_DIR="$TEST_DIR/wrapper"
    mkdir -p "$WRAPPER_DIR"
    cat > "$WRAPPER_DIR/node" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$WRAPPER_DIR/node"

    cat > "$WRAPPER_DIR/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "init" ]; then
  cat > package.json <<'JSON'
{"name":"dayu-harness-skill-test","version":"1.0.0","devDependencies":{}}
JSON
  exit 0
fi

if [ "${1:-}" = "install" ]; then
  cat > package.json <<'JSON'
{"name":"dayu-harness-skill-test","version":"1.0.0","devDependencies":{"@commitlint/cli":"0.0.0","@commitlint/config-conventional":"0.0.0","eslint":"0.0.0","@eslint/js":"0.0.0","prettier":"0.0.0","lint-staged":"0.0.0"}}
JSON
  exit 0
fi

exit 0
EOF
    chmod +x "$WRAPPER_DIR/npm"

    cat > "$WRAPPER_DIR/npx" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$WRAPPER_DIR/npx"

    cat > "$WRAPPER_DIR/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "auth" ] && [ "${2:-}" = "status" ]; then
  exit 0
fi
exit 0
EOF
    chmod +x "$WRAPPER_DIR/gh"

    export PATH="$WRAPPER_DIR:$PATH"
}

teardown() {
    rm -rf "$TEST_DIR"
}

json_from_output() {
    printf '%s\n' "$output" | awk 'BEGIN {emit=0} /^[[:space:]]*\{/ {emit=1} emit {print}'
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

@test "default scaffold passes optional-link checks" {
    local project_dir="$TEST_DIR/default-scaffold"
    mkdir -p "$project_dir"

    run bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply
    [ "$status" -eq 0 ]

    run bash "$REPO_ROOT/templates/docs/harness/sensors/scripts/check-consistency.sh" --json "$project_dir"
    [ "$status" -eq 0 ]

    run bash -c '"$1" --json "$2" 2>/dev/null' _ "$REPO_ROOT/templates/docs/harness/sensors/scripts/audit.sh" "$project_dir"
    [ "$status" -eq 0 ]
}

@test "validate.sh fails hard when initialized version sources drift" {
    local project_dir="$TEST_DIR/version-drift"
    mkdir -p "$project_dir"
    run bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply --strategy merge
    [ "$status" -eq 0 ]

    jq '.version = "9.9.9" | .packages[""].version = "9.9.9"' "$project_dir/package-lock.json" > "$project_dir/package-lock.tmp"
    mv "$project_dir/package-lock.tmp" "$project_dir/package-lock.json"

    run bash "$REPO_ROOT/templates/docs/harness/sensors/scripts/validate.sh" --json "$project_dir"
    [ "$status" -eq 1 ]
    json_from_output | jq -e '.summary.failed >= 1'
    json_from_output | jq -e '.checks | any(.item == "project/version-sync" and .status == "fail" and (.detail | contains("package-lock.json=9.9.9")))'
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

@test "check-consistency accepts English Optional marker for missing optional doc" {
    local project_dir="$TEST_DIR/broken-optional-en"
    mkdir -p "$project_dir"
    run bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply
    [ "$status" -eq 0 ]

    echo "- [Missing optional doc](docs/design-docs/does-not-exist.md) Optional: ai.execution" >> "$project_dir/AGENTS.md"
    run bash "$REPO_ROOT/templates/docs/harness/sensors/scripts/check-consistency.sh" --json "$project_dir"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.summary.failed == 0'
}

@test "audit --json accepts English Optional marker for missing optional doc" {
    local project_dir="$TEST_DIR/audit-json-broken-optional-en"
    mkdir -p "$project_dir"
    run bash "$REPO_ROOT/scripts/scaffold.sh" "$project_dir" --apply
    [ "$status" -eq 0 ]

    echo "- [Missing optional doc](docs/design-docs/does-not-exist.md) Optional: ai.execution" >> "$project_dir/AGENTS.md"

    run bash -c '"$1" --json "$2" 2>/dev/null' _ "$REPO_ROOT/templates/docs/harness/sensors/scripts/audit.sh" "$project_dir"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.summary.failed == 0'
    echo "$output" | jq -e '.results | any(.check == "AGENTS.md 链接: docs/design-docs/does-not-exist.md" and .status == "pass" and (.detail | contains("可选能力未部署，跳过断链检查")) )'
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
