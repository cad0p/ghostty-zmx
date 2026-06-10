# Phase 3 bloat review: correctness over-trim guardrails

Reviewer: Phase 3 correctness / over-trim
Scope: `design.md`, `deferred.md`, `session-manager.zsh`, `install.sh`, `uninstall.sh`, `tests/*.zsh`, and Phase 2 E2E rerun results.

## Summary

The current implementation has several areas that look verbose, duplicated, or defensive, but those shapes are required by the locked v0.1 design and by the passing Phase 2 E2E rerun. Trimming them mechanically would risk regressions in restore election, Ghostty layout targeting, close cleanup, unmanaged-session safety, reboot scrollback restore, or user config restoration.

I found one real correctness issue worth carrying forward: the reboot scrollback restore path still attempts `zmx print` after `zmx run` fails, which can produce misleading success logging and may fail to inject history into the fresh session. This is already tracked as deferred E2E adversarial work, but it is a genuine correctness edge and should not be hidden by a bloat-cleanup pass.

## Findings and over-trim guardrails

### R1-OT-1 — medium — `session-manager.zsh:251`

**Finding:** `_ghostty_zmx_restore_saved_scrollback` logs `zmx run failed` but continues immediately to `zmx print` and can then log `zmx print restored scrollback` if `zmx print` exits successfully. The design explicitly records that `zmx print <missing-session>` does not create the session; the required flow depends on `zmx run "$session" true` creating it first.

**Why it matters:** This is not removable defensive verbosity; it is a correctness seam. If `zmx run` fails because zmx is unavailable, its daemon is wedged, or the session was not created, the subsequent `zmx print` can be a no-op/misleading success. That undermines the reboot-scrollback guarantee even though the E2E success path passed.

**Recommendation:** In a follow-up fix, after `zmx run` failure re-run `zmx list --short` for the target session before attempting `zmx print`; if the session still does not exist, log a restore failure and skip printing. Keep the existing banner and successful `zmx run`/`zmx print` sequence for the passing E2E path.

### R1-OT-2 — high — `session-manager.zsh:262`

**Finding:** The generated reaper duplicates helper logic from the sourced manager (`valid_session_name`, history path handling, snapshotting, elapsed parsing, zmx list parsing). This looks like prime bloat.

**Why it must not be trimmed unsafely:** The reaper is launched with `nohup /bin/zsh` and must survive after the attaching shell exits or a Ghostty surface is closed. It cannot depend on sourced shell functions remaining in memory. Phase 2 E2E coverage for pane close, window close, close-all-windows cleanup, Cmd-Q preservation, and unmanaged-session preservation depends on this standalone reaper behavior.

**Recommendation:** Do not replace the generated reaper with calls to `_ghostty_zmx_*` sourced helpers in v0.1. If deduplication is desired later, generate the reaper from a shared template or install a separate executable, and rerun the full live close/Cmd-Q E2E matrix.

### R1-OT-3 — high — `session-manager.zsh:617`

**Finding:** `_ghostty_zmx_restore` is long and has nested queue/id helpers, grouping arrays, serial AppleScript snippets, explicit target-window/tab matching, per-step sleeps, and failure cleanup. It looks overly complex.

**Why it must not be trimmed unsafely:** The design requires serial restore because startup-time batch/direct input restore was unreliable. The restore must regroup sessions by logical window/tab rather than trusting append order, target restored windows/tabs explicitly rather than relying on front-window focus, and expose queue entries incrementally so newly-created shells attach to the intended session. Phase 2 Cmd-Q restore passed with layout shape `1;2,1`, all clients attached, markers in `zmx history`, and no restore failure debug entries.

**Recommendation:** Do not collapse the restore path into a simple append-order queue or focus-based AppleScript. Any simplification must preserve grouping by logical window/tab, explicit physical-target matching, queue removal on AppleScript failure, and the serial delay model.

### R1-OT-4 — high — `session-manager.zsh:568`

**Finding:** The `id-map` logic appears redundant because session names already include window/tab IDs.

**Why it must not be trimmed unsafely:** Ghostty physical window/tab IDs change across app restart. The map bridges restored physical IDs back to logical IDs so new splits/tabs/windows after restore inherit the restored logical window/tab instead of creating a new logical layout. It also avoids restored child shells rewriting the map through `front window` while focus is moving during restore.

**Recommendation:** Keep `_ghostty_zmx_apply_position_map`, `_ghostty_zmx_write_id_map`, and `_ghostty_zmx_record_position_map` unless an alternative explicitly preserves restored logical identity for newly-created surfaces and passes working-directory/session-generation E2E.

### R1-OT-5 — medium — `session-manager.zsh:128`

**Finding:** Restore-attempt process tokens and the `restore-attempted-${ghosttyPID}.done` flag look like complicated lock state beyond the visible `restore-${pid}.lock` lock.

**Why it must not be trimmed unsafely:** This was added to prevent repeated restore-driver election inside one Ghostty process. The tests assert only one election and that later shell startups generate fresh sessions rather than reattaching `restore-first` repeatedly. The elapsed/lstart token handling also protects against PID reuse in the process-scoped runtime state.

**Recommendation:** Do not remove the attempted flag or token comparison as a bloat cleanup. A future simplification should first add a replacement one-shot invariant and PID-reuse test coverage.

### R1-OT-6 — medium — `session-manager.zsh:205` and `session-manager.zsh:360`

**Finding:** Snapshotting uses temp files, truncation, final moves, and duplicated reaper logic instead of `zmx history "$session" | tail -n ... > "$historyFile"`.

**Why it must not be trimmed unsafely:** The temp/final-file pattern prevents a failed `zmx history` or `tail` from overwriting the previous good snapshot. Reboot-scrollback recovery depends on preserved snapshots after Cmd-Q/restart, and tests assert a failed history command leaves an existing snapshot intact.

**Recommendation:** Keep failure-safe snapshot writes in both manager and generated reaper. If refactored, preserve the invariant: never replace an existing snapshot unless the new history capture and truncation both succeed.

### R1-OT-7 — medium — `session-manager.zsh:443`

**Finding:** Reaper startup delay, zero-window grace, detached-session stability tracking, and restore-active skips look like timing bloat.

**Why it must not be trimmed unsafely:** Ghostty/zmx close behavior is asynchronous: surface closure detaches zmx clients before shell code resumes, Cmd-Q can detach all clients, and close-all-windows relies on Ghostty remaining alive with `windows=0`. The delay/grace/stability checks are what distinguish pane/window close cleanup from Cmd-Q preservation and restore in progress.

**Recommendation:** Do not reduce this to immediate kill-on-`clients=0`. Any timing simplification must still pass pane close, window close, close-all-windows cleanup, Cmd-Q-does-not-clean, and unmanaged-not-reaped E2E.

### R1-OT-8 — medium — `install.sh:99` and `install.sh:130`

**Finding:** The installer has managed-block validation, strip/re-add behavior, conflict warnings, and a printed plan that can look verbose for a small shell package.

**Why it must not be trimmed unsafely:** The design requires editing only the managed Ghostty section, leaving conflicting user settings outside the block untouched, warning about unsupported `quit-after-last-window-closed = true`, and showing exactly what will be added. The tests assert idempotence and preservation of user config lines.

**Recommendation:** Do not replace this with global `grep`/`sed` removal of Ghostty keys. If cleaned up, keep block-pair validation, user-setting preservation, explicit conflict warnings, backups, and the interactive plan.

### R1-OT-9 — medium — `uninstall.sh:49` and `uninstall.sh:73`

**Finding:** Uninstall path safety checks and non-destructive defaults add a lot of code relative to the package size.

**Why it must not be trimmed unsafely:** The design requires leaving zmx sessions alive by default, asking before deleting data/state, removing only generated runtime files under expected per-user runtime paths, and refusing symlinked unsafe targets. Tests cover symlink refusal, ownership/path checks, and the fact that `--yes` alone must not delete install/data/state directories.

**Recommendation:** Do not replace `safe_remove_tree` / `safe_remove_runtime_dir` with unconditional `rm -rf`. If deletion logic is refactored, keep basename/parent/ownership/symlink checks and the explicit `--remove-*` flags.

### R1-OT-10 — low — `session-manager.zsh:972`

**Finding:** The post-startup `unfunction -m '_ghostty_zmx_*'` and `GHOSTTY_ZMX_KEEP_HELPERS` test escape hatch look like extra API surface management.

**Why it must not be trimmed unsafely:** Normal sourced shells should not keep dozens of private helper functions in the user's namespace, while the shell tests need to source and call helpers directly. Removing either side regresses either user shell hygiene or testability.

**Recommendation:** Keep the cleanup and the private test escape hatch. Do not document `GHOSTTY_ZMX_KEEP_HELPERS` as public API.

## Release-methodology notes

- The E2E rerun shows all eight scenarios passing and verifies byte-for-byte restoration of the user's Ghostty config, installed manager, and installed uninstall script. Do not trim the E2E harness restoration safeguards from the methodology or docs.
- `deferred.md` already records several medium/low items that are tempting to fix during bloat cleanup. Avoid opportunistic implementation churn unless it is tied to a concrete correctness fix and re-run of the relevant E2E scenario.
