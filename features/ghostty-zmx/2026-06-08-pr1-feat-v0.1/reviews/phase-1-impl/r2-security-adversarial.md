## Findings

### SEC-S1 (medium) — Reaper can act after Ghostty PID reuse and delete preserved sessions
**Where:** `session-manager.zsh:252-308`
**What:** The reaper loop is keyed by the detected Ghostty PID and continues while `kill -0 "$ghosttyPID"` succeeds. If the original Ghostty process exits and the PID is reused before the reaper observes shutdown, the reaper can continue into the zero-window cleanup path, snapshot preserved sessions, run `zmx kill`, remove them from the managed log, and forget the snapshot. This can turn a Cmd-Q/reboot-preservation case into destructive cleanup.
**Recommendation:** Stop cleanup immediately when the original app instance exits rather than continuing on PID reuse. Prefer an app-instance token or launch/start-time guard in addition to PID, and on shutdown take a final `snapshot_existing_sessions "ghostty-exit"` then exit without zero-window cleanup. Add a PID-reuse simulation test for the reaper decision loop.

### SEC-S2 (medium) — Physical Ghostty IDs are used in regex filters before validation
**Where:** `session-manager.zsh:393-403`
**What:** `_ghostty_zmx_write_id_map` writes `id-map` by filtering existing entries with `grep -v -E "^(W ${curWin} |T ${curWin} ${curTab} )"` before validating `curWin` and `curTab`. If AppleScript/position parsing ever returns regex metacharacters or unexpected spacing, the filter can remove unintended map entries and corrupt restore mapping.
**Recommendation:** Validate physical window/tab IDs with the same alphanumeric check before writing the map, or replace the regex filter with fixed-string parsing and reconstruction. Keep the validation at the `_ghostty_zmx_write_id_map` boundary rather than relying on callers.

### SEC-S3 (medium) — Installer removes `confirm-close-surface = false` outside the managed block
**Where:** `install.sh:106-117`, especially `install.sh:112-114`
**What:** Migration strips any `confirm-close-surface = false` line in Ghostty config, not only the known experimental line inside the managed block. This contradicts the documented behavior that conflicts outside the managed section are left untouched and can unexpectedly change user-controlled close confirmation behavior.
**Recommendation:** Limit removal to the managed ghostty-zmx block and the documented experimental inline context, or fail with an explicit remediation warning when an unsupported false setting remains outside managed config. Preserve backups, but do not silently edit unrelated user config.

### SEC-S4 (low) — Uninstaller does not clean the current per-user runtime directory
**Where:** `session-manager.zsh:30-45`, `session-manager.zsh:129-131`, `session-manager.zsh:311`, `uninstall.sh:102-103`
**What:** Runtime scripts/logs now live under a per-user directory such as `${TMPDIR}/ghostty-zmx-${UID}` with mode `700`, but uninstall only removes legacy `/tmp/ghostty-zmx-*` paths. Stale executable reaper scripts or logs can remain after uninstall.
**Recommendation:** Teach uninstall to remove the current runtime directory only after verifying it is the expected `ghostty-zmx-${UID}` directory, owned by the current user, and not a symlink or unsafe parent. Otherwise document that runtime files are transient and cleaned by the reaper on normal exit.

### SEC-S5 (low) — Scrollback line limit is not numerically validated
**Where:** `session-manager.zsh:88`, `session-manager.zsh:189`
**What:** `GHOSTTY_ZMX_SCROLLBACK_LINES` is passed directly to `tail -n`. This is not a shell-injection issue, but a malformed or huge value can cause snapshot failure or excessive resource use.
**Recommendation:** Validate the value as a positive integer at process start or before snapshotting, defaulting to `1000` on invalid input and logging the fallback.

### SEC-S6 (low) — Experimental `/tmp/zmx-*` cleanup is broad
**Where:** `install.sh:172-174`
**What:** The installer removes stale `/tmp/zmx-restore-*`, `/tmp/zmx-restoring-*`, and `/tmp/zmx-reaper-*` globs. The sticky `/tmp` directory mitigates symlink following, but the operation is broader than necessary and can remove experimental runtime state the user expected to preserve.
**Recommendation:** Prefer removing only known lock/script paths under a safe runtime directory, or add ownership and basename checks before deleting broad `/tmp/zmx-*` matches.

### SEC-S7 (low) — Debug log path permissions are not hardened
**Where:** `session-manager.zsh:54-58`, `session-manager.zsh:162-166`
**What:** Debug logs are appended under user-controlled `${GHOSTTY_ZMX_STATE_HOME}` without checking directory ownership or mode. Current logging avoids terminal history content, but a world-writable state path could let another local user append or interfere with logs.
**Recommendation:** Require the state directory to be user-owned and not world-writable when debug logging is enabled, or create it with restrictive mode and warn/fall back if the path is unsafe.

## Well-maintained areas

- Managed zmx session names are validated before use in history paths, snapshot files, queue pops, restore loading, and reaper decisions (`session-manager.zsh:19-28`, `session-manager.zsh:80-95`, `session-manager.zsh:97-119`, `session-manager.zsh:209-232`, `session-manager.zsh:314-339`, `session-manager.zsh:420-431`).
- Runtime reaper scripts moved from predictable public `/tmp` filenames to a per-user runtime directory with lock directories and a `700` directory mode (`session-manager.zsh:30-52`, `session-manager.zsh:121-131`).
- Destructive uninstall of install/data/state directories is opt-in and guarded against deleting `/`, `$HOME`, parent directories, non-user-owned paths, or basenames other than `ghostty-zmx` (`uninstall.sh:49-67`, `uninstall.sh:105-120`).
- The implementation avoids `eval`, quotes zmx and AppleScript command inputs, and debug logs do not include saved terminal history content (`session-manager.zsh:113-118`, `session-manager.zsh:162-166`, `session-manager.zsh:681-745`).
- Tests cover invalid migrated session filtering, non-destructive `--yes` uninstall, explicit destructive uninstall flags, unsafe data-path refusal, snapshot truncation, banner ordering, and debug-log non-leakage (`tests/install-uninstall.zsh:50-84`, `tests/snapshot-scrollback.zsh:50-69`).

## Summary

No block findings were identified. The main remaining security/adversarial issues are medium-severity data-loss and config-integrity risks: reaper behavior after Ghostty PID reuse, unvalidated physical IDs in id-map filtering, and installer removal of `confirm-close-surface = false` outside the managed block. The implementation otherwise shows substantial hardening around session-name validation, runtime paths, uninstall deletion guards, and debug-log leakage.
