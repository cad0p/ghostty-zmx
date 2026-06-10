# E2E Tester Findings — Round 1

## Findings

### E2E-1 (block) — Reaper script has syntax error: AppleScript functions embedded in shell script
**Where:** `session-manager.zsh` lines ~200-350 (reaper generation heredoc)
**What:** The `_ghostty_zmx_start_reaper` function generates a reaper script via heredoc that includes AppleScript `on hex_suffix` / `on terminal_hash` functions. These are not valid shell syntax. The reaper fails to start with:
```
/var/folders/.../reaper-59722.zsh:19: unknown file attribute: i
/var/folders/.../reaper-59722.zsh:23: parse error near `}'
```
This completely breaks the reaper lifecycle — no cleanup of detached sessions, no scrollback snapshots, no zero-windows grace handling.
**Recommendation:** Fix-now. The reaper script should only contain shell code. The AppleScript functions belong in the main session-manager.zsh for the restore driver, not in the generated reaper.

### E2E-2 (high) — Restore driver lock (`restore-${PID}.lock`) never cleaned up
**Where:** `session-manager.zsh` `_ghostty_zmx_auto_attach` function
**What:** The restore driver creates `mkdir "$restoreFlag"` (e.g., `/tmp/ghostty-zmx-501/restore-59722.lock`) but there's no corresponding cleanup. The `restoring-${PID}.lock` is cleaned up after a delay, but the election lock persists. This prevents subsequent Ghostty restarts from electing a restore driver, breaking serial restore on reopen.
**Recommendation:** Fix-now. Add cleanup of the restore driver lock after the restore driver completes its work (after `_ghostty_zmx_restore`, session generation, and reaper start).

### E2E-3 (high) — Sessions file not created on first Ghostty launch
**Where:** `session-manager.zsh` `_ghostty_zmx_auto_attach` flow after restore driver election
**What:** On first Ghostty launch, the login shell becomes the restore driver, `_ghostty_zmx_restore` returns 1 (no sessions file), but the sessions file is never created. The `_ghostty_zmx_log_session` call appears not to be reached, or fails silently. The data directory `~/.local/share/ghostty-zmx` is never created. However, when `_ghostty_zmx_log_session` is tested in isolation, it works correctly and creates the directory and file.
**Recommendation:** Fix-now. Trace the auto_attach flow after restore driver election to find where execution stops or fails.

### E2E-4 (medium) — Debug logging incomplete: only "shell init" logged, no restore-driver or session logs
**Where:** `session-manager.zsh` debug calls throughout auto_attach
**What:** Debug log shows only the initial "shell init" line. No "restore-driver elected", "session logged", "reaper start", or "restore scrollback" entries. This indicates the code path stops early or debug calls are not executed.
**Recommendation:** Fix-now (part of E2E-3 investigation). Add more granular debug logs to trace execution flow.

## Well-maintained areas
- Session name validation and ID parsing works correctly (tested in isolation)
- `_ghostty_zmx_log_session` creates directories and files correctly when called directly
- Snapshot truncation and restore flow logic is sound (tested via unit tests)
- Restore grouping and id-map logic passes unit tests
- Installer/uninstaller idempotency and conflict warnings work (tested)

## Summary
The implementation has critical runtime bugs that prevent basic Ghostty + zmx integration from working:
1. Reaper cannot start (syntax error)
2. Restore driver lock persists across restarts
3. Sessions file not created on first launch

These are fix-now blockers for E2E convergence. No manual E2E scenarios can pass until these are fixed.