## Findings

### R3-E2E-ADV-0 (medium) — Adversarial convergence is contingent on the live cumulative E2E run passing
**Where:** `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-results.md:12`

**What:** This report was written before the orchestrator-launched live supervised E2E convergence run completed. I did not run broad Ghostty E2E concurrently. The conclusions below are based on the existing supervised artifact plus static shell/code review, so final adversarial convergence is contingent on the new live run passing with layout/client assertions included.

**Recommendation:** Treat this report as conditional until the live cumulative result artifact is available and shows all required scenarios passing, especially Cmd-Q restore layout shape and `clients=1` for restored managed sessions.

### R3-E2E-ADV-1 (high) — Cmd-Q restore was marked PASS despite failing the required layout/client invariants
**Where:** `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-supervisor.zsh:210`, `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-supervisor.zsh:226`, `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-results.md:12`

**What:** The supervised summary reports `SCENARIO_RESULT cmd-q-restore PASS`, but the harness only checks that the old sessions still exist and markers remain in `zmx history`. It does not assert the design-required restored layout shape or `clients=1` for every restored managed session. The full log referenced by `e2e-rerun-results.md` shows this scenario was not actually restored correctly: before quit it had 2 windows, 3 tabs, and 4 terminals; after reopen it had only 2 windows, 2 tabs, and 2 terminals. The same log contains restore failures (`restore failed step=split`, `restore failed step=new-tab`, `restore failed step=new-window`) and shows two of the four managed sessions with `clients=0`. That contradicts the design's Cmd-Q restore scenario: “verify same session names, `clients=1`, same layout shape, and markers in `zmx history`.”

**Recommendation:** Fix now before using the cumulative E2E pass as release evidence. Tighten the E2E harness to compare pre/post window-tab-terminal shape and to require every restored managed session to report `clients=1`; then rerun the supervised E2E. If the same AppleScript failures reproduce, fix the restore path rather than classifying Cmd-Q restore as passed.

### R3-E2E-ADV-2 (medium) — Restore creation failures still leave queued sessions to attach into the wrong reduced layout
**Where:** `session-manager.zsh:681`, `session-manager.zsh:683`, `session-manager.zsh:716`, `session-manager.zsh:750`, `session-manager.zsh:793`

**What:** `_ghostty_zmx_restore` writes `restore-first` and the full `restore-queue` before attempting AppleScript surface creation. If a split/tab/window creation fails, the code logs the failure and continues, but the queue still contains sessions for surfaces that were never created. Newly-started shells then pop and attach queued sessions into whatever terminals exist, which can make marker/history checks pass while the physical Ghostty layout is incomplete. This matches the supervised full-log symptom for Cmd-Q restore: AppleScript creation failed, yet the scenario was marked PASS because preserved zmx sessions and markers survived.

**Recommendation:** Fix if the tightened E2E rerun reproduces the restore failures. At minimum, a restore with any AppleScript creation failure should be surfaced as failed and should not be treated as a valid restored layout. Prefer delaying queue exposure until after corresponding surfaces are successfully created, or recording expected surface count and verifying that all queued sessions become attached exactly once before declaring restore complete.

### R3-E2E-ADV-3 (medium) — Reboot scrollback path can still report success after `zmx run` fails
**Where:** `session-manager.zsh:244`, `session-manager.zsh:248`, `session-manager.zsh:251`

**What:** This remains a real but deferrable hardening issue from R2. The success path is covered by static fixtures and the supervised reboot simulation: `zmx run "$session" true` is used before `zmx print`, and the marker/banner are verified in `zmx history`. However, if `zmx run` fails, the function only logs `zmx run failed` and still pipes the snapshot to `zmx print`. The design explicitly records that `zmx print <missing-session>` can exit successfully without creating a session or history, so this branch can log `zmx print restored scrollback` without having restored scrollback into a live session.

**Recommendation:** Defer to v0.2 only if the release gate accepts success-path coverage. Harden by returning on `zmx run` failure or re-checking `zmx list --short` before `zmx print`; only log restored scrollback after the session exists and, ideally, after a post-print history check confirms the banner.

### R3-E2E-ADV-4 (medium) — A stale restore-in-progress flag can suppress cleanup after restore-driver death
**Where:** `session-manager.zsh:632`, `session-manager.zsh:829`, `session-manager.zsh:473`

**What:** `_ghostty_zmx_restore` creates `restoring-${ghosttyPID}.lock` near the start of restore, but schedules delayed removal only after the restore loop finishes. The generated reaper skips cleanup while that flag exists. A killed driver shell, shell crash, or unrecoverable AppleScript path before the cleanup is scheduled can leave the flag present for the lifetime of the Ghostty process, suppressing pane/window cleanup and biasing toward preservation. This is especially relevant because the supervised full log already showed AppleScript restore errors; a harder failure at the same stage would not necessarily reach the scheduled cleanup.

**Recommendation:** Defer to v0.2 if no live crash is observed, but keep it as a real cleanup/reboot robustness gap. Make restore flags self-expiring by storing PID/timestamp and having the reaper ignore or remove stale flags after a conservative TTL, or schedule cleanup immediately after creating the flag and extend it as needed.

### R3-E2E-ADV-5 (low) — Session-log mutation remains append-vs-rewrite race-prone
**Where:** `session-manager.zsh:193`, `session-manager.zsh:349`

**What:** Normal session creation appends to `sessions` without a shared lock, while the generated reaper rewrites the same file via `grep -vxF ... > ${log}.tmp` followed by `mv`. A new split/tab/window attaching while another managed surface is being cleaned can lose the new append. That would leave a live zmx session unmanaged for future cleanup/restore. The supervised scenarios were serialized enough not to expose this race.

**Recommendation:** Defer. Add a shared lock around all `sessions` mutations in v0.2, including `_ghostty_zmx_log_session` and generated-reaper `cleanup_log`.

### R3-E2E-ADV-6 (low) — Reaper still depends on positional `zmx list` fields
**Where:** `session-manager.zsh:402`, `session-manager.zsh:480`

**What:** Unmanaged-session protection has the correct boundary: only valid `zmx-*` names that also appear in ghostty-zmx's `sessions` file are eligible for cleanup. The parser nevertheless assumes current `zmx list` tabular order (`name` in field 1 and `clients` in field 3). If zmx 0.6.x changes field order or inserts a column, cleanup may leak detached managed sessions or misclassify attached counts. This is more likely to cause preservation/leaks than unmanaged reaping.

**Recommendation:** Defer. Parse fields by key rather than by position, or use `zmx list --short` plus a stable per-session detail command if available.

## Well-maintained areas

- Static shell checks passed during this review: `zsh -n session-manager.zsh install.sh uninstall.sh`, `zsh tests/install-uninstall.zsh`, `zsh tests/snapshot-scrollback.zsh`, `zsh tests/restore-id-map.zsh`, and `zsh tests/release-control.zsh` completed with no output.
- The installer preserves user-controlled Ghostty conflicts outside the managed block in fixture tests, including `confirm-close-surface = false` and `quit-after-last-window-closed = true`, while warning about the unsupported close-all-windows setting.
- The E2E supervisor uses a temporary managed block with `confirm-close-surface = false` and restores the user's real Ghostty config, installed manager, and uninstall script byte-for-byte via an EXIT/INT/TERM trap. The summary reports `CONFIG_RESTORE_BYTE_FOR_BYTE=PASS`, `MANAGER_RESTORE_BYTE_FOR_BYTE=PASS`, and `UNINSTALL_RESTORE_BYTE_FOR_BYTE=PASS`.
- Reaper unmanaged-session scoping remains strong in shape: validate managed-looking session names, require membership in the ghostty-zmx `sessions` file, snapshot before destructive cleanup, and delete snapshots after intentional close cleanup.
- Reboot scrollback success-path behavior is materially covered: fixture tests verify `zmx run` precedes `zmx print`, banner ordering, list-failure skip behavior, and debug-log non-leakage; the supervised scenario verified the banner and marker in `zmx history` after simulated session loss.
- Deferred items around `ghostty-zmx reset`, remote/SSH inheritance, Homebrew packaging, and broad process/TUI persistence remain truly out of v0.1 scope.

## Summary

I do not consider the cumulative E2E state release-clean based on the artifact available at the time this report was written. Adversarial convergence is contingent on the orchestrator-launched live supervised E2E run passing. The strongest issue in the existing evidence is that Cmd-Q restore was reported PASS while the full log shows missing tabs/panes, `clients=0` restored sessions, and AppleScript restore failures. That undermines the central “all 8 manual scenarios pass” exit criterion unless the new live run supersedes it with stricter layout/client assertions. The remaining concerns from R2—`zmx run` partial failure, stale restore flags, unsynchronized `sessions` mutation, and positional `zmx list` parsing—are real hardening items but are still reasonable v0.2 deferrals if the corrected Cmd-Q/layout E2E passes.
