## Context

First implementation fixer pass after the initial four-lens review. Apply only the accepted findings listed below from `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md`.

## Working directory + branch

`/Users/piercarlocadoppi/Documents/open-source/github/cad0p/ghostty-zmx`

Branch: `feat/v0.1`, continue from `fd3f705`. Push each commit to the existing draft PR branch.

## Reviews to read for citations

- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-1-impl/r1-correctness.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-1-impl/r1-security-adversarial.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-1-impl/r1-cleanness.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-1-impl/r1-coverage.md`

Do not read any future review reports.

## Scope and commits

### Commit 1: harden runtime locks, session validation, and paths

Finding rows: `SEC-S1`, `SEC-S2`, `SEC-S4`, plus related pieces of `CLEAN-C6` where constants are touched.

Required changes:

- Add strict canonical managed-session validation before using names from `sessions`, restore queue, migrated state, zmx list output, or before constructing snapshot paths and invoking destructive zmx operations.
- Use a conservative canonical shape for v0.1: `zmx-<hex-or-alnum-window>-<hex-or-alnum-tab>-<8 hex/alnum terminal chars>`; reject slashes, `..`, whitespace, tabs, and control characters.
- Skip and debug-log invalid session names rather than acting on them.
- Replace predictable direct `/tmp` reaper script/log paths with a private runtime directory created safely, with restrictive permissions. Avoid symlink clobbering. Store generated reaper script/log inside that directory or use an installed/static helper if simpler.
- Replace restore-driver `[[ ! -f ]]` + `touch` election with atomic `mkdir` locking.
- Name timing/retry constants that you touch.

Suggested commit subject: `fix: harden runtime locks and session validation`

Required checks: `zsh -n session-manager.zsh install.sh uninstall.sh`; add/run any shell tests you introduce.

### Commit 2: fix reaper preserve/cleanup semantics and coverage

Finding rows: the correctness row about Cmd-Q reaper semantics, the coverage rows about reaper/restore fixture validation and scrollback snapshot/injection validation, and snapshot-related parts of the cleanness row about timing constants.

Required changes:

- Ensure Cmd-Q-shaped shutdown preserves sessions and snapshots managed sessions for reboot recovery.
- Avoid killing newly detached sessions until the close-vs-quit heuristic has had a stable interval to distinguish single-surface/window closes from all-client detaches caused by app quit.
- Before reaper exits on Ghostty process termination, snapshot all valid managed sessions that still exist.
- Preserve snapshots for Cmd-Q-shaped detach; delete snapshots for intentional close cleanup.
- Add fixture/stub coverage for reaper decision behavior and scrollback snapshot/injection/truncation edge cases if practical. At minimum add executable shell tests for truncation, injection banner ordering, invalid/missing snapshot, and failure logging without saved history content.

Suggested commit subject: `fix: preserve sessions during app quit`

Required checks: `zsh -n session-manager.zsh install.sh uninstall.sh`; run added tests.

### Commit 3: make restore target explicit physical windows/tabs

Finding row: `CORR-C3`.

Required changes:

- Remove reliance on ambient `front window` / focused terminal during restore layout creation where possible.
- Track physical window/tab IDs captured by AppleScript creation.
- Before adding a tab or split, explicitly target/select the intended physical window/tab and verify the returned physical IDs before writing id-map.
- If AppleScript creation fails or returns mismatched IDs, debug-log a restore failure and avoid writing misleading id-map entries.

Suggested commit subject: `fix: target restored Ghostty surfaces explicitly`

Required checks: `zsh -n session-manager.zsh install.sh uninstall.sh`; any AppleScript syntax sanity checks you can run safely.

### Commit 4: make installer and uninstall migration safer and testable

Finding rows: the correctness row about experimental close-confirmation migration, the security/cleanness row about non-interactive uninstall deletion, the coverage rows about installer/migration coverage and release/install verification docs, and the cleanness row about the Ghostty config override.

Required changes:

- During migration, remove the exact known experimental `confirm-close-surface = false` line, with backup already in place. Keep warning for other conflicting values outside the managed block.
- Keep `--yes` non-destructive for data/state deletion by default. Add explicit destructive flags such as `--remove-data`, `--remove-state`, and `--remove-install-dir` for uninstall. Refuse unsafe deletion targets even with explicit flags.
- Document `GHOSTTY_ZMX_GHOSTTY_CONFIG` as an advanced/testing override if retained.
- Add temp-HOME installer/uninstaller tests or a shell test harness covering interactive decline, `--yes` install, idempotency, migration block removal, experimental env removal, experimental `confirm-close-surface = false` removal, sessions-copy behavior, conflict warnings, uninstall non-destructive default, and explicit deletion flags.
- Add docs for pre-merge verification steps including installer/release checks.

Suggested commit subject: `fix: make migration and uninstall safer`

Required checks: `zsh -n session-manager.zsh install.sh uninstall.sh`; run added installer/uninstaller tests; `jq . package.json`.

### Commit 5: localize sourced-shell runtime surface

Finding row: `CLEAN-C3`, and remaining accepted `CLEAN-C4` if cleanup is straightforward.

Required changes:

- Wrap top-level auto-attach logic in a prefixed function with local variables, call it, and unset the function if not public.
- Avoid leaking unprefixed globals such as `SESSION_NAME` and `POSITION` into user shells.
- Remove no-op or stale sourced helpers if they are truly unused after the other fixes, or keep only helpers that are part of actual runtime.

Suggested commit subject: `fix: localize sourced shell state`

Required checks: `zsh -n session-manager.zsh install.sh uninstall.sh`; run relevant tests.

## Exit criteria

- All assigned tracker rows have either fixes landed or an explicit report explaining why a row could not be safely fixed in this pass.
- Tests/checks pass after each commit.
- Commits are pushed to `origin/feat/v0.1` after each commit.

## Do not fix

- Do not change the source-line quote form unless you find actual byte evidence contradicting the tracker; the source-line finding was declined because current files contain normal quotes, not backslash characters.
- Do not pin `cad0p/semver-calver-release/release@v1` unless you first report that the user's requested release-control policy requires changing; `SEC-S5` is deferred.
