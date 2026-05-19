# AI Memory and Knowledge Capture Protocol

> Trigger: read when generating reusable knowledge, updating project knowledge base, consolidating session conclusions, or syncing external memory systems.

## Project Memory Authority

In the project, `AGENTS.md` and `docs/` are the single source of long-lived truth. External agent memory, LangChain/LangGraph stores, vector databases, or built-in product memory may be used for runtime retrieval and context recall, but they do not replace repository documentation.

Information from external memory systems becomes project memory only after being organized into project documentation and linked in the corresponding `AGENTS.md` index.

## Knowledge Placement

| Knowledge type | Location |
|---------|---------|
| Architecture and technical decisions | `docs/design-docs/` |
| Troubleshooting | `docs/troubleshooting/` |
| Research findings | `docs/references/research/` |
| Constraint changes | `docs/harness/guides/` + AGENTS.md |
| Project background and product context | `docs/product-specs/` |

## Capture Boundaries

Capture only distilled, reusable conclusions. Do not capture:
- complete conversation transcripts
- temporary assumptions
- unconfirmed proposals
- repeated reasoning traces
- sensitive information

Long-lived directories should hold content that later AI can use directly, including context, conclusion, applicability, validation method, and invalidation conditions.

## Generated Content Handling

AI-generated drafts, reports, or bulk-generated outputs should first land in `docs/generated/`; move them to long-term locations only after confirmation.

Outdated generated content should be deleted or moved to `docs/archive/` so later AI does not reuse stale material.
