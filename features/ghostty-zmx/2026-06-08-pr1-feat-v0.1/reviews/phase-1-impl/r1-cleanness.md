## Findings

### C1 (high) — Installed and documented zsh source line contains literal escaped quotes
**Where:** `install.sh`:27, `README.md`:38, `uninstall.sh`:22
**What:** The public `.zshrc` integration line is stored and documented as `[[ -r \"$HOME/...\" ]] && source \"$HOME/...\"`. If appended literally, zsh treats `\"` as a literal quote character in the path rather than as shell quoting, so the readability check and `source` target the wrong filename. This makes the main installed entrypoint easy to copy/persist incorrectly and couples uninstall matching to the same invalid spelling.
**Recommendation:** Use the actual zsh line without backslashes in both scripts and docs: `[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"`. Keep install and uninstall matching the same valid literal line; optionally have uninstall remove both the old escaped form and the corrected form for migration from this PR version.

### C2 (medium) — `uninstall.sh --yes` expands into destructive data/state deletion
**Where:** `uninstall.sh`:37-40, `uninstall.sh`:86-97, `README.md`:161-171
**What:** `--yes` answers every confirmation affirmatively, including deletion of `GHOSTTY_ZMX_DATA_HOME` and `GHOSTTY_ZMX_STATE_HOME`. That makes the non-interactive uninstall API surprisingly destructive: a flag documented as the non-interactive form also deletes the managed sessions list, debug logs, and saved scrollback snapshots. This conflicts with the otherwise careful public contract that uninstall leaves zmx sessions alive and asks before deleting state.
**Recommendation:** Make `--yes` only approve the base uninstall flow, while preserving data/state by default. Add explicit opt-in flags such as `--remove-data`, `--remove-state`, and/or `--remove-install-dir`, or require separate environment opt-ins for destructive cleanup in non-interactive mode. Document the final flag matrix.

### C3 (medium) — Sourced runtime leaks unprefixed globals into user shells
**Where:** `session-manager.zsh`:493, `session-manager.zsh`:512-518, `session-manager.zsh`:521-530
**What:** Because `session-manager.zsh` is sourced from `.zshrc`, top-level assignments such as `SESSION_NAME=""` and `POSITION=...` become user-shell variables. Several `typeset` declarations in the top-level auto-attach block also become shell-scope variables after `zmx attach` returns. For a shell integration, this unnecessarily broadens the public surface and risks collisions with user shell state.
**Recommendation:** Wrap the auto-attach block in a single prefixed function, use local variables inside it, call it, then unset the function if it is not intended as public API. If variables must remain observable, prefix them consistently as `GHOSTTY_ZMX_*` and document them.

### C4 (low) — Dead/no-op helpers and duplicated reaper helpers obscure the runtime surface
**Where:** `session-manager.zsh`:33-49, `session-manager.zsh`:113-145, `session-manager.zsh`:530
**What:** `_ghostty_zmx_unlog_session` and `_ghostty_zmx_snapshot_history` are defined in the sourced script but the generated reaper reimplements equivalent `cleanup_log` and `snapshot_history` helpers. `_ghostty_zmx_cleanup_after_detach` is a no-op but is still called after `zmx attach`. These look like stale extension points and make it harder to audit which cleanup path is authoritative.
**Recommendation:** Remove unused/no-op helpers, or clearly wire them into the actual runtime. If the reaper must be self-contained, keep only the generated-script helpers and avoid exposing duplicate sourced functions.

### C5 (low) — Undocumented Ghostty config path override becomes accidental API
**Where:** `install.sh`:24, `uninstall.sh`:19, `README.md`:102-109
**What:** `GHOSTTY_ZMX_GHOSTTY_CONFIG` is supported by install and uninstall, but it is absent from the documented environment variable list. Environment variables are part of the package's public surface once shipped, especially for installer behavior.
**Recommendation:** Either document `GHOSTTY_ZMX_GHOSTTY_CONFIG` as an advanced/testing override, or keep the public API minimal by renaming/removing it before v0.1. If retained for E2E harnesses, document its intended scope and stability.

### C6 (low) — Timing constants are still magic numbers
**Where:** `session-manager.zsh`:149, `session-manager.zsh`:216-229, `session-manager.zsh`:473-489, `session-manager.zsh`:457
**What:** Several runtime waits/retries are hardcoded (`sleep 5`, 50 queue-lock attempts at 0.1s, 10 Ghostty PID/AppleScript readiness attempts at 0.5s, another restore-flag cleanup `sleep 5`) while nearby behavior is configurable via named `GHOSTTY_ZMX_*` defaults. This makes tuning and debugging startup/restore edge cases less clear.
**Recommendation:** Promote these values to named internal constants, and expose only the ones users are expected to tune. For example: `_GHOSTTY_ZMX_REAPER_STARTUP_DELAY`, `_GHOSTTY_ZMX_QUEUE_LOCK_ATTEMPTS`, `_GHOSTTY_ZMX_QUEUE_LOCK_DELAY`, `_GHOSTTY_ZMX_GHOSTTY_READY_ATTEMPTS`, and `_GHOSTTY_ZMX_RESTORE_FLAG_CLEANUP_DELAY`.

## Well-maintained areas

- File layout and installed paths generally match the v0.1 package shape: `session-manager.zsh`, `install.sh`, `uninstall.sh`, XDG data/state paths, and `/tmp/ghostty-zmx-*` runtime files are consistently named.
- The installer is intentionally scoped to a marked Ghostty config block and warns about unmanaged conflicting settings rather than overwriting arbitrary user config.
- The README is clear about zsh/macOS/Ghostty AppleScript scope, serial restore, local-only behavior, reboot limitations, and non-npm release control.
- Release metadata is minimal and aligned with the shell-only package story; `package.json` is used as a version source without promising npm publication.
- Most runtime helpers are consistently prefixed with `_ghostty_zmx_`, which is a good baseline for a sourced zsh integration.

## Summary

The cleanness/API surface is close to the intended v0.1 shape, but the escaped `.zshrc` source line should be fixed before relying on installer output or README instructions. The next most important API cleanup is making uninstall's non-interactive mode non-destructive by default. After that, tighten the sourced-shell surface by localizing globals, removing stale helpers, documenting or removing the Ghostty config override, and naming the remaining timing constants.
