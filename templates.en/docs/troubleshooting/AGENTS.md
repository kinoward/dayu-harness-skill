# docs/troubleshooting/AGENTS.md

This directory is the categorized index for the troubleshooting knowledge base. Each subdirectory maps to a troubleshooting category; each category `AGENTS.md` lists concrete entries.

## Directory Index

- [AGENTS.md](AGENTS.md) - Current index
- `<category>/` - Troubleshooting categories added by project
- `<category>/AGENTS.md` - Category index
- `<category>/<issue>.md` - Individual troubleshooting entry

Keep this section synchronized with directory/file/capability manifest changes.

## Categories

<!-- Create subdirectories as needed, for example: -->
<!-- - build-env/ — build tools, environment, language configuration issues -->
<!-- - ci-cd/ — CI/CD process issues -->
<!-- - testing/ — testing-related issues -->

## Entry Format

Each troubleshooting entry must follow this strict format. `TL;DR` must be the first section so AI and humans can assess relevance without reading the full file.

```markdown
# <Short issue description>

## TL;DR

One line with symptom + root cause + fix.

**Date**: YYYY-MM-DD
**Symptom**: <Observed behavior and concrete error message>
**Root cause**: <Underlying reason>
**Fix**: <Solution, including executable commands>
**Prevention**: <How to prevent recurrence, including optional config changes>
```

## Add New Entry

1. Create a kebab-case `.md` file under the corresponding category directory.
2. Ensure the file contains `## TL;DR` immediately after the title.
3. Update the category `AGENTS.md` with the new entry.
4. Update this file’s category list if a new subdirectory is added.
