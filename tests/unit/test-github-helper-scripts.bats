#!/usr/bin/env bats

setup() {
    export PYTHONDONTWRITEBYTECODE=1
    TEST_ROOT="${BATS_TEST_DIRNAME}/.tmp"
    mkdir -p "$TEST_ROOT"
    TEST_DIR="$(mktemp -d "$TEST_ROOT/github-helper-scripts.XXXXXX")"
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
}

teardown() {
    rm -rf "$TEST_DIR"
}

write_file() {
    local file="$1"
    shift
    printf '%s\n' "$@" > "$file"
}

@test "issue_depends_on enforces strict depends-on format" {
    local payload="$TEST_DIR/issue-payload.json"
    cat > "$payload" <<'JSON'
{
  "issue": {
    "body": "# Proposal\n\nNo dependency marker here."
  }
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/issue_depends_on.py" "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dependency lint skipped"* ]]

    cat > "$payload" <<'JSON'
{
  "issue": {
    "body": "# Proposal\n\nDepends on: #12"
  }
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/issue_depends_on.py" "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: Issue depends-on line is valid."* ]]

    cat > "$payload" <<'JSON'
{
  "issue": {
    "body": "# Proposal\n\nDepends on: #12, #34"
  }
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/issue_depends_on.py" "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: Issue depends-on line is valid."* ]]

    cat > "$payload" <<'JSON'
{
  "issue": {
    "body": "# Proposal\nDepends on: #12\nDepends on: #34"
  }
}
JSON
    run python3 "$REPO_ROOT/assets/github/scripts/issue_depends_on.py" "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *"at most one"* ]]

    cat > "$payload" <<'JSON'
{
  "issue": {
    "body": "# Proposal\n- Depends on: #12"
  }
}
JSON
    run python3 "$REPO_ROOT/assets/github/scripts/issue_depends_on.py" "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid issue dependency format"* ]]

    cat > "$payload" <<'JSON'
{
  "issue": {
    "body": "# Proposal\nDepends on #12"
  }
}
JSON
    run python3 "$REPO_ROOT/assets/github/scripts/issue_depends_on.py" "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid issue dependency format"* ]]

    cat > "$payload" <<'JSON'
{
  "issue": {
    "body": "# Proposal\nDepends on: 12"
  }
}
JSON
    run python3 "$REPO_ROOT/assets/github/scripts/issue_depends_on.py" "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid issue dependency format"* ]]

    cat > "$payload" <<'JSON'
{
  "issue": {
    "body": "# Proposal\nDepends on: #12 and #13"
  }
}
JSON
    run python3 "$REPO_ROOT/assets/github/scripts/issue_depends_on.py" "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid issue dependency format"* ]]
}

@test "pr_body_structure.py supports issue-first final and non-final trailers" {
    local body_file="$TEST_DIR/pr-body.md"
    write_file "$body_file" \
      "## Summary" \
      "- split issue work" \
      "" \
      "## Implementation notes" \
      "- first slice" \
      "" \
      "## Test plan" \
      "- [x] \`printf ok\`" \
      "" \
      "Final PR: no" \
      "Refs #42"

    run python3 "$REPO_ROOT/assets/github/scripts/pr_body_structure.py" < "$body_file"
    [ "$status" -eq 0 ]

    write_file "$body_file" \
      "## Summary" \
      "- finish issue work" \
      "" \
      "## Implementation notes" \
      "- final slice" \
      "" \
      "## Test plan" \
      "- [x] \`printf ok\`" \
      "" \
      "Final PR: yes" \
      "Closes #42"

    run python3 "$REPO_ROOT/assets/github/scripts/pr_body_structure.py" < "$body_file"
    [ "$status" -eq 0 ]
}

@test "pr_body_structure.py blocks closing keyword while sibling PR remains open" {
    local body_file="$TEST_DIR/pr-body-final.md"
    local open_prs="$TEST_DIR/open-prs.json"
    write_file "$body_file" \
      "## Summary" \
      "- finish issue work" \
      "" \
      "## Implementation notes" \
      "- final slice" \
      "" \
      "## Test plan" \
      "- [x] \`printf ok\`" \
      "" \
      "Final PR: yes" \
      "Closes #42"

    cat > "$open_prs" <<'JSON'
{
  "pulls": [
    {"number": 10, "body": "Final PR: no\nRefs #42"},
    {"number": 11, "body": "Final PR: yes\nCloses #42"}
  ]
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/pr_body_structure.py" --pr-number 11 --open-prs-json "$open_prs" < "$body_file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"other open PRs reference the same issue #42: #10"* ]]
}

@test "release_please_policy.py reports config validation failures" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local manifest_file="$TEST_DIR/.release-please-manifest.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}' \
      "        run: gh pr merge 1 --auto --merge --delete-branch"

    cat > "$manifest_file" <<'JSON'
{
  "release-notes": "v0.0.0"
}
JSON

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "release ${version}",
  "packages": {
    ".": {
      "extra-files": ["VERSION"],
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false,
    "forbid_legacy_release_auth": true
  },
  "release_pr": {
    "branch_prefix": "release-please--",
    "title_pattern": "Release ${version}",
    "allowed_paths": ["VERSION", "CHANGELOG.md", "**/CHANGELOG.md", ".release-please-manifest.json"]
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json",
    "allow_merge_commit": true,
    "allow_squash_merge": false,
    "allow_rebase_merge": false,
    "allow_auto_merge": true,
    "delete_branch_on_merge": true
  }
}
JSON

    mkdir -p "$TEST_DIR/.github/repository"
    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": false,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"allow_auto_merge must be true"* ]]
    [[ "$output" == *"pull-request-title-pattern must be 'Release \${version}'"* ]]
    [[ "$output" == *"missing types: fix"* ]]
    [[ "$output" == *"plain VERSION must be synchronized by the release workflow"* ]]
}

@test "release_please_policy.py requires exact release push allowlist" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local manifest_file="$TEST_DIR/.release-please-manifest.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "      - \"docs/**\"" \
      "      - \"**\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}' \
      "        run: gh pr merge 1 --auto --merge --delete-branch"

    cat > "$manifest_file" <<'JSON'
{
  "release-notes": "v0.0.0"
}
JSON

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        },
        {
          "type": "fix",
          "section": "Fixes",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false,
    "forbid_legacy_release_auth": true
  },
  "release_pr": {
    "branch_prefix": "release-please--",
    "title_pattern": "Release ${version}",
    "allowed_paths": ["VERSION", "CHANGELOG.md", "**/CHANGELOG.md", ".release-please-manifest.json"]
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json",
    "allow_merge_commit": true,
    "allow_squash_merge": false,
    "allow_rebase_merge": false,
    "allow_auto_merge": true,
    "delete_branch_on_merge": true
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unexpected push paths"* ]]
}

@test "release_please_policy.py rejects pull_request_target labeled gate" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local manifest_file="$TEST_DIR/.release-please-manifest.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "\"on\":" \
      "  pull_request_target:" \
      "    types:" \
      "      - labeled" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}' \
      "        run: gh pr merge 1 --auto --merge --delete-branch"

    cat > "$manifest_file" <<'JSON'
{
  "release-notes": "v0.0.0"
}
JSON

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        },
        {
          "type": "fix",
          "section": "Fixes",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false
  },
  "release_pr": {
    "branch_prefix": "release-please--",
    "title_pattern": "Release ${version}",
    "allowed_paths": ["VERSION", "CHANGELOG.md", "**/CHANGELOG.md", ".release-please-manifest.json"]
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json",
    "allow_merge_commit": true,
    "allow_squash_merge": false,
    "allow_rebase_merge": false,
    "allow_auto_merge": true,
    "delete_branch_on_merge": true
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"label-based gate detected"* ]]
}

@test "release_please_policy.py requires GITHUB_TOKEN and publish-only mode" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local manifest_file="$TEST_DIR/.release-please-manifest.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        run: gh pr merge 1 --auto --merge --delete-branch"

    cat > "$manifest_file" <<'JSON'
{
  "release-notes": "v0.0.0"
}
JSON

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        },
        {
          "type": "fix",
          "section": "Fixes",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json"
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"release workflow must use secrets.GITHUB_TOKEN"* ]]
    [[ "$output" == *"workflow_dispatch mode=publish with skip-github-pull-request is required"* ]]
}

@test "release_please_policy.py rejects missing new release workflow policy flags" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local manifest_file="$TEST_DIR/.release-please-manifest.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}' \
      "        run: gh pr merge 1 --auto --merge --delete-branch"

    cat > "$manifest_file" <<'JSON'
{
  "release-notes": "v0.0.0"
}
JSON

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        },
        {
          "type": "fix",
          "section": "Fixes",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "require_allowed_actors_reference": false,
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false
  },
  "release_pr": {
    "branch_prefix": "release-please--",
    "title_pattern": "Release ${version}",
    "allowed_paths": ["CHANGELOG.md", "**/CHANGELOG.md", ".release-please-manifest.json"]
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json"
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"workflow.github_token_required must be true."* ]]
    [[ "$output" == *"workflow.publish_mode_required must be true."* ]]
    [[ "$output" == *"workflow.plain_version_sync_required must be true."* ]]
    [[ "$output" == *"workflow.git_credential_helper_required must be true."* ]]
    [[ "$output" == *"workflow.forbid_inline_http_extraheader must be true."* ]]
    [[ "$output" == *"workflow.merge_subject_required must be true."* ]]
    [[ "$output" == *"workflow.merge_empty_body_required must be true."* ]]
    [[ "$output" == *"workflow.release_branch_delete_required must be true."* ]]
    [[ "$output" == *"workflow.forbid_legacy_release_auth must be true."* ]]
}

@test "release_please_policy.py rejects legacy actor variables in additional workflows" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local extra_workflow_file="$TEST_DIR/.github/workflows/pr-lint.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local manifest_file="$TEST_DIR/.release-please-manifest.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}' \
      "        run: gh pr merge 1 --auto --merge --delete-branch"

    cat > "$extra_workflow_file" <<'YAML'
name: PR Lint

on:
  pull_request:
    types: [opened]

jobs:
  pr-lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo skip
YAML

    cat > "$manifest_file" <<'JSON'
{
  "release-notes": "v0.0.0"
}
JSON

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        },
        {
          "type": "fix",
          "section": "Fixes",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "additional_workflows": [
      ".github/workflows/pr-lint.yml"
    ],
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false,
    "forbid_legacy_release_auth": true
  },
  "release_pr": {
    "branch_prefix": "release-please--",
    "title_pattern": "Release ${version}",
    "allowed_paths": ["CHANGELOG.md", "**/CHANGELOG.md", ".release-please-manifest.json"]
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json"
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"legacy RELEASE_TOKEN or RELEASE_PLEASE_ALLOWED_ACTORS reference is forbidden"* ]]
}

@test "release_please_policy.py passes with GITHUB_TOKEN, plain VERSION sync, and publish-only mode" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local lint_workflow_file="$TEST_DIR/.github/workflows/pr-lint.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local manifest_file="$TEST_DIR/.release-please-manifest.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "    inputs:" \
      "      mode:" \
      "        type: choice" \
      "        options:" \
      "          - pr" \
      "          - publish" \
      "" \
      "permissions:" \
      "  contents: write" \
      "  pull-requests: write" \
      "  actions: write" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - uses: googleapis/release-please-action@v4" \
      "        with:" \
      '          token: ${{ secrets.GITHUB_TOKEN }}' \
      "          skip-github-pull-request: \${{ github.event_name == 'workflow_dispatch' && inputs.mode == 'publish' }}" \
      "      - name: Sync VERSION in release PR" \
      "        run: |" \
      "          sync_version_from_manifest() {" \
      "            jq -r '.\".\" // empty' .release-please-manifest.json" \
      "            echo \"VERSION is already synchronized\"" \
      "            git -C \"\$workdir\" add VERSION" \
      "            git -C \"\$workdir\" push origin \"HEAD:\$head_ref\"" \
      "          }" \
      "          assert_release_pr_allowed_files 1" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}' \
      "        run: |" \
      "          git config --global credential.helper '!f() { echo \"username=x-access-token\"; echo \"password=\$GH_TOKEN\"; }; f'" \
      "          pr_title=\"Release 1.2.3\"" \
      "          gh pr view 1 --json headRefName --jq '.headRefName'" \
      "          head_ref=\"release-please--branches--main\"" \
      "          gh pr merge 1 --auto --merge --delete-branch --repo \"\$REPO\" --subject \"\${pr_title:-Release}\" --body \"\"" \
      "          git push origin --delete \"\$head_ref\"" \
      "      - run: gh workflow run release-please.yml --ref main -f mode=publish"

    cat > "$lint_workflow_file" <<'YAML'
name: PR Lint

jobs:
  pr-lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YAML

    cat > "$manifest_file" <<'JSON'
{
  "release-notes": "v0.0.0"
}
JSON

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "release-type": "node",
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        },
        {
          "type": "fix",
          "section": "Fixes",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "additional_workflows": [".github/workflows/pr-lint.yml"],
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false,
    "github_token_required": true,
    "publish_mode_required": true,
    "plain_version_sync_required": true,
    "git_credential_helper_required": true,
    "forbid_inline_http_extraheader": true,
    "merge_subject_required": true,
    "merge_empty_body_required": true,
    "release_branch_delete_required": true,
    "forbid_legacy_release_auth": true
  },
  "release_pr": {
    "branch_prefix": "release-please--",
    "title_pattern": "Release ${version}",
    "allowed_paths": ["VERSION", "CHANGELOG.md", "**/CHANGELOG.md", ".release-please-manifest.json"]
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json",
    "allow_merge_commit": true,
    "allow_squash_merge": false,
    "allow_rebase_merge": false,
    "allow_auto_merge": true,
    "delete_branch_on_merge": true
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_merge_commit": true,
  "allow_squash_merge": false,
  "allow_rebase_merge": false,
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 0 ]
}

@test "release_please_policy.py rejects policy redirecting workflow.file to non-release workflow" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local fake_workflow_file="$TEST_DIR/.github/workflows/fake-release.yml"
    local lint_workflow_file="$TEST_DIR/.github/workflows/pr-lint.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local manifest_file="$TEST_DIR/.release-please-manifest.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}' \
      "        run: gh pr merge 1 --auto --merge --delete-branch"

    write_file "$fake_workflow_file" \
      "name: Fake Workflow" \
      "" \
      "on:" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  fake:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - run: echo fake"

    cat > "$lint_workflow_file" <<'YAML'
name: PR Lint

jobs:
  pr-lint:
    runs-on: ubuntu-latest
    env:
      RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}
    steps:
      - run: echo ok
YAML

    cat > "$manifest_file" <<'JSON'
{
  "release-notes": "v0.0.0"
}
JSON

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        },
        {
          "type": "fix",
          "section": "Fixes",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/fake-release.yml",
    "dispatch_enabled": true,
    "additional_workflows": [".github/workflows/pr-lint.yml"],
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false,
    "require_allowed_actors_reference": true
  },
  "release_pr": {
    "branch_prefix": "release-please--",
    "title_pattern": "Release ${version}",
    "allowed_paths": ["CHANGELOG.md", "**/CHANGELOG.md", ".release-please-manifest.json"]
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json"
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"workflow.file must be '.github/workflows/release-please.yml'."* ]]
}

@test "release_please_policy.py requires pr-lint in workflow.additional_workflows" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local lint_workflow_file="$TEST_DIR/.github/workflows/pr-lint.yml"
    local extra_workflow_file="$TEST_DIR/.github/workflows/custom-lint.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local manifest_file="$TEST_DIR/.release-please-manifest.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}' \
      "        run: gh pr merge 1 --auto --merge --delete-branch"

    cat > "$lint_workflow_file" <<'YAML'
name: PR Lint

jobs:
  pr-lint:
    runs-on: ubuntu-latest
    env:
      RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}
    steps:
      - run: echo ok
YAML

    cat > "$extra_workflow_file" <<'YAML'
name: Custom Lint

jobs:
  custom:
    runs-on: ubuntu-latest
    env:
      RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}
    steps:
      - run: echo custom
YAML

    cat > "$manifest_file" <<'JSON'
{
  "release-notes": "v0.0.0"
}
JSON

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        },
        {
          "type": "fix",
          "section": "Fixes",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "additional_workflows": [".github/workflows/custom-lint.yml"],
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false,
    "require_allowed_actors_reference": true
  },
  "release_pr": {
    "branch_prefix": "release-please--",
    "title_pattern": "Release ${version}",
    "allowed_paths": ["CHANGELOG.md", "**/CHANGELOG.md", ".release-please-manifest.json"]
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json"
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"workflow.additional_workflows must include '.github/workflows/pr-lint.yml'."* ]]
}

@test "release_please_policy.py rejects redirected config targets, actor variable, and echo merge bypass" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local lint_workflow_file="$TEST_DIR/.github/workflows/pr-lint.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}' \
      "        run: echo gh pr merge 1 --auto --merge --delete-branch"

    cat > "$lint_workflow_file" <<'YAML'
name: PR Lint

jobs:
  pr-lint:
    runs-on: ubuntu-latest
    env:
      RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}
    steps:
      - run: echo ok
YAML

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        },
        {
          "type": "fix",
          "section": "Fixes",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "additional_workflows": [".github/workflows/pr-lint.yml"],
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false,
    "allowed_actors_variable": "name",
    "require_allowed_actors_reference": true
  },
  "release_pr": {
    "branch_prefix": "release-please--",
    "title_pattern": "Release ${version}",
    "allowed_paths": ["CHANGELOG.md", "**/CHANGELOG.md", ".release-please-manifest.json"]
  },
  "release_please_config": {
    "file": "safe-release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/safe-pull-request-settings.json"
  }
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"repository_settings.file must be '.github/repository/pull-request-settings.json'."* ]]
    [[ "$output" == *"release_please_config.file must be 'release-please-config.json'."* ]]
    [[ "$output" == *"missing merge command 'gh pr merge --auto --merge --delete-branch'"* ]]
}

@test "release_please_policy.py rejects no-op merge command variants" {
    run python3 - "$REPO_ROOT/assets/github/scripts/release_please_policy.py" <<'PY'
import importlib.util
import sys

module_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("release_please_policy", module_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

if module.has_required_merge_command("run: echo gh pr merge 1 --auto --merge --delete-branch"):
    raise SystemExit("echoed merge command should not satisfy release merge check")

if module.has_required_merge_command("run: gh pr merge 1 --auto --merge --delete-branch --help"):
    raise SystemExit("--help merge command should not satisfy release merge check")

if not module.has_required_merge_command('run: gh pr merge "$pr_number" --auto --merge --delete-branch --repo "$REPO"'):
    raise SystemExit("real release merge command should satisfy release merge check")
PY
    [ "$status" -eq 0 ]
}

@test "release_please_policy.py requires full changelog checks and still rejects hidden sections" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local lint_workflow_file="$TEST_DIR/.github/workflows/pr-lint.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}' \
      "        run: gh pr merge 1 --auto --merge --delete-branch"

    cat > "$lint_workflow_file" <<'YAML'
name: PR Lint

jobs:
  pr-lint:
    runs-on: ubuntu-latest
    env:
      RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}
    steps:
      - run: echo ok
YAML

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": true
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "additional_workflows": [".github/workflows/pr-lint.yml"],
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false,
    "require_allowed_actors_reference": true
  },
  "release_pr": {
    "branch_prefix": "release-please--",
    "title_pattern": "Release ${version}",
    "allowed_paths": ["CHANGELOG.md", "**/CHANGELOG.md", ".release-please-manifest.json"]
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": false,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json"
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"release_please_config.require_full_changelog_types must be true."* ]]
    [[ "$output" == *"changelog section 'feat' must not be hidden."* ]]
    [[ "$output" == *"changelog-sections is missing types: fix."* ]]
}

@test "release_please_policy.py rejects empty changelog type policy" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local lint_workflow_file="$TEST_DIR/.github/workflows/pr-lint.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}' \
      "        run: gh pr merge 1 --auto --merge --delete-branch"

    cat > "$lint_workflow_file" <<'YAML'
name: PR Lint

jobs:
  pr-lint:
    runs-on: ubuntu-latest
    env:
      RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}
    steps:
      - run: echo ok
YAML

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "additional_workflows": [".github/workflows/pr-lint.yml"],
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false,
    "require_allowed_actors_reference": true
  },
  "release_pr": {
    "branch_prefix": "release-please--",
    "title_pattern": "Release ${version}",
    "allowed_paths": ["CHANGELOG.md", "**/CHANGELOG.md", ".release-please-manifest.json"]
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": []
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json"
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"release_please_config.required_changelog_types must be a non-empty array."* ]]
}

@test "release_please fixed actor guard accepts only release bots" {
    run python3 - <<'PY'
def is_release_actor(author: str) -> bool:
    actor = (author or "").strip().lower()
    return actor in {"github-actions[bot]", "release-please[bot]"}


if is_release_actor("release-owner"):
    raise SystemExit("PAT owner should be denied")

if is_release_actor("alice"):
    raise SystemExit("configured human owners are no longer allowed")

if not is_release_actor("github-actions[bot]"):
    raise SystemExit("default github-actions bot should be allowed")

if not is_release_actor("release-please[bot]"):
    raise SystemExit("default release-please bot should be allowed")

if is_release_actor("dependabot[bot]"):
    raise SystemExit("other bot should not be allowed")

print("release-please fixed actor guard validated")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"release-please fixed actor guard validated"* ]]
}

@test "release_please_policy.py validates release_pr shape fields" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false
  },
  "release_pr": {
    "branch_prefix": "",
    "title_pattern": 123,
    "allowed_paths": []
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json"
  }
}
JSON

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}' \
      "        run: gh pr merge 1 --auto --merge --delete-branch"

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"release_pr.branch_prefix must be a non-empty string."* ]]
    [[ "$output" == *"release_pr.title_pattern must be a non-empty string."* ]]
    [[ "$output" == *"release_pr.allowed_paths must be a non-empty array."* ]]
}

@test "release_please_policy.py requires release_pr policy section" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json"
  }
}
JSON

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}' \
      "        run: gh pr merge 1 --auto --merge --delete-branch"

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        },
        {
          "type": "fix",
          "section": "Fixes",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"release_pr must be an object."* ]]
}

@test "release_please_policy.py rejects label-based merge bypass logic" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local manifest_file="$TEST_DIR/.release-please-manifest.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    cat > "$workflow_file" <<'YAML'
name: Release Please

on:
  push:
    branches:
      - main
    paths:
      - "src/**"
      - "release-please-config.json"
  workflow_dispatch:

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - uses: googleapis/release-please-action@v4
        id: release
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          config-file: release-please-config.json
          manifest-file: .release-please-manifest.json
      - name: Merge release-please PR
        run: |
          LABELS="$(printf '${{ \"\" }}')"
          if printf '%s' "$LABELS" | grep -Eq '^autorelease:'; then
            echo "release please label bypass"
          fi
      - name: Merge release PR
        env:
          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        if: ${{ steps.release.outcome == 'success' }}
        run: |
          gh pr merge 1 --auto --merge --delete-branch --repo "${{ github.repository }}"
YAML

    cat > "$manifest_file" <<'JSON'
{
  "release-notes": "v0.0.0"
}
JSON

    cat > "$config_file" <<'JSON'
{
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        },
        {
          "type": "fix",
          "section": "Fixes",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json"
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"label-based signal detected"* ]]
}

@test "release_please_policy.py rejects label-based merge bypass in additional workflows" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local lint_workflow_file="$TEST_DIR/.github/workflows/pr-lint.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local manifest_file="$TEST_DIR/.release-please-manifest.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    write_file "$workflow_file" \
      "name: Release Please" \
      "" \
      "on:" \
      "  push:" \
      "    branches:" \
      "      - main" \
      "    paths:" \
      "      - \"src/**\"" \
      "      - \"release-please-config.json\"" \
      "  workflow_dispatch:" \
      "" \
      "jobs:" \
      "  release-please:" \
      "    runs-on: ubuntu-latest" \
      "    steps:" \
      "      - name: Merge release-please PR" \
      "        env:" \
      '          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}' \
      "        run: gh pr merge 1 --auto --merge --delete-branch"

    cat > "$lint_workflow_file" <<'YAML'
name: PR Lint

env:
  RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}

"on":
  pull_request_target:
    types: [opened, labeled]

jobs:
  pr-lint:
    runs-on: ubuntu-latest
    steps:
      - name: Detect release-please PR
        run: |
          if [ "$GITHUB_EVENT_NAME" = "pull_request_target" ]; then
            echo "bypass by label"
          fi
YAML

    cat > "$manifest_file" <<'JSON'
{
  "release-notes": "v0.0.0"
}
JSON

    cat > "$config_file" <<'JSON'
{
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        },
        {
          "type": "fix",
          "section": "Fixes",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "additional_workflows": [".github/workflows/pr-lint.yml"],
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": false
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json"
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"label-based gate detected"* ]]
}

@test "release_please_policy.py requires label_gate_required=false and still scans label gates" {
    local policy_file="$TEST_DIR/release-please-policy.json"
    local workflow_file="$TEST_DIR/.github/workflows/release-please.yml"
    local config_file="$TEST_DIR/release-please-config.json"
    local manifest_file="$TEST_DIR/.release-please-manifest.json"
    local settings_file="$TEST_DIR/.github/repository/pull-request-settings.json"

    mkdir -p "$TEST_DIR/.github/workflows" "$TEST_DIR/.github/repository"

    cat > "$workflow_file" <<'YAML'
name: Release Please

on:
  pull_request:
    types:
      - labeled
  push:
    branches:
      - main
    paths:
      - "src/**"
      - "release-please-config.json"
  workflow_dispatch:

jobs:
  release-please:
    runs-on: ubuntu-latest
    steps:
      - name: Merge release-please PR
        env:
          RELEASE_PLEASE_ALLOWED_ACTORS: ${{ vars.RELEASE_PLEASE_ALLOWED_ACTORS }}
        run: gh pr merge 1 --auto --merge --delete-branch
YAML

    cat > "$manifest_file" <<'JSON'
{
  "release-notes": "v0.0.0"
}
JSON

    cat > "$config_file" <<'JSON'
{
  "pull-request-title-pattern": "Release ${version}",
  "packages": {
    ".": {
      "changelog-sections": [
        {
          "type": "feat",
          "section": "Features",
          "hidden": false
        },
        {
          "type": "fix",
          "section": "Fixes",
          "hidden": false
        }
      ]
    }
  }
}
JSON

    cat > "$policy_file" <<'JSON'
{
  "workflow": {
    "file": ".github/workflows/release-please.yml",
    "dispatch_enabled": true,
    "push_paths": ["src/**", "release-please-config.json"],
    "merge_command": "gh pr merge --auto --merge --delete-branch",
    "label_gate_required": true
  },
  "release_pr": {
    "branch_prefix": "release-please--",
    "title_pattern": "Release ${version}",
    "allowed_paths": ["CHANGELOG.md", "**/CHANGELOG.md", ".release-please-manifest.json"]
  },
  "release_please_config": {
    "file": "release-please-config.json",
    "pull_request_title_pattern": "Release ${version}",
    "require_full_changelog_types": true,
    "required_changelog_types": ["feat", "fix"]
  },
  "repository_settings": {
    "file": ".github/repository/pull-request-settings.json"
  }
}
JSON

    cat > "$settings_file" <<'JSON'
{
  "allow_auto_merge": true,
  "delete_branch_on_merge": true
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/release_please_policy.py" "$policy_file" "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"workflow.label_gate_required must be false."* ]]
    [[ "$output" == *"label-based gate detected"* ]]
}

@test "pr_tdd_check.py skips when no enforcement patterns are configured" {
    local policy_file="$TEST_DIR/pr-tdd-policy.json"
    cat > "$policy_file" <<'JSON'
{
  "impl_patterns": [],
  "test_patterns": [],
  "exempt_patterns": []
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/pr_tdd_check.py" "$policy_file" --repo-root "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: Policy lacks impl_patterns/test_patterns; no TDD enforceable scope configured."* ]]
}

@test "pr_tdd_check.py validates policy in validate-only mode" {
    local policy_file="$TEST_DIR/pr-tdd-policy.json"
    cat > "$policy_file" <<'JSON'
{
  "impl_patterns": ["^src/.*\\.py$"],
  "test_patterns": ["^test/.*\\.py$"],
  "exempt_patterns": []
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/pr_tdd_check.py" "$policy_file" --validate-policy-only
    [ "$status" -eq 0 ]
    [[ "$output" == *"policy file is valid (policy-only mode)"* ]]

    cat > "$policy_file" <<'JSON'
{
  "impl_patterns": ["(["],
  "test_patterns": ["^test/.*\\.py$"],
  "exempt_patterns": []
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/pr_tdd_check.py" "$policy_file" --validate-policy-only
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid regex in 'impl_patterns':"* ]]
}

@test "pr_tdd_check.py skips when policy is empty even with synthetic base/head refs" {
    local policy_file="$TEST_DIR/pr-tdd-policy.json"
    cat > "$policy_file" <<'JSON'
{
  "impl_patterns": [],
  "test_patterns": [],
  "exempt_patterns": []
}
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/pr_tdd_check.py" "$policy_file" --base "1234567890abcdef" --head "fedcba0987654321" --repo-root "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP: Policy lacks impl_patterns/test_patterns; no TDD enforceable scope configured."* ]]
}

@test "pr_tdd_check.py fails when implementation changes have no test changes" {
    local policy_file="$TEST_DIR/pr-tdd-policy.json"
    local files_json="$TEST_DIR/changed-files.json"

    cat > "$policy_file" <<'JSON'
{
  "impl_patterns": ["src/"],
  "test_patterns": ["test/"],
  "exempt_patterns": []
}
JSON

    write_file "$files_json" '["src/app.py"]'

    run python3 "$REPO_ROOT/assets/github/scripts/pr_tdd_check.py" "$policy_file" --files-json "$files_json" --repo-root "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"implementation-path files were changed but no test-pattern files were changed"* ]]
}

@test "pr_tdd_check.py fails when first test commit is later than implementation commit" {
    local policy_file="$TEST_DIR/pr-tdd-policy.json"
    local files_json="$TEST_DIR/changed-files.json"
    local commits_json="$TEST_DIR/commits.json"

    cat > "$policy_file" <<'JSON'
{
  "impl_patterns": ["src/"],
  "test_patterns": ["test/"],
  "exempt_patterns": []
}
JSON

    write_file "$files_json" '["src/app.py","test/app_test.py"]'
    cat > "$commits_json" <<'JSON'
[
  {"sha":"1111111111111111111111111111111111111111","subject":"feat: add impl","files":[{"filename":"src/app.py"}],"committed_at":1700000001},
  {"sha":"2222222222222222222222222222222222222222","subject":"test: add coverage","files":[{"filename":"test/app_test.py"}],"committed_at":1700000002}
]
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/pr_tdd_check.py" "$policy_file" --files-json "$files_json" --commits-json "$commits_json" --repo-root "$TEST_DIR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"first test commit is later than first implementation commit"* ]]
}

@test "pr_tdd_check.py accepts commit JSON with object file entries and message field" {
    local policy_file="$TEST_DIR/pr-tdd-policy.json"
    local files_json="$TEST_DIR/changed-files.json"
    local commits_json="$TEST_DIR/commits.json"

    cat > "$policy_file" <<'JSON'
{
  "impl_patterns": ["src/"],
  "test_patterns": ["test/"],
  "exempt_patterns": []
}
JSON

    write_file "$files_json" '[{"path":"src/app.py"},{"name":"test/app_test.py"}]'
    cat > "$commits_json" <<'JSON'
[
  {"sha":"1111111111111111111111111111111111111111","message":"test: add coverage","files":[{"path":"test/app_test.py"},{"filename":"README.md"}],"committed_at":1700000001},
  {"sha":"2222222222222222222222222222222222222222","message":"feat: add impl","files":[{"path":"src/app.py"}],"committed_at":1700000002}
]
JSON

    run python3 "$REPO_ROOT/assets/github/scripts/pr_tdd_check.py" "$policy_file" --files-json "$files_json" --commits-json "$commits_json" --repo-root "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: TDD policy passed."* ]]
}
