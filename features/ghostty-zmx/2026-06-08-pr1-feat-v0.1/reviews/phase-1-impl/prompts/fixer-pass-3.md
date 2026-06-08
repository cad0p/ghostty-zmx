## Context

Third implementation fixer pass after the cumulative r3 review. Apply only the accepted findings from the r3 reports. Do not re-open declined/deferred findings unless your assigned change invalidates that rationale.

## Working directory + branch

`/Users/piercarlocadoppi/Documents/open-source/github/cad0p/ghostty-zmx`

Branch: `feat/v0.1`, continue from current HEAD. Push each commit to the existing draft PR branch.

## Reviews to read for citations

Read the cumulative reports under:

`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-1-impl/r3-cumulative-*.md`

## Scope and commits

### Commit 1: fix AppleScript ID parsing and legacy migration path

Finding rows: cumulative correctness AppleScript ID extraction, legacy migration path handling.

Required changes:

- Parse Ghostty AppleScript IDs by extracting the trailing hexadecimal suffix, not by fixed character offsets.
- Add regression coverage for prefixed AppleScript IDs such as `tab-group-.../tab-...` or similar prefixed strings.
- Migrate experimental sessions from the canonical legacy path `~/.local/share/zmx/sessions`; if `XDG_DATA_HOME` points elsewhere, also support that legacy path when it differs.

Suggested commit subject: `fix: parse AppleScript IDs and legacy paths`

### Commit 2: narrow Ghostty config migration scope

Finding rows: cumulative correctness over-removal, cumulative security non-managed config mutation, cumulative cleanness installer config scope mismatch.

Required changes:

- Remove `confirm-close-surface = false` only when it is part of the known experimental migration context, e.g. when the config also contains `env = ZMX_AUTO_ATTACH=1`.
- Leave user-controlled `confirm-close-surface = false` outside that context untouched and warn.
- Add regression fixtures for user-controlled false and `quit-after-last-window-closed = true`.

Suggested commit subject: `fix: narrow Ghostty config migration`

### Commit 3: harden install/uninstall file boundaries

Finding rows: cumulative security symlink delete targets, symlinked install directory, backup collisions, atomic edit failures, broad tmp cleanup where practical.

Required changes:

- Refuse symlink targets for install/data/state deletion.
- Refuse a symlinked install directory before writing.
- Make backup filenames unique within the same second.
- Check atomic edit command status before moving temp files into place.
- Improve runtime cleanup to avoid unsafe broad deletion where practical, or add tests for decoy/symlink paths.

Suggested commit subject: `fix: harden file boundary edits`

### Commit 4: cleanup public surface and nits

Finding rows: cumulative cleanness test-only config override, unused restore constant, orphan uninstall comment, noisy env warnings.

Required changes:

- Rename `GHOSTTY_ZMX_GHOSTTY_CONFIG` to `GHOSTTY_ZMX_TEST_GHOSTTY_CONFIG` or otherwise make it clearly test-scoped; update tests/docs.
- Remove unused `_ghostty_zmx_restore_flag_cleanup_delay`.
- Make uninstall remove the installer-added `# ghostty-zmx` comment.
- Narrow env conflict warnings to `GHOSTTY_ZMX_AUTO_ATTACH`/`ZMX_AUTO_ATTACH` rather than any `env =` line.

Suggested commit subject: `fix: tidy installer surface and cleanup`

## Decline/defer without code

Do not attempt to fully centralize the generated reaper or remove all private helper functions in this pass; those are larger refactor items. Do not pin the release action to SHA in this pass because the user explicitly requested using `cad0p/semver-calver-release/release@v1` and that policy is deferred.

## Exit criteria

- `zsh -n session-manager.zsh install.sh uninstall.sh tests/*.zsh` passes.
- `zsh tests/install-uninstall.zsh`, `zsh tests/snapshot-scrollback.zsh`, `zsh tests/restore-id-map.zsh`, and `zsh tests/release-control.zsh` pass.
- `jq . package.json` passes.
- Commits are pushed after each commit.
