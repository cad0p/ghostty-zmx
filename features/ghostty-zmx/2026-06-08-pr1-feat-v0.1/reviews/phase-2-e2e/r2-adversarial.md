## Findings

### R2-E2E-ADV-1 (medium) — Reboot scrollback path can log a successful restore after `zmx run` fails
**Where:** `session-manager.zsh:244`, `session-manager.zsh:248`, `session-manager.zsh:251`

**What:** The required reboot path is correctly implemented for the successful case and the supervised rerun proved it live: `SCENARIO_RESULT reboot-scrollback-simulation PASS`, with debug evidence for `fresh-session detection ... exists=0` and `zmx print restored scrollback ...`. The partial-failure branch is still weak: if `zmx run "$session" true` fails, the function only logs `zmx run failed` and still pipes the snapshot to `zmx print`. The design records that `zmx print <missing-session>` can exit successfully without creating a session or history, so this branch can emit `zmx print restored scrollback ...` even though the session was never pre-created and the saved history may not be present in `zmx history` after attach.

**Recommendation:** Defer for v0.2 unless another live failure appears before merge. Harden by either returning immediately on `zmx run` failure, or re-checking `zmx list --short` after `zmx run` and before `zmx print`; only log `zmx print restored scrollback` after verifying the session exists and/or after a post-print `zmx history` check contains the restore banner.

### R2-E2E-ADV-2 (medium) — A stale restore-in-progress flag can suppress cleanup if the restore driver is killed mid-restore
**Where:** `session-manager.zsh:631`, `session-manager.zsh:829`, `session-manager.zsh:472`

**What:** `_ghostty_zmx_restore` creates `restoring-${ghosttyPID}.lock` before AppleScript layout creation, but schedules its delayed removal only at the end of the restore loop. The generated reaper skips all cleanup while that flag exists. A hard failure such as `kill -9` of the driver shell, a shell crash, or a severe AppleScript path abort after the flag is created but before the delayed cleanup is scheduled can leave the flag behind for the lifetime of the Ghostty process. That would bias the system toward preservation/no-cleanup until quit or runtime cleanup.

**Recommendation:** Defer. Make restore flags self-expiring or write a timestamp/PID into the flag and let the reaper ignore/remove it after a conservative TTL. A smaller v0.1-safe improvement would be scheduling cleanup immediately after creating the flag, then extending/removing it normally at successful restore completion.

### R2-E2E-ADV-3 (low) — Session log updates are not serialized between attach and reaper cleanup
**Where:** `session-manager.zsh:190`, `session-manager.zsh:193`, `session-manager.zsh:342`, `session-manager.zsh:350`

**What:** Normal session creation appends to `sessions` without a file lock, while the generated reaper rewrites the same file through `grep -vxF ... > ${log}.tmp` followed by `mv`. The supervised scenarios are serialized enough that this passed, including pane/window cleanup and unmanaged preservation. Under adversarial timing, closing one managed surface while another new split/tab/window is being auto-attached could race append-vs-rewrite and lose the new session entry. The lost session would still exist in zmx but would no longer be protected/restored as a ghostty-zmx-managed session.

**Recommendation:** Defer. Use a shared lock around all `sessions` reads/writes that can mutate state (`_ghostty_zmx_log_session`, `cleanup_log`, restore load/queue preparation if needed). Keep the current behavior for v0.1 if no live race is observed.

### R2-E2E-ADV-4 (low) — Reaper depends on current tabular `zmx list` field ordering
**Where:** `session-manager.zsh:401`, `session-manager.zsh:402`, `session-manager.zsh:479`

**What:** Unmanaged-session protection is strong in the current target environment: the reaper filters to valid `zmx-*` names and then requires membership in ghostty-zmx's `sessions` file before killing. The parser, however, assumes `zmx list` has `name=...` in field 1 and `clients=...` in field 3. If zmx 0.6.x changes field order or inserts another tab-separated column, detached managed sessions may be missed, and attached counts may be wrong. This is more likely to cause leaks/preservation than unmanaged reaping, but it affects close cleanup reliability.

**Recommendation:** Defer. Parse `zmx list` by key name rather than position, or prefer `zmx list --short` plus a per-session detail command if available. Keep the current parser for v0.1 because live E2E showed it matches the tested zmx output.

## Well-maintained areas

- The supervised rerun passed all eight design scenarios: Cmd-Q restore, working-directory inheritance, pane close cleanup, window close cleanup, close-all-windows cleanup, Cmd-Q does-not-clean, reboot scrollback simulation, and unmanaged-not-reaped.
- Real user file restoration was explicitly verified: `CONFIG_RESTORE_BYTE_FOR_BYTE=PASS`, `MANAGER_RESTORE_BYTE_FOR_BYTE=PASS`, and `UNINSTALL_RESTORE_BYTE_FOR_BYTE=PASS` in `e2e-rerun-results.md`.
- The E2E harness avoided the earlier blocking marker-injection failure by using `zmx print` for markers and a short `ZMX_DIR=/tmp/gzmx-$$`, and it used the required temporary `confirm-close-surface = false` override only under a restore trap.
- Static/shell checks passed locally during this review: `zsh -n session-manager.zsh install.sh uninstall.sh`, `zsh tests/install-uninstall.zsh`, `zsh tests/snapshot-scrollback.zsh`, `zsh tests/restore-id-map.zsh`, and `zsh tests/release-control.zsh` all completed with no output.
- Reaper unmanaged-session protection has the right core shape: validate managed-looking names, require membership in the ghostty-zmx `sessions` file, snapshot before cleanup, and delete snapshots after intentional close cleanup.
- Reboot scrollback success-path evidence is strong: the implementation uses `zmx run "$session" true` before `zmx print`, injects the exact required banner, and the supervised rerun verified the marker and banner inside `zmx history` after simulated daemon/session loss.
- Diagnostic strings are stable and reviewable. The prompt's GNU `grep -P` command is not portable on this macOS host, so I extracted `_ghostty_zmx_debug "..."` and generated-reaper `debug_log "..."` strings with Python instead and compared them against the supervised log patterns used by the E2E harness. No diagnostic-message deviations were found.

## Summary

No fix-now E2E blockers found in this adversarial pass. The current branch has credible live evidence for all required v0.1 scenarios and byte-for-byte restoration of the user's real Ghostty config and installed files. The remaining adversarial concerns are partial-failure/race hardening around reboot-scrollback `zmx run` failure, stale restore flags after a killed restore driver, unsynchronized `sessions` mutations, and positional parsing of `zmx list`; these are suitable deferrals unless another live run exposes them before merge.
