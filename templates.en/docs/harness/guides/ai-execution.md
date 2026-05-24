# AI Execution Protocol

> Trigger: read before starting or continuing any AI-led implementation task. Defines human/AI responsibilities, long-task execution style, auto-fix behavior, and reporting requirements.

## 1. Product and Technical Boundaries

The user owns product direction, UX, and business trade-offs. AI owns technical approach, implementation, validation, and documentation updates within those constraints.

Human confirmation required for:
- user journey design and UI presentation
- product scope boundaries and user-facing trade-offs
- decisions that change usage patterns, data risk, or release strategy

AI may decide independently:
- API contracts, architecture patterns, caching, and error-handling strategy
- test organization, validation commands, implementation breakdown, and retry strategy
- draft content for ADRs, troubleshooting records, and research notes

## 2. Autonomous Execution of Longer Tasks

Once a plan is approved, execute implementation, testing, documentation, and commit/PR flow end-to-end without pausing before every mechanical step.

Execution requirements:
- Run independent tasks in parallel; execute dependent tasks in dependency order
- Keep output evidence for long-running commands; inspect raw errors first before deciding
- Send short progress updates at each stage boundary
- Pause for user input only when there is a product decision, permission gap, or issue that cannot be auto-repaired

## 3. Auto-Fix and Retries

When automation fails for resolvable reasons, diagnose and retry proactively.

Commit rejected by hook:
1. Read hook output and locate the violation
2. Fix commit message format or issue trailer placement
3. Re-run commit

PR or CI rejected:
1. Read failure logs and locate checks
2. Fix PR title/body/test plan or formatting
3. Push again or update PR to re-run checks

General rules:
- If the same error fails after 2 retries, report to user with remediation attempts made
- Retries must be accompanied by substantive changes; do not blindly rerun identical commands
- Network errors may be retried directly; report to user after 3 consecutive failures

## 4. Test Plan Execution

After creating a PR, execute and report each item under `## Test plan`. A test plan is an execution checklist, not decorative text.

| Item type | Execution |
|-----------|---------|
| CI / lint check | Verify with `gh pr checks <N>` or equivalent |
| Runnable command | Execute directly and keep key output |
| GitHub render state | Use `gh api` / `gh pr view` to collect verifiable results |
| Needs post-merge check | Mark as “Requires merge” and run after merge |
| Purely visual/manual | Mark as “Needs human verification” and list check points |

When reporting, include one line per checklist item and key evidence. Do not just state “all passed”.

## 5. Review Self-Check

After each implementation segment, self-check against the review checklist. When the PR review checklist exists, it is located at `docs/harness/sensors/reviews/code-review-checklist.md`.

Common failure areas:
- resource cleanup, input validation, error handling, concurrency safety
- edge cases, sensitive data in logs, mismatch between tests and behavior

## 6. Output and Error Messages

If the tool already provides detailed errors, do not paste large logs. Add only root cause, fix action, and next step.

When explaining technical decisions, describe product-level impact instead of asking users to choose among code-level options.
