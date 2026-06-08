# Canonical spec

`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/design.md` — read in full.

# Lens: correctness

Review whether the implementation matches the locked spec. Focus on behavioral correctness, data/state semantics, session naming, restore logic, migration behavior, reaper semantics, snapshot/injection behavior, and release-control requirements.

Scrutinize especially:

- `session-manager.zsh` restore algorithm, queue handling, id-map behavior, shell quoting, zsh array behavior, AppleScript integration, and zmx command usage.
- Reaper close-vs-Cmd-Q heuristics and managed-session-only guarantees.
- Installer migration from the experimental `.zshrc`/Ghostty config state.
- `GHOSTTY_ZMX_AUTO_ATTACH` replacing the old experimental env variable.
- Snapshot deletion/preservation semantics.
- Reboot scrollback injection flow and exact banner.
- Release metadata/workflow alignment with `cad0p/semver-calver-release`.

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
jq . package.json
```
