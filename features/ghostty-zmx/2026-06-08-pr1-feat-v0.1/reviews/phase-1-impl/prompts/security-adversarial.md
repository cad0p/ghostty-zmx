# Canonical spec

`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/design.md` — read in full.

# Lens: security / adversarial

Review the implementation for trust-boundary, filesystem, subprocess, shell-injection, race, data-loss, and hostile-config risks. This package edits user shell/config files, spawns subprocesses, writes `/tmp` scripts/flags, invokes AppleScript, and runs zmx commands, so adversarial review is mandatory.

Scrutinize especially:

- Quoting and injection risks in shell scripts and generated reaper scripts.
- `/tmp` race/symlink/path risks and stale flag cleanup patterns.
- Whether installer/uninstaller can delete or overwrite unintended files.
- Whether migration handles malformed `.zshrc` or Ghostty config safely.
- Whether session names read from managed files can cause command injection or path traversal.
- Whether debug logs leak terminal history or secrets.
- Whether snapshot files are written safely and not exposed beyond expected user-local state.
- Whether reaper can accidentally kill unmanaged sessions.
- Whether release workflow permissions are minimal enough.

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
zsh -n session-manager.zsh install.sh uninstall.sh
grep -R "rm -rf\|eval\|osascript\|zmx \|cat >\|/tmp/" -n session-manager.zsh install.sh uninstall.sh .github/workflows/release.yml
```
