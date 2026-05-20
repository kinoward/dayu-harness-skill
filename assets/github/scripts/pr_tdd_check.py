#!/usr/bin/env python3
"""Validate PR changes with a configurable TDD policy.

The checker inspects implementation/test path matching and commit-order constraints.
It is designed for GitHub Actions as well as local unit tests.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

def die(msg: str) -> None:
    """Print error and exit with failure."""
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def run_git(repo_root: Path, args: list[str]) -> str:
    """Run git command and return stdout."""
    completed = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        die(
            f"git command failed: git {' '.join(args)}\n"
            f"stderr: {completed.stderr.strip()}"
        )
    return completed.stdout


def load_json_file(path: Path) -> object:
    """Load a JSON file."""
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        die(f"Cannot read policy/input file '{path}': {exc}")
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        die(f"Invalid JSON in '{path}': {exc}")


@dataclass
class Policy:
    impl_patterns: list[re.Pattern]
    test_patterns: list[re.Pattern]
    exempt_patterns: list[re.Pattern]


def parse_pattern_list(data: object, key: str) -> list[re.Pattern]:
    """Parse one pattern list and compile regex patterns."""
    if not isinstance(data, dict):
        die(f"Policy must be an object, got {type(data).__name__} for {key}.")
    raw = data.get(key)
    if raw is None:
        return []
    if not isinstance(raw, list):
        die(f"Policy field '{key}' must be an array, got {type(raw).__name__}.")
    patterns: list[re.Pattern] = []
    for item in raw:
        if not isinstance(item, str):
            die(f"Policy field '{key}' must contain strings; invalid item: {item!r}")
        try:
            patterns.append(re.compile(item))
        except re.error as exc:
            die(f"Invalid regex in '{key}': {item!r}: {exc}")
    return patterns


def parse_policy(path: Path) -> Policy:
    """Load policy JSON and compile regex fields."""
    raw_policy = load_json_file(path)
    impl_patterns = parse_pattern_list(raw_policy, "impl_patterns")
    test_patterns = parse_pattern_list(raw_policy, "test_patterns")
    exempt_patterns = parse_pattern_list(raw_policy, "exempt_patterns")
    return Policy(impl_patterns, test_patterns, exempt_patterns)


def matches_any(path: str, patterns: list[re.Pattern]) -> bool:
    """Check if any regex matches path."""
    for pattern in patterns:
        if pattern.search(path):
            return True
    return False


@dataclass
class CommitInfo:
    sha: str
    subject: str
    committed_at: int
    files: list[str]


def _normalize_file_entry(value: object) -> str | None:
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, dict):
        for key in ("filename", "path", "name"):
            entry = value.get(key)
            if isinstance(entry, str):
                return entry.strip()
    return None


def _normalize_timestamp(raw: object) -> int:
    if isinstance(raw, int):
        return raw
    if isinstance(raw, float):
        return int(raw)
    if isinstance(raw, str) and raw.isdigit():
        return int(raw)
    return 0


def parse_commits_from_json(path: Path) -> list[CommitInfo]:
    """Load commit simulation data from JSON."""
    raw = load_json_file(path)
    if not isinstance(raw, list):
        die(f"Simulated commits JSON must be an array: {path}")
    commits: list[CommitInfo] = []
    for idx, item in enumerate(raw):
        if not isinstance(item, dict):
            die(f"Commit entry #{idx} must be an object.")
        sha = (item.get("sha") or "").strip() if isinstance(item.get("sha"), str) else ""
        if not sha:
            die(f"Commit entry #{idx} missing 'sha'.")
        subject = str(item.get("subject", "") or item.get("message", "")).strip()
        committed_at = _normalize_timestamp(
            item.get("committed_at") or item.get("timestamp") or item.get("committed_date")
        )
        if committed_at == 0:
            committed_at = _normalize_timestamp(item.get("committedAt"))

        if committed_at == 0:
            # keep deterministic order only, fallback to 0 for unsupported values.
            committed_at = 0

        raw_files = item.get("files", item.get("changed_files", []))
        if not isinstance(raw_files, list):
            die(f"Commit entry '{sha}' field 'files' must be an array.")
        files = [value for value in (_normalize_file_entry(f) for f in raw_files) if value]
        commits.append(
            CommitInfo(
                sha=sha,
                subject=subject,
                committed_at=committed_at,
                files=files,
            )
        )
    return commits


def parse_commits_from_git(repo_root: Path, base_ref: str, head_ref: str) -> list[CommitInfo]:
    """Build commit list with changed files from git log + git show."""
    range_expr = f"{base_ref}..{head_ref}"
    # oldest -> newest
    log_output = run_git(
        repo_root,
        [
            "log",
            "--reverse",
            "--no-merges",
            "--format=%H%x01%s%x01%ct",
            range_expr,
        ],
    ).splitlines()

    commits: list[CommitInfo] = []
    for line in log_output:
        parts = line.split("\x01")
        if len(parts) < 3:
            continue
        sha, subject, epoch_str = parts[0], parts[1], parts[2]
        try:
            committed_at = int(epoch_str)
        except ValueError:
            committed_at = 0

        show_output = run_git(
            repo_root,
            ["show", "--pretty=format:", "--name-status", "--no-renames", sha],
        ).splitlines()
        files: list[str] = []
        for row in show_output:
            row = row.strip()
            if not row:
                continue
            cells = row.split("\t")
            if len(cells) == 2:
                _status, path = cells
                files.append(path.strip())
            elif len(cells) >= 3 and cells[0].startswith("R"):
                files.append(cells[2].strip())
            elif len(cells) > 3 and cells[0].startswith("C"):
                files.append(cells[-1].strip())
            elif len(cells) >= 2:
                files.append(cells[1].strip())
        commits.append(
            CommitInfo(
                sha=sha,
                subject=subject.strip(),
                committed_at=committed_at,
                files=files,
            )
        )

    return commits


def parse_files_from_json(path: Path) -> list[str]:
    """Load changed paths from simulated files JSON."""
    raw = load_json_file(path)
    if isinstance(raw, dict) and "files" in raw:
        raw = raw["files"]
    if not isinstance(raw, list):
        die(f"Simulated files JSON must be an array: {path}")

    files: list[str] = []
    for item in raw:
        entry = _normalize_file_entry(item)
        if entry:
            files.append(entry)
    return files


def collect_files_from_git(repo_root: Path, base_ref: str, head_ref: str) -> list[str]:
    """Collect all changed files from git diff as a fallback."""
    range_expr = f"{base_ref}..{head_ref}"
    output = run_git(
        repo_root,
        ["diff", "--name-only", "--diff-filter=ACMRD", range_expr],
    ).splitlines()
    return [line.strip() for line in output if line.strip()]


def infer_base_head(args: argparse.Namespace) -> tuple[str, str] | None:
    """Resolve base and head refs from args or common CI env."""
    if args.base and args.head:
        return (args.base.strip(), args.head.strip())

    env_base = os.getenv("PR_TDD_BASE")
    env_head = os.getenv("PR_TDD_HEAD")
    if env_base and env_head:
        return (env_base.strip(), env_head.strip())

    # GitHub event payload fallback for pull_request contexts.
    event_path = os.getenv("GITHUB_EVENT_PATH")
    if event_path:
        try:
            payload_raw = json.loads(Path(event_path).read_text(encoding="utf-8"))
            pr_obj = payload_raw.get("pull_request", {}) if isinstance(payload_raw, dict) else {}
            base = pr_obj.get("base", {}).get("sha") if isinstance(pr_obj.get("base"), dict) else None
            head = pr_obj.get("head", {}).get("sha") if isinstance(pr_obj.get("head"), dict) else None
            if isinstance(base, str) and isinstance(head, str):
                return (base.strip(), head.strip())
        except (OSError, json.JSONDecodeError):
            pass

    return None


def classify_file(
    path: str, policy: Policy
) -> tuple[bool, bool]:
    """Return (is_impl, is_test) after exempt handling."""
    if matches_any(path, policy.exempt_patterns):
        return False, False
    is_impl = matches_any(path, policy.impl_patterns)
    is_test = matches_any(path, policy.test_patterns)
    return is_impl, is_test


def evaluate(
    policy: Policy,
    repo_root: Path,
    base_ref: str,
    head_ref: str,
    commit_records: list[CommitInfo],
    changed_files: list[str],
) -> None:
    """Run the TDD checks and print status."""
    if not policy.impl_patterns or not policy.test_patterns:
        print(
            "SKIP: Policy lacks impl_patterns/test_patterns; "
            "no TDD enforceable scope configured."
        )
        return

    impl_paths: list[str] = []
    test_paths: list[str] = []
    for path in changed_files:
        is_impl, is_test = classify_file(path, policy)
        if is_impl:
            impl_paths.append(path)
        if is_test:
            test_paths.append(path)

    if not impl_paths:
        print("OK: No implementation-path changes matched policy; gate passed.")
        return

    if not test_paths:
        die(
            "TDD policy failed: implementation-path files were changed but no "
            f"test-pattern files were changed. impl={len(impl_paths)}, test={len(test_paths)}.\n"
            f"Matched impl paths: {', '.join(impl_paths)}"
        )

    if not commit_records:
        # Keep rule informative instead of silently passing when order is not inferable.
        die(
            "TDD policy failed: cannot evaluate commit order because no commit data was "
            "provided or base/head diff range was empty."
        )

    first_impl_idx = None
    first_test_idx = None
    for index, record in enumerate(commit_records):
        impl_in_commit = False
        test_in_commit = False
        for path in record.files:
            is_impl, is_test = classify_file(path, policy)
            if is_impl:
                impl_in_commit = True
            if is_test:
                test_in_commit = True

        if first_impl_idx is None and impl_in_commit:
            first_impl_idx = index
        if first_test_idx is None and test_in_commit:
            first_test_idx = index
        if first_impl_idx is not None and first_test_idx is not None:
            break

    if first_impl_idx is None:
        # Defensive; should not happen because we have impl_paths but maybe empty file metadata.
        die("TDD policy failed: cannot map implementation changes back to commit entries.")

    if first_test_idx is None:
        die(
            "TDD policy failed: no test-pattern commits were found in commit history. "
            f"Need at least one test commit not later than the first implementation commit ({first_impl_idx})."
        )

    if first_test_idx > first_impl_idx:
        first_impl = commit_records[first_impl_idx]
        first_test = commit_records[first_test_idx]
        die(
            "TDD policy failed: first test commit is later than first implementation commit.\n"
            f"first implementation commit: {first_impl.sha[:7]} - {first_impl.subject}\n"
            f"first test commit: {first_test.sha[:7]} - {first_test.subject}"
        )

    print(
        "OK: TDD policy passed. implementation changes are paired with tests and "
        f"test commit is not later than first implementation commit (impl={len(impl_paths)}, test={len(test_paths)})."
    )
    if repo_root and base_ref and head_ref:
        print(f"Checked changes between {base_ref}..{head_ref} in {repo_root}.")


def resolve_inputs(
    args: argparse.Namespace,
) -> tuple[Path, Policy, Path, str | None, str | None, list[CommitInfo], list[str]]:
    """Resolve policy, repository root, refs, and simulation overrides."""
    policy_path = Path(args.policy_path)
    if not policy_path.exists():
        die(f"Policy file not found: {policy_path}")

    policy = parse_policy(policy_path)

    repo_root = Path(args.repo_root or os.getenv("PR_TDD_REPO_ROOT", ".")).resolve()
    commit_records: list[CommitInfo] = []
    changed_files: list[str] = []
    base_ref: str | None = args.base or os.getenv("PR_TDD_BASE")
    head_ref: str | None = args.head or os.getenv("PR_TDD_HEAD")

    if not policy.impl_patterns or not policy.test_patterns:
        return policy_path, policy, repo_root, None, None, [], []

    if args.files_json or os.getenv("PR_TDD_FILES_JSON"):
        files_json_path = Path(args.files_json or os.getenv("PR_TDD_FILES_JSON", ""))
        changed_files = parse_files_from_json(files_json_path)
    if args.commits_json or os.getenv("PR_TDD_COMMITS_JSON"):
        commits_json_path = Path(args.commits_json or os.getenv("PR_TDD_COMMITS_JSON", ""))
        commit_records = parse_commits_from_json(commits_json_path)
    elif base_ref and head_ref and repo_root.exists():
        commit_records = parse_commits_from_git(repo_root, base_ref, head_ref)

    if not commit_records and not changed_files and base_ref and head_ref and repo_root.exists():
        # no commit-level data; fallback to file-level diff for content-based checks
        changed_files = collect_files_from_git(repo_root, base_ref, head_ref)

    if not changed_files:
        # final fallback from commit records, if any
        changed_files = [path for record in commit_records for path in record.files]
        # deduplicate while preserving order
        changed_files = [f for i, f in enumerate(changed_files) if f not in changed_files[:i]]

    inferred = infer_base_head(args)
    if not base_ref and not head_ref and inferred:
        base_ref, head_ref = inferred
        if not commit_records:
            commit_records = parse_commits_from_git(repo_root, base_ref, head_ref)
        if not changed_files:
            changed_files = collect_files_from_git(repo_root, base_ref, head_ref)

    if not base_ref and not head_ref and not commit_records:
        print("SKIP: No base/head refs or commit simulation input found; only policy scope checks are available.")

    return policy_path, policy, repo_root, base_ref, head_ref, commit_records, changed_files


def build_arg_parser() -> argparse.ArgumentParser:
    """Build CLI parser."""
    parser = argparse.ArgumentParser(
        description="Validate PR file/commit changes using a configurable TDD policy JSON."
    )
    parser.add_argument(
        "policy_path",
        help="Path to policy JSON, e.g. .github/dayu-harness/pr-tdd-policy.json",
    )
    parser.add_argument(
        "--base",
        help="Base ref/sha used for git range checks (usually PR base sha).",
    )
    parser.add_argument(
        "--head",
        help="Head ref/sha used for git range checks (usually PR head sha).",
    )
    parser.add_argument(
        "--repo-root",
        default=".",
        help="Repository root for git operations (default: .)",
    )
    parser.add_argument(
        "--files-json",
        help="Optional JSON file describing changed files, for local simulation or tests.",
    )
    parser.add_argument(
        "--commits-json",
        help="Optional JSON file describing commit records (sha/subject/files), for local simulation or tests.",
    )
    parser.add_argument(
        "--validate-policy-only",
        action="store_true",
        help="Validate and compile the policy only; skip files/commits/git checks.",
    )
    return parser


def main() -> None:
    """CLI entrypoint."""
    args = build_arg_parser().parse_args()
    if args.validate_policy_only:
        parse_policy(Path(args.policy_path))
        print("OK: TDD policy file is valid (policy-only mode).")
        return

    policy_path, policy, repo_root, base_ref, head_ref, commit_records, changed_files = resolve_inputs(args)

    if not repo_root.is_dir():
        die(f"repo-root is not a directory: {repo_root}")

    evaluate(policy, repo_root, base_ref or "", head_ref or "", commit_records, changed_files)


if __name__ == "__main__":
    main()
