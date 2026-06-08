# Canonical spec

`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/design.md` — read in full.

# Lens: coverage

Review whether the implementation has enough tests, checklists, fixtures, and verification seams for the behavior it implements. Focus on gaps that could allow regressions in installer migration, shell syntax, restore/reaper behavior, snapshots, reboot injection, release workflow, and documentation claims.

Scrutinize especially:

- Whether scripts are structured so important shell functions can be tested without editing real user config.
- Whether installer interactive and `--yes` paths are testable and actually documented.
- Whether migration edge cases are covered or at least clearly testable.
- Whether manual E2E scenarios are actionable and safe.
- Whether release-control behavior has an appropriate validation plan given `package.json` is not on `main` yet.
- Whether debug logging, snapshot truncation, and injection can be verified without leaking terminal history.

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

Do not read other review reports. Do not make patches or commits. Do not decide convergence. Your report is input for orchestrator triage.

Avoid orchestration-internal vocabulary in your report except simple local finding IDs in the report itself.

# Useful commands

```sh
git diff --stat main..HEAD
git diff main..HEAD -- session-manager.zsh install.sh uninstall.sh README.md docs/manual-e2e.md .github/workflows/release.yml package.json RELEASE.md
zsh -n session-manager.zsh install.sh uninstall.sh
```
