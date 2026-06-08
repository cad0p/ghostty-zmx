## Findings

### F1 (high) — `zmx history` pipeline failures can overwrite or empty scrollback snapshots
**Where:** `session-manager.zsh:80-89`, `session-manager.zsh:183-193`
**What:** Both the main snapshot helper and the generated reaper snapshot helper treat the status of the final `tail` command as the pipeline status. In zsh, a failed `zmx history` followed by successful `tail` is treated as success, so an existing Cmd-Q snapshot can be replaced with an empty file and later reboot restore can inject only the banner.
**Recommendation:** Capture `zmx history` output to a temporary file and check its exit status before truncating with `tail`, or enable/use pipeline-failure handling. Only move the temporary snapshot into place after `zmx history` succeeds.

### F2 (medium) — restore lock can be removed before serial restore has fully completed
**Where:** `session-manager.zsh:17`, `session-manager.zsh:442`, `session-manager.zsh:669-670`, `session-manager.zsh:272-273`
**What:** `_ghostty_zmx_restore` schedules removal of `restoring-${ghosttyPID}.lock` after a fixed 5 seconds. For layouts with more than a few surfaces, serial AppleScript creation plus `GHOSTTY_ZMX_RESTORE_STEP_DELAY=1` can still be active after that lock disappears. The reaper skips cleanup only while restore markers are present, so it can start managing detached sessions while restore is still creating surfaces.
**Recommendation:** Keep the restore lock until the restore driver has completed handoff for all queued sessions, or replace the fixed delay with a duration derived from session count/step delay plus a conservative AppleScript margin. Alternatively add an explicit restore-complete marker that the reaper observes.

### F3 (medium) — unterminated experimental `.zshrc` block is not fatal before adding the new source line
**Where:** `install.sh:67-80`, `install.sh:90-98`, `install.sh:207`
**What:** `remove_experimental_zsh_block` detects an unterminated experimental block and leaves the file unchanged, but `ensure_source_line` ignores that failure and appends the ghostty-zmx source line anyway. This can leave a broken old block plus the new source line in `.zshrc`.
**Recommendation:** Abort installation or repair the unterminated block before appending the new source line. At minimum, do not ignore the error from `remove_experimental_zsh_block`.

### F4 (medium) — fresh-session detection treats `zmx list --short` failure as “session missing”
**Where:** `session-manager.zsh:97-115`
**What:** `_ghostty_zmx_restore_saved_scrollback` cannot distinguish “session absent” from “`zmx list --short` failed.” A transient zmx/daemon/command failure can cause the code to attempt `zmx run`/`zmx print` for a session that may actually exist or may be unreachable, risking broken restore/attach behavior.
**Recommendation:** Explicitly check the exit status of `zmx list --short`. If the command fails, log the failure and skip injection/attach or retry; only run the `zmx run` + `zmx print` path when list succeeds and the session is absent.

### F5 (low) — managed session-name validation is broader than the canonical spec
**Where:** `session-manager.zsh:19-21`, `session-manager.zsh:151-153`, `session-manager.zsh:500-501`
**What:** The valid-name regex accepts arbitrary alphanumeric logical window/tab components, while the design specifies Ghostty hex portions. This can allow corrupted or noncanonical session names to be treated as managed sessions.
**Recommendation:** Tighten managed-name validation to hexadecimal components for window and tab IDs, with the terminal component remaining the first eight hex characters.

## Well-maintained areas

- Restore grouping by logical window/tab and serial queue handling align with the design, and restored child shells do not rewrite the id-map from `front window`.
- The reaper is scoped to sessions listed in the ghostty-zmx sessions file and preserves Cmd-Q/exit snapshots while cleaning intentional pane/window closes.
- Migration covers the guarded `.zshrc` source line, managed Ghostty block, experimental env cleanup, sessions copy, stale runtime flag cleanup, and final cleanup reminder.
- Reboot scrollback restore uses the required `zmx run "$session" true` before `zmx print`, includes the exact required banner, and debug logging avoids history contents.
- Release-control artifacts are present: `package.json`, `.github/workflows/release.yml`, `RELEASE.md`, and README release-control notes.

## Summary

The implementation mostly matches the v0.1 design, especially around serial restore, managed-session-only reaping, migration, and reboot scrollback injection. The highest-priority correctness risk is snapshot handling: failed `zmx history` calls can erase saved scrollback. The next fixes should address the restore-lock race, migration error handling, and explicit `zmx list` failure handling.
