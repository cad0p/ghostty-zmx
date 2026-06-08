## Findings

### R3-CLEAN-C1 (medium) — Sourced manager exposes a broad private helper surface
**Where:** `session-manager.zsh`:21-167, 433-849
**What:** Sourcing `session-manager.zsh` defines many `_ghostty_zmx_*` helpers and runtime state in the user's interactive shell. The README correctly calls these private implementation details, but the file only unfunctions `_ghostty_zmx_auto_attach` at the end. That leaves a large private namespace visible and callable by users or later config snippets.
**Recommendation:** For v0.1, either unfunction all private helpers after startup, or gate helper exposure behind an explicit test/source mode and keep normal installation to the auto-attach entrypoint. Keep only documented environment variables as the public surface.

### R3-CLEAN-C2 (medium) — Generated reaper duplicates core logic and uses unprefixed names
**Where:** `session-manager.zsh`:184-400
**What:** The reaper is generated as a large heredoc that duplicates validation, debug logging, session-list parsing, snapshotting, and cleanup logic already present in the sourced manager. Inside the generated script it uses unprefixed function names such as `valid_session_name`, `snapshot_history`, and `managed_detached_sessions`, making drift and audit harder.
**Recommendation:** Centralize reaper behavior in one internal implementation path, preferably with prefixed helper names, or generate a standalone internal reaper script that is clearly separated from the sourced manager. Avoid maintaining two copies of the same lifecycle logic.

### R3-CLEAN-C3 (medium) — Installer migration silently widens Ghostty config ownership
**Where:** `install.sh`:106-117, 181-185; `README.md`:74-76
**What:** The migration helper removes any exact `confirm-close-surface = false` line outside the managed block, while the README and install plan describe removal only for the known experimental line and otherwise warn about conflicts outside the managed section. This makes the installer's config-edit boundary less predictable than the documented API.
**Recommendation:** Narrow automatic removal to the documented experimental migration context, or explicitly document and prompt before removing a user-controlled `confirm-close-surface = false`. Add a fixture covering a non-experimental user `confirm-close-surface = false` if the broader behavior is intended.

### R3-CLEAN-C4 (medium) — Test-only Ghostty config override remains part of the production environment surface
**Where:** `install.sh`:23-25; `uninstall.sh`:23-27; `README.md`:108
**What:** `GHOSTTY_ZMX_GHOSTTY_CONFIG` is useful for temp-HOME tests, but it is implemented as a normal environment override in both install and uninstall and is listed in the README. It is not part of the canonical runtime configuration list and can silently redirect production edits if accidentally set.
**Recommendation:** Rename it to something clearly test-scoped, such as `GHOSTTY_ZMX_TEST_GHOSTTY_CONFIG`, or require an explicit test/debug mode before honoring it. Keep the README language strictly under advanced test harnesses.

### R3-CLEAN-C5 (medium) — Restore/layout logic is intermixed and has a nested helper seam
**Where:** `session-manager.zsh`:540-600, 602-769
**What:** Restore grouping, restore-file writing, id-map writes, and AppleScript window/tab/split creation are all in one large function. It also defines the nested helper `_ghostty_zmx_restore_ids_valid`, which becomes part of the global function namespace. This makes the restore path harder to audit than the design's simple serial algorithm implies.
**Recommendation:** Extract small prefixed helpers for parsing session names, grouping by window/tab, writing restore files, validating physical IDs, and creating each Ghostty surface. Keep the top-level restore driver as the serial orchestrator only.

### R3-CLEAN-C6 (low) — Unused restore cleanup constant leaks into tests
**Where:** `session-manager.zsh`:17; `tests/restore-id-map.zsh`:49
**What:** `_ghostty_zmx_restore_flag_cleanup_delay` is set but not referenced by the current implementation, and the restore test sets it to zero. This looks like stale cleanup plumbing and adds noise to the internal API.
**Recommendation:** Remove the unused constant and the test assignment unless restore-lock cleanup timing is restored as a real seam.

### R3-CLEAN-C7 (low) — Uninstaller leaves the installer-added `.zshrc` comment
**Where:** `install.sh`:98-101; `uninstall.sh`:94-100
**What:** The installer adds a `# ghostty-zmx` comment before the guarded source line, but uninstall only removes the exact source line. A clean uninstall leaves an orphaned section header behind.
**Recommendation:** Either make uninstall remove the installer-added comment as well, or stop adding the comment and keep the source line self-contained.

### R3-CLEAN-C8 (low) — Ghostty conflict warnings are noisy for unrelated `env` lines
**Where:** `install.sh`:119-136; `README.md`:56
**What:** The conflict warning loop treats any `env =` line outside the managed block as a ghostty-zmx conflict. That will warn on unrelated Ghostty environment settings and may obscure the actual `GHOSTTY_ZMX_AUTO_ATTACH` conflict the user needs to inspect.
**Recommendation:** Warn specifically for `env = GHOSTTY_ZMX_AUTO_ATTACH=...` conflicts, or clarify the README that any `env` line can affect Ghostty's environment and may need review.

## Well-maintained areas

- The install/uninstall CLI is now coherent and minimal: `--yes` is non-interactive, destructive data/state/install-dir removal requires explicit flags, and uninstall leaves zmx sessions alive by default.
- Runtime state moved from predictable `/tmp/ghostty-zmx-*` files into a documented per-user runtime directory with unsafe-path guards in uninstall.
- README, install plan, and manual E2E docs align with the design on required Ghostty config, migration behavior, reboot scrollback injection, and unmanaged-session preservation.
- Scrollback handling has a clear public limit via `GHOSTTY_ZMX_SCROLLBACK_LINES`, validates invalid values, and avoids logging saved terminal history content.
- Lightweight tests cover installer/uninstaller idempotency and migration, restore id-map behavior, scrollback snapshot/injection seams, and release-control metadata.

## Summary

The current diff is much cleaner than a raw shell integration: docs, installer behavior, uninstall safety, runtime paths, and scrollback seams are mostly aligned with the v0.1 design. The remaining cleanness/API-surface issues are mostly about private implementation leaking into the sourced shell namespace, duplicated reaper logic, test-only environment overrides looking like production knobs, and installer config ownership being slightly broader than documented.
