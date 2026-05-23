#!/usr/bin/env python3
"""Validate that a GitHub issue body has a valid single-line Depends-on trailer."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


DEPENDS_ON_RE = re.compile(r"^Depends on: #\d+(?:, #\d+)*\s*$")
DEPENDS_ON_LIKE_RE = re.compile(r"^(?:[-*]\s*)?Depends on\b", re.IGNORECASE)


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def load_event_payload(path: str) -> dict:
    try:
        raw = Path(path).read_text(encoding="utf-8")
    except OSError as exc:
        die(f"Cannot read GitHub event payload '{path}': {exc}")
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        die(f"Invalid JSON in '{path}': {exc}")
    if not isinstance(payload, dict):
        die(f"Expected event payload object, got {type(payload).__name__}")
    return payload


def main() -> None:
    if len(sys.argv) != 2:
        die("Usage: issue_depends_on.py <GITHUB_EVENT_PATH>")

    payload = load_event_payload(sys.argv[1])
    issue = payload.get("issue")
    if not isinstance(issue, dict):
        die("Event payload missing 'issue' object.")

    body = (issue.get("body") or "").splitlines()
    candidate_lines = [
        line.strip()
        for line in body
        if DEPENDS_ON_LIKE_RE.match(line.strip())
    ]

    if not candidate_lines:
        print("OK: Issue has no depends-on line; dependency lint skipped.")
        return

    if len(candidate_lines) != 1:
        die(
            "Issue body may contain at most one `Depends on: #N[, #M]*` line."
        )

    line = candidate_lines[0]
    if not DEPENDS_ON_RE.fullmatch(line):
        die(
            "Invalid issue dependency format. Use strict single line: `Depends on: #N[, #M]*`."
        )

    print("OK: Issue depends-on line is valid.")


if __name__ == "__main__":
    main()
