## Context

Second implementation fixer pass after the r2 review batch. Apply only the accepted findings from the r2 reports and related tracker rows. Do not re-open declined findings unless the assigned change invalidates the decline rationale.

## Working directory + branch

`/Users/piercarlocadoppi/Documents/open-source/github/cad0p/ghostty-zmx`

Branch: `feat/v0.1`, continue from current HEAD. Push each commit to the existing draft PR branch.

## Reviews to read for citations

Read the r2 reports under:

`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-1-impl/r2-*.md`

Do not read prior review reports unless a cited r2 report explicitly references a prior finding.

## Scope and commits

### Commit 1: make scrollback snapshots and fresh-session detection failure-safe

Finding rows: correctness snapshot pipeline failure, fresh-session detection failure, scrollback line validation.

Required changes:

- Make snapshot helpers write `zmx history` output to a temp file and check `zmx history` exit status before truncating/moving the snapshot into place.
- Treat `zmx list --short` failure distinctly from “session absent”; log and skip injection on failure.
- Validate `GHOSTTY_ZMX_SCROLLBACK_LINES` as a positive integer, defaulting to `1000` and logging fallback on invalid input.
- Mirror the safe snapshot behavior in the generated reaper.

Suggested commit subject: `fix: make scrollback snapshotting failure-safe`

### Commit 2: harden restore lock and physical id-map boundaries

Finding rows: restore lock race, physical id-map regex filtering, session-name hex tightening.

Required changes:

- Keep the restore lock for a duration derived from the number of sessions and `GHOSTTY_ZMX_RESTORE_STEP_DELAY`, plus a conservative AppleScript margin, instead of a fixed 5 seconds.
- Validate physical window/tab IDs before `_ghostty_zmx_write_id_map` filters or writes.
- Tighten managed session validation to the canonical hex-like session shape from the design.

Suggested commit subject: `fix: harden restore locking and id-map writes`

### Commit 3: guard installer migration edge cases

Finding rows: unterminated experimental `.zshrc` block handling, installer migration edge coverage, interactive install acceptance.

Required changes:

- Abort installation when an unterminated experimental `.zshrc` block is detected; do not append the new source line after that failure.
- Add tests for unterminated experimental blocks, existing ghostty-zmx sessions file, stale runtime flag cleanup, and interactive install acceptance.
- Keep the documented experimental migration behavior for exact `confirm-close-surface = false`, but make the plan/test coverage explicit.

Suggested commit subject: `fix: harden installer migration handling`

### Commit 4: harden reaper PID-reuse behavior and runtime cleanup

Finding rows: reaper PID reuse, uninstaller runtime dir cleanup.

Required changes:

- Pass the detected Ghostty elapsed time to the reaper and stop cleanup if the PID appears reused; on shutdown, snapshot preserved sessions and exit without zero-window cleanup.
- Teach uninstall to remove the current per-user runtime directory only after validating it is the expected owned `ghostty-zmx-${UID}` directory and not a symlink/parent.

Suggested commit subject: `fix: guard reaper shutdown and runtime cleanup`

### Commit 5: add remaining executable coverage and release-control smoke

Finding rows: release/reaper fixture gap, uninstall interactive coverage, release-control validation.

Required changes:

- Add executable tests for interactive uninstall decline/acceptance and release-control metadata/workflow shape.
- Add whatever practical fixture coverage is feasible for restore grouping/id-map behavior or reaper decision parsing without requiring live Ghostty.
- Do not over-engineer fake daemons; small deterministic shell fixtures are sufficient.

Suggested commit subject: `test: add remaining shell coverage`

### Commit 6: documentation cleanup for runtime layout and API surface

Finding rows: runtime layout documentation, uninstall `--yes` behavior, helper namespace cleanup if straightforward.

Required changes:

- Document the internal per-user runtime directory and uninstall cleanup behavior.
- Clarify `--yes` behavior for Ghostty config removal.
- If easy, reduce private helper namespace leakage; otherwise leave helpers as private implementation details and document that they are not stable APIs.

Suggested commit subject: `docs: document private runtime layout`

## Declined findings to preserve

Do not spend time changing the `.zshrc` source-line quote form unless you find byte evidence of literal backslashes in the current branch; r2 cleanness re-flagged this, but current bytes contain normal quotes.

## Exit criteria

- All assigned high/medium findings have fixes or explicit report notes.
- `zsh -n session-manager.zsh install.sh uninstall.sh tests/*.zsh` passes.
- `tests/install-uninstall.zsh`, `tests/snapshot-scrollback.zsh`, and any new tests pass.
- `jq . package.json` passes.
- Commits are pushed after each commit.
