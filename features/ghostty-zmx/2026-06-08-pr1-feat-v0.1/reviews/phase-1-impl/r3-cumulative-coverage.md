## Findings

### C1 (Medium) — Reaper lifecycle decisions are not covered by automated fixtures
**Where:** session-manager.zsh:328-397; tests/snapshot-scrollback.zsh:62-99; docs/manual-e2e.md:47-91
**What:** The generated reaper contains the important close-cleanup and Cmd-Q-preservation logic: zero-window cleanup, all-detached preservation, detached-session pending/stable handling, snapshotting, kill/unlog, and snapshot deletion. Current tests exercise snapshot truncation and reboot print/attach helpers, but not the reaper loop decisions themselves. The behavior is documented as manual E2E, but there is no fast fixture for regression-prone cases such as pane close, window close, close-all-windows, and Cmd-Q.
**Recommendation:** Add an automated reaper fixture with stubbed `zmx`, `osascript`, `ps`, and controllable timing variables. Assert pane close kills/unlogs/deletes snapshots, close-all-windows waits for the zero-window grace, Cmd-Q preserves sessions and snapshots, and unmanaged sessions remain untouched.

### C2 (Medium) — Full restore-driver and auto-attach path is under-tested
**Where:** session-manager.zsh:773-845; tests/restore-id-map.zsh:47-58
**What:** The restore-id-map test calls `_ghostty_zmx_restore` directly and verifies queue ordering and id-map writes. It does not cover the restore-driver election using the runtime lock, `restore-first` consumption, queue popping, generated non-restore session naming, id-map recording for new sessions, reaper startup, or `zmx attach` failure logging.
**Recommendation:** Add a fixture for `_ghostty_zmx_auto_attach` with stubbed `ps`, `osascript`, and `zmx`. Cover first-session restore, queued-session restore, generated-session attach, failed attach logging, and id-map recording without changing real user config.

### C3 (Medium) — Intentional-close snapshot deletion is not explicitly verified
**Where:** session-manager.zsh:351-357, 388-393; docs/manual-e2e.md:47-52, 66-73
**What:** The close-pane and close-window E2E scenarios verify that managed sessions disappear from `zmx list --short` and the sessions file, but they do not explicitly verify that the corresponding `~/.local/state/ghostty-zmx/history/<session>.txt` snapshot is deleted immediately for intentional closes.
**Recommendation:** Add manual checklist steps and automated fixtures to record the snapshot path before closing a pane/window, then assert the snapshot file is removed after reaper cleanup.

### C4 (Medium) — Migration fixtures do not cover non-experimental Ghostty config conflicts
**Where:** install.sh:106-117, 119-136; tests/install-uninstall.zsh:75-93
**What:** The migration test covers the experimental `confirm-close-surface = false` line and preservation of `window-save-state = always`, but it does not cover a user-controlled `confirm-close-surface = false` outside the managed block or `quit-after-last-window-closed = true` during migration. The installer currently strips all `confirm-close-surface = false` lines, so the intended conflict behavior is not clearly covered.
**Recommendation:** Add fixtures for user-controlled `confirm-close-surface = false` and unsupported `quit-after-last-window-closed = true`. Either narrow removal to the known experimental line/block or document and test the preserve/warn behavior for user-controlled conflicts.

### C5 (Medium) — Runtime cleanup fixtures are incomplete for unsafe migration paths
**Where:** install.sh:172-174; uninstall.sh:127-129; tests/install-uninstall.zsh:62-88, 138-152
**What:** Tests cover stale experimental `/tmp/zmx-*` files and uninstall removing the current runtime directory, including a runtime-directory symlink refusal. They do not cover unsafe stale flag paths/symlinks, nor do they verify uninstall removes generated `/tmp/ghostty-zmx-*` files. The installer cleanup hardcodes `/tmp`, which limits test isolation.
**Recommendation:** Make runtime cleanup safer and more testable, for example by avoiding broad `rm -rf` globs or adding explicit ownership/symlink checks and a test override for stale-flag roots. Add fixtures for stale-flag symlinks and uninstall cleanup of generated runtime files.

### C6 (Low) — Release workflow validation is mostly grep-based/manual
**Where:** tests/release-control.zsh:7-12; .github/workflows/release.yml:1-24; RELEASE.md:20-22
**What:** The release-control smoke test confirms the expected action, permissions, branch trigger, and deferred `validate-package-version` documentation. It does not validate workflow YAML shape with a workflow linter/schema, nor does it assert that `validate-package-version` remains absent from the workflow while deferred.
**Recommendation:** Add lightweight workflow validation, such as `actionlint`, `yq`, or explicit YAML assertions, and assert the deferred package-version validation behavior in the test.

## Well-maintained areas

- Snapshot truncation, reboot scrollback injection, banner content, and debug-log non-leakage are covered by a focused helper test: tests/snapshot-scrollback.zsh:54-99.
- Installer interactive and `--yes` paths, migration, idempotency, stale-flag cleanup, conflict warning, and uninstall preservation/deletion behavior are documented and covered by tests: README.md:22-41; tests/install-uninstall.zsh:34-164.
- Restore grouping and id-map behavior have a fixture for append-order sessions across multiple logical windows/tabs: tests/restore-id-map.zsh:41-58.
- Manual E2E scenarios are actionable and include safe orchestration guidance, production close behavior, unmanaged-session checks, reboot scrollback simulation, and the automated-test `confirm-close-surface = false` override pattern: docs/manual-e2e.md:1-147.

## Summary

The implementation has solid coverage for installer/uninstaller behavior, restore grouping/id-map writes, snapshot truncation, reboot scrollback injection, and debug-log non-leakage. The main remaining coverage gaps are the generated reaper lifecycle, full auto-attach/restore-driver flow, explicit intentional-close snapshot deletion, non-experimental migration conflicts, unsafe runtime cleanup fixtures, and automated release-workflow validation.
