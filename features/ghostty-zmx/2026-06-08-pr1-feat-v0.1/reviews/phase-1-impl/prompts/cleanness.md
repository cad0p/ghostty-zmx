# Canonical spec

`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/design.md` — read in full.

# Lens: cleanness / API surface

Review the implementation for clarity, maintainability, public surface shape, naming consistency, duplication, dead/speculative code, shell style, file layout, and documentation/API alignment. Treat this as pre-v1 API hygiene for a zsh-only package.

Scrutinize especially:

- Whether installer/uninstall flags and environment variables are coherent and minimal.
- Whether public file locations and names match the README and design.
- Whether helper functions are named consistently and avoid stale experimental naming.
- Whether runtime paths, constants, and magic numbers are named/rationalized.
- Whether README/docs overclaim or duplicate too much implementation detail.
- Whether release-control docs are clear without promising npm publishing.
- Whether shell scripts are easy to audit and avoid unnecessary complexity.

# Deliverable

Write a structured report to the output path specified by the orchestrator.

Use this shape:

```md
## Findings

### <ID> (<severity>) — <title>
**Where:** <file>:<line>
**What:** <description>
**Recommendation:** <concrete fix, defer, or decline suggestion>

## Well-maintained areas

## Summary
```

Findings must cite file:line for every block/high/medium. Include low/nit findings if useful.

# Output-shape constraints

Do not read other review reports. Do not make patches or commits. Do not decide phase status. Your report is input for orchestrator triage.

Avoid orchestration-internal vocabulary in your report except simple local finding IDs in the report itself.

# Useful commands

```sh
git diff --stat main..HEAD
git diff main..HEAD -- session-manager.zsh install.sh uninstall.sh README.md docs/manual-e2e.md .github/workflows/release.yml package.json RELEASE.md
grep -R "ZMX_AUTO_ATTACH\|~/.local/share/zmx\|/tmp/zmx-" -n . --exclude-dir=.git
```
