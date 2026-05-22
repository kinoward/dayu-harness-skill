#!/usr/bin/env python3
"""Validate release-please policy constraints in a project."""

from __future__ import annotations

import json
import re
import shlex
import sys
from pathlib import Path
from collections import Counter


REQUIRED_PRIMARY_WORKFLOW = ".github/workflows/release-please.yml"
REQUIRED_ADDITIONAL_WORKFLOW = ".github/workflows/pr-lint.yml"
REQUIRED_MERGE_COMMAND = "gh pr merge --auto --merge --delete-branch"
REQUIRED_REPOSITORY_SETTINGS_FILE = ".github/repository/pull-request-settings.json"
REQUIRED_RELEASE_CONFIG_FILE = "release-please-config.json"


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def parse_args() -> tuple[Path, Path]:
    if len(sys.argv) != 3:
        print(
            "Usage: release_please_policy.py <policy_path> <project_root>",
            file=sys.stderr,
        )
        raise SystemExit(1)

    policy_path = Path(sys.argv[1]).expanduser()
    if not policy_path.is_absolute():
        policy_path = (Path.cwd() / policy_path).resolve()

    project_root = Path(sys.argv[2]).expanduser()
    if not project_root.is_absolute():
        project_root = (Path.cwd() / project_root).resolve()

    return policy_path, project_root


def load_json(path: Path) -> dict:
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        die(f"Cannot read JSON file '{path}': {exc}")

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        die(f"Invalid JSON in '{path}': {exc}")

    if not isinstance(data, dict):
        die(f"JSON root in '{path}' must be an object.")

    return data


def extract_yaml_key(line: str) -> str | None:
    stripped = line.strip()
    if ":" not in stripped:
        return None

    raw_key = stripped.split(":", 1)[0].strip()
    if (raw_key.startswith('"') and raw_key.endswith('"')) or (
        raw_key.startswith("'") and raw_key.endswith("'")
    ):
        return raw_key[1:-1]
    return raw_key


def parse_workflow_triggers(workflow_text: str) -> tuple[bool, list[str]]:
    lines = workflow_text.splitlines()
    in_on = False
    in_push = False
    in_paths = False
    workflow_dispatch = False
    push_paths: list[str] = []

    for raw in lines:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue

        indent = len(raw) - len(raw.lstrip(" "))
        if indent == 0:
            in_on = extract_yaml_key(stripped) == "on"
            in_push = False
            in_paths = False
            continue

        if not in_on:
            continue

        if indent == 2 and stripped.endswith(":"):
            key = extract_yaml_key(stripped)
            if key is None:
                continue
            if key == "workflow_dispatch":
                workflow_dispatch = True
                in_push = False
                in_paths = False
                continue

            in_push = key == "push"
            in_paths = False
            continue

        if in_push and indent == 4 and stripped.endswith(":"):
            in_paths = stripped.startswith("paths:")
            continue

        if in_paths:
            if indent < 6:
                in_paths = False
                continue
            if stripped.startswith("- "):
                value = stripped[2:].strip().strip('"').strip("'")
                if value:
                    push_paths.append(value)
                continue
            if stripped.startswith("-"):
                value = stripped[1:].strip().strip('"').strip("'")
                if value:
                    push_paths.append(value)
                continue

    return workflow_dispatch, push_paths


def has_label_gate(workflow_text: str) -> bool:
    lines = workflow_text.splitlines()
    in_on = False
    current_event = None
    in_types_block = False

    for raw in lines:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue

        indent = len(raw) - len(raw.lstrip(" "))

        if indent == 0:
            in_on = extract_yaml_key(stripped) == "on"
            current_event = None
            in_types_block = False
            continue

        if not in_on:
            continue

        if indent == 2 and ":" in stripped:
            current_event = extract_yaml_key(stripped)
            in_types_block = False
            if current_event is None:
                continue

            inline_types = stripped.split(":", 1)[1].strip()
            if current_event in {"pull_request", "pull_request_target"} and inline_types:
                if inline_types.startswith("[") and "labeled" in inline_types.lower():
                    return True
            in_types_block = False
            continue

        if current_event not in {"pull_request", "pull_request_target"}:
            continue

        if indent == 4 and stripped.startswith("types:"):
            in_types_block = True
            inline_types = stripped.split(":", 1)[1].strip()
            if inline_types.startswith("[") and "labeled" in inline_types.lower():
                return True
            if inline_types:
                in_types_block = False
                continue
            continue

        if in_types_block:
            if indent < 6:
                in_types_block = False
                continue
            if stripped.startswith("-"):
                item = stripped[1:].strip().strip("`\"'")
                if item.lower() == "labeled":
                    return True
            continue

        if re.search(r"\bgithub\.event_name\s*==\s*['\"]pull_request_target['\"]", stripped, re.IGNORECASE):
            if "labeled" in stripped.lower():
                return True
        if re.search(r"\bgithub\.event\.action\s*==\s*['\"]labeled['\"]", stripped, re.IGNORECASE):
            return True

    if re.search(r"github\.event\.label", workflow_text, re.IGNORECASE):
        return True

    return False


def has_label_bypass_signal(workflow_text: str) -> bool:
    lowered = workflow_text.lower()
    suspicious_patterns = [
        r"has_autorelease_label",
        r"github\.event\.label",
        r"\bgithub\.event\.pull_request\.labels\b",
        r"\bbased on.*label",
        r"\blabel.*named\s*['\"]autorelease:",
    ]

    for pattern in suspicious_patterns:
        if re.search(pattern, lowered):
            return True

    if "autorelease" in lowered and "label" in lowered:
        return True

    return False


def has_github_token_reference(workflow_text: str) -> bool:
    return bool(
        re.search(r"\$\{\{\s*secrets\.GITHUB_TOKEN\s*\}\}", workflow_text)
        or re.search(r"\$\{\{\s*github\.token\s*\}\}", workflow_text)
    )


def has_publish_only_mode(workflow_text: str) -> bool:
    lowered = workflow_text.lower()
    return (
        "workflow_dispatch" in lowered
        and re.search(r"(?im)^\s*mode\s*:", workflow_text) is not None
        and "skip-github-pull-request" in lowered
        and "publish" in lowered
    )


def has_publish_dispatch_after_merge(workflow_text: str) -> bool:
    return bool(
        re.search(r"\bgh\s+workflow\s+run\s+release-please\.yml\b", workflow_text)
        and re.search(r"-f\s+mode=publish\b", workflow_text)
    )


def has_plain_version_manifest_sync(workflow_text: str) -> bool:
    return all(
        marker in workflow_text
        for marker in (
            "sync_version_from_manifest",
            ".release-please-manifest.json",
            "VERSION is already synchronized",
            "git -C \"$workdir\" add VERSION",
            "push origin \"HEAD:$head_ref\"",
            "assert_release_pr_allowed_files",
        )
    )


def has_actions_write_permission(workflow_text: str) -> bool:
    return bool(re.search(r"(?m)^\s+actions\s*:\s*write\s*$", workflow_text))


def has_legacy_release_auth_reference(workflow_text: str) -> bool:
    return bool(
        re.search(r"\bRELEASE_TOKEN\b", workflow_text)
        or re.search(r"\bRELEASE_PLEASE_ALLOWED_ACTORS\b", workflow_text)
    )


def has_required_merge_command(workflow_text: str) -> bool:
    for line in workflow_text.splitlines():
        command = line.strip()
        if command.startswith("run:"):
            command = command[4:].strip()

        if any(token in command for token in ("||", "&&", ";")):
            continue

        try:
            tokens = shlex.split(command)
        except ValueError:
            continue

        if tokens[:3] != ["gh", "pr", "merge"]:
            continue
        if any(token in {"--help", "-h"} for token in tokens):
            continue
        if len(tokens) < 5:
            continue

        target = tokens[3]
        if not target or target.startswith("-"):
            continue

        if all(flag in tokens for flag in ("--auto", "--merge", "--delete-branch")):
            return True

    return False


def validate_release_pr_policy(policy: dict, errors: list[str]) -> None:
    release_pr = policy.get("release_pr")
    if release_pr is None:
        errors.append("release_pr must be an object.")
        return

    if not isinstance(release_pr, dict):
        errors.append("release_pr must be an object.")
        return

    branch_prefix = release_pr.get("branch_prefix")
    if "branch_prefix" in release_pr and (
        not isinstance(branch_prefix, str) or not branch_prefix.strip()
    ):
        errors.append("release_pr.branch_prefix must be a non-empty string.")

    title_pattern = release_pr.get("title_pattern")
    if "title_pattern" in release_pr and (
        not isinstance(title_pattern, str) or not title_pattern.strip()
    ):
        errors.append("release_pr.title_pattern must be a non-empty string.")

    allowed_paths = release_pr.get("allowed_paths")
    if not isinstance(allowed_paths, list) or not allowed_paths:
        errors.append("release_pr.allowed_paths must be a non-empty array.")
        return

    invalid_items = [
        item
        for item in allowed_paths
        if not isinstance(item, str) or not item.strip()
    ]
    if invalid_items:
        errors.append("release_pr.allowed_paths entries must be non-empty strings.")
    if "VERSION" not in allowed_paths:
        errors.append("release_pr.allowed_paths must include VERSION.")


def validate_repository_settings(policy: dict, project_root: Path, errors: list[str]) -> None:
    settings_policy = policy.get("repository_settings", {})
    if not isinstance(settings_policy, dict):
        errors.append("repository_settings must be an object.")
        return

    settings_path = settings_policy.get("file", REQUIRED_REPOSITORY_SETTINGS_FILE)
    if not isinstance(settings_path, str) or not settings_path.strip():
        errors.append("repository_settings.file must be a non-empty string.")
        settings_path = REQUIRED_REPOSITORY_SETTINGS_FILE
    elif settings_path != REQUIRED_REPOSITORY_SETTINGS_FILE:
        errors.append(f"repository_settings.file must be '{REQUIRED_REPOSITORY_SETTINGS_FILE}'.")
        settings_path = REQUIRED_REPOSITORY_SETTINGS_FILE

    settings_path = project_root / Path(settings_path)
    settings = load_json(settings_path)

    if settings.get("allow_auto_merge") is not True:
        errors.append(f"{settings_path}: allow_auto_merge must be true.")

    if settings.get("delete_branch_on_merge") is not True:
        errors.append(f"{settings_path}: delete_branch_on_merge must be true.")


def validate_workflow(policy: dict, project_root: Path, errors: list[str]) -> None:
    workflow_policy = policy.get("workflow", {})
    if not isinstance(workflow_policy, dict):
        errors.append("workflow policy must be an object.")
        return

    configured_workflow_file = workflow_policy.get("file", REQUIRED_PRIMARY_WORKFLOW)
    if not isinstance(configured_workflow_file, str) or not configured_workflow_file.strip():
        errors.append("workflow.file must be a non-empty string.")
        configured_workflow_file = REQUIRED_PRIMARY_WORKFLOW
    elif configured_workflow_file != REQUIRED_PRIMARY_WORKFLOW:
        errors.append(f"workflow.file must be '{REQUIRED_PRIMARY_WORKFLOW}'.")

    workflow_path = project_root / Path(REQUIRED_PRIMARY_WORKFLOW)
    try:
        workflow_text = workflow_path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"Cannot read workflow '{workflow_path}': {exc}")
        return

    workflow_dispatch, push_paths = parse_workflow_triggers(workflow_text)
    if workflow_policy.get("dispatch_enabled") is not True:
        errors.append("workflow.dispatch_enabled must be true.")
    if not workflow_dispatch:
        errors.append(f"{workflow_path}: workflow_dispatch must be enabled.")

    expected_paths = workflow_policy.get("push_paths")
    if expected_paths is None:
        errors.append("workflow.push_paths must be a non-empty array.")
        expected_paths = []
    elif not isinstance(expected_paths, list):
        errors.append("workflow.push_paths must be a non-empty array.")
        expected_paths = []
    elif not expected_paths:
        errors.append("workflow.push_paths must be a non-empty array.")
    elif any(not isinstance(path, str) or not path.strip() for path in expected_paths):
        errors.append("workflow.push_paths entries must be non-empty strings.")

    if not push_paths:
        errors.append(f"{workflow_path}: push.paths block is required.")
    else:
        expected_counter = Counter(str(x) for x in expected_paths if isinstance(x, str))
        actual_counter = Counter(push_paths)
        missing_paths = sorted((expected_counter - actual_counter).elements())
        extra_paths = sorted((actual_counter - expected_counter).elements())
        if missing_paths:
            errors.append(
                f"{workflow_path}: missing required push paths: {', '.join(missing_paths)}."
            )
        if extra_paths:
            errors.append(
                f"{workflow_path}: unexpected push paths: {', '.join(extra_paths)}."
            )

    merge_command = workflow_policy.get("merge_command")
    if not isinstance(merge_command, str) or not merge_command.strip():
        errors.append(
            f"workflow.merge_command must be explicitly set to '{REQUIRED_MERGE_COMMAND}'."
        )
        merge_command = REQUIRED_MERGE_COMMAND
    elif merge_command != REQUIRED_MERGE_COMMAND:
        errors.append(
            f"workflow.merge_command must be '{REQUIRED_MERGE_COMMAND}'."
        )

    if not has_required_merge_command(workflow_text):
        errors.append(
            f"{workflow_path}: missing merge command '{REQUIRED_MERGE_COMMAND}'."
        )

    if workflow_policy.get("github_token_required") is not True:
        errors.append("workflow.github_token_required must be true.")
    if not has_github_token_reference(workflow_text):
        errors.append(f"{workflow_path}: release workflow must use secrets.GITHUB_TOKEN.")

    if workflow_policy.get("publish_mode_required") is not True:
        errors.append("workflow.publish_mode_required must be true.")
    if not has_publish_only_mode(workflow_text):
        errors.append(
            f"{workflow_path}: workflow_dispatch mode=publish with skip-github-pull-request is required."
        )
    if not has_publish_dispatch_after_merge(workflow_text):
        errors.append(
            f"{workflow_path}: release PR merge path must dispatch workflow_dispatch mode=publish."
        )
    if workflow_policy.get("plain_version_sync_required") is not True:
        errors.append("workflow.plain_version_sync_required must be true.")
    if not has_plain_version_manifest_sync(workflow_text):
        errors.append(
            f"{workflow_path}: release PR merge path must sync plain VERSION from .release-please-manifest.json before merging."
        )
    if not has_actions_write_permission(workflow_text):
        errors.append(
            f"{workflow_path}: release workflow must grant actions: write for publish dispatch."
        )

    forbid_legacy_release_auth = workflow_policy.get("forbid_legacy_release_auth")
    if forbid_legacy_release_auth is not True:
        errors.append("workflow.forbid_legacy_release_auth must be true.")

    def validate_workflow_text(path: Path, text: str) -> None:
        if has_label_gate(text):
            errors.append(
                f"{path}: label-based gate detected, but policy forbids label gate."
            )
        if has_label_bypass_signal(text):
            errors.append(
                f"{path}: label-based signal detected, but policy forbids autorelease-label bypass."
            )
        if forbid_legacy_release_auth is True and has_legacy_release_auth_reference(text):
            errors.append(
                f"{path}: legacy RELEASE_TOKEN or RELEASE_PLEASE_ALLOWED_ACTORS reference is forbidden."
            )

    if workflow_policy.get("label_gate_required") is not False:
        errors.append("workflow.label_gate_required must be false.")

    validate_workflow_text(workflow_path, workflow_text)

    additional_workflows = workflow_policy.get("additional_workflows")
    if additional_workflows is None:
        errors.append("workflow.additional_workflows must include '.github/workflows/pr-lint.yml'.")
        additional_workflows = []
    elif not isinstance(additional_workflows, list):
        errors.append("workflow.additional_workflows must be an array when provided.")
        additional_workflows = []

    valid_additional_workflows: list[str] = []
    for extra in additional_workflows:
        if not isinstance(extra, str) or not extra.strip():
            errors.append("workflow.additional_workflows entries must be non-empty strings.")
            continue
        valid_additional_workflows.append(extra)

    if REQUIRED_ADDITIONAL_WORKFLOW not in valid_additional_workflows:
        errors.append(
            f"workflow.additional_workflows must include '{REQUIRED_ADDITIONAL_WORKFLOW}'."
        )

    workflows_to_scan = [REQUIRED_ADDITIONAL_WORKFLOW]
    for extra in valid_additional_workflows:
        if extra != REQUIRED_ADDITIONAL_WORKFLOW:
            workflows_to_scan.append(extra)

    for extra in workflows_to_scan:
        extra_workflow_path = project_root / Path(extra)
        try:
            extra_text = extra_workflow_path.read_text(encoding="utf-8")
        except OSError as exc:
            errors.append(f"Cannot read workflow '{extra_workflow_path}': {exc}")
            continue

        validate_workflow_text(extra_workflow_path, extra_text)


def validate_release_config(policy: dict, project_root: Path, errors: list[str]) -> None:
    config_policy = policy.get("release_please_config", {})
    if not isinstance(config_policy, dict):
        errors.append("release_please_config must be an object.")
        return

    config_path = config_policy.get("file", REQUIRED_RELEASE_CONFIG_FILE)
    if not isinstance(config_path, str) or not config_path.strip():
        errors.append("release_please_config.file must be a non-empty string.")
        config_path = REQUIRED_RELEASE_CONFIG_FILE
    elif config_path != REQUIRED_RELEASE_CONFIG_FILE:
        errors.append(f"release_please_config.file must be '{REQUIRED_RELEASE_CONFIG_FILE}'.")
        config_path = REQUIRED_RELEASE_CONFIG_FILE

    config_path = project_root / Path(config_path)
    config = load_json(config_path)

    packages = config.get("packages")
    if not isinstance(packages, dict):
        errors.append(f"{config_path}: packages must be an object.")
        return

    package_cfg = packages.get(".")
    if not isinstance(package_cfg, dict):
        errors.append(
            f"{config_path}: missing default package configuration at packages['.']."
        )
        return

    expected_title = config_policy.get("pull_request_title_pattern")
    if isinstance(expected_title, str):
        actual_title = config.get("pull-request-title-pattern")
        if actual_title != expected_title:
            errors.append(
                f"{config_path}: pull-request-title-pattern must be '{expected_title}'."
            )

    sections = package_cfg.get("changelog-sections")
    if not isinstance(sections, list):
        errors.append(f"{config_path}: changelog-sections must be an array.")
        return

    if config_policy.get("require_full_changelog_types") is not True:
        errors.append("release_please_config.require_full_changelog_types must be true.")

    if package_cfg.get("release-type") != "node":
        errors.append(f"{config_path}: packages['.'].release-type must be 'node'.")

    extra_files = package_cfg.get("extra-files")
    if extra_files is not None:
        if not isinstance(extra_files, list):
            errors.append(f"{config_path}: packages['.'].extra-files must be an array when present.")
        elif "VERSION" in extra_files:
            errors.append(
                f"{config_path}: plain VERSION must be synchronized by the release workflow, not packages['.'].extra-files."
            )

    seen_types: list[str] = []
    for idx, section in enumerate(sections):
        if not isinstance(section, dict):
            errors.append(
                f"{config_path}: changelog-sections[{idx}] must be an object."
            )
            continue
        section_type = section.get("type")
        if isinstance(section_type, str):
            seen_types.append(section_type)
        if section.get("hidden") is True:
            section_type = section.get("type", f"index {idx}")
            errors.append(
                f"{config_path}: changelog section '{section_type}' must not be hidden."
            )

    required_types = config_policy.get("required_changelog_types", [])
    if not isinstance(required_types, list) or not required_types:
        errors.append("release_please_config.required_changelog_types must be a non-empty array.")
        required_types = []
    elif any(not isinstance(commit_type, str) or not commit_type.strip() for commit_type in required_types):
        errors.append("release_please_config.required_changelog_types entries must be non-empty strings.")

    missing_types = [
        commit_type
        for commit_type in required_types
        if isinstance(commit_type, str) and commit_type not in seen_types
    ]
    if missing_types:
        errors.append(
            f"{config_path}: changelog-sections is missing types: {', '.join(missing_types)}."
        )

    duplicate_types = sorted(
        {commit_type for commit_type in seen_types if seen_types.count(commit_type) > 1}
    )
    if duplicate_types:
        errors.append(
            f"{config_path}: changelog-sections contains duplicate types: {', '.join(duplicate_types)}."
        )


def main() -> None:
    policy_path, project_root = parse_args()
    policy = load_json(policy_path)

    errors: list[str] = []
    validate_repository_settings(policy, project_root, errors)
    validate_workflow(policy, project_root, errors)
    validate_release_pr_policy(policy, errors)
    validate_release_config(policy, project_root, errors)

    if errors:
        print("ERROR: release-please policy validation failed.", file=sys.stderr)
        for err in errors:
            print(f"- {err}", file=sys.stderr)
        raise SystemExit(1)

    print("OK: release-please policy checks passed.")


if __name__ == "__main__":
    main()
