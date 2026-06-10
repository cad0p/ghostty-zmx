# R4 cumulative adversarial E2E review

## Verdict

PASS. I found no new E2E fix-now blockers after the post-fix live run and static review. The prior R3 adversarial blockers around Cmd-Q restore evidence are resolved by the combination of:

- `17f754c` — restore queue exposure is now incremental and Ghostty restore surface creation is fixed before reattaching sessions.
- `7dc6eb0` — the supervised E2E harness now fails Cmd-Q restore unless layout shape matches, all restored managed sessions have `clients=1`, markers are present in `zmx history`, and no `restore failed step=` debug lines appear.
- `7cbd57c` / `e2e-rerun-results.md` — strict live Ghostty/zmx evidence shows all eight scenarios passing with those strengthened assertions.

## Scope reviewed

Required files read in full:

- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/design.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/r3-cumulative-adversarial.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/r4-cumulative-live-e2e-tester.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-results.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md`

Additional static/lite checks performed, without running broad live Ghostty E2E:

```sh
git status --short
git branch --show-current
git log --oneline -12
git diff --stat origin/main...HEAD
git diff --name-status origin/main...HEAD
git show --stat --oneline 17f754c
git show --stat --oneline 7dc6eb0
grep -E 'SCENARIO_RESULT cmd-q-restore|before_shape=|after_shape=|restore failed step=|clients=|markers_in_history|after_layout|before_layout' /var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T//ghostty-zmx-e2e-rerun-1781109829/e2e.log | tail -n 80
zsh -n session-manager.zsh install.sh uninstall.sh features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-supervisor.zsh
zsh tests/install-uninstall.zsh
zsh tests/snapshot-scrollback.zsh
zsh tests/restore-id-map.zsh
zsh tests/release-control.zsh
```

The static shell/test command completed with no output.

## Prior adversarial blocker verification

### Cmd-Q restore asserts and passes layout shape

Resolved.

The harness now computes pre/post layout shapes and gates `cmd-q-restore` on equality:

- `layout_shape()` is defined in `e2e-rerun-supervisor.zsh`.
- The scenario captures `before_shape` from `before_layout` and `after_shape` from `after_layout`.
- The pass condition requires `"$before_shape" == "$after_shape"`.

The strict live result reports:

```text
SCENARIO_RESULT cmd-q-restore PASS sessions_remain=4 markers_in_history=1 layout_shape=1;2,1 clients=1
```

The full log corroborates the shape assertion:

```text
before_shape=1;2,1
after_shape=1;2,1
SCENARIO_RESULT cmd-q-restore PASS sessions_remain=4 markers_in_history=1 layout_shape=1;2,1 clients=1
```

This resolves the R3 failure mode where the previous harness could report PASS despite restoring fewer tabs/panes.

### All restored sessions have `clients=1`

Resolved.

The harness now defines `managed_clients_ok()` and requires every session captured before Cmd-Q to match a `zmx list` line containing `clients=1` before the scenario can pass. The live summary reports `clients=1`, and the full log's post-scenario state dump shows the four Cmd-Q sessions each attached with `clients=1`:

```text
name=zmx-600002fc9440-12d20e630-A41C0B96 ... clients=1
name=zmx-600002fc9440-12d20e630-D0771FF9 ... clients=1
name=zmx-600002fc9440-12d22bca0-248B0C4D ... clients=1
name=zmx-600002fd54d0-12d2468a0-C85A7A73 ... clients=1
```

Later `clients=0` lines in the full log are from later scenarios after intentional detach/cleanup activity, not from the Cmd-Q restore assertion set.

### Markers are verified in `zmx history`

Resolved.

The harness still injects per-session markers with `zmx print` before Cmd-Q and now keeps the marker check as part of a stricter combined gate:

```text
hist_ok=1; for s in $s1; do zmx history "$s" | grep -qF "${RUN_ID}-cmdq-$s" || hist_ok=0; done
```

The live result reports `markers_in_history=1` for `cmd-q-restore`, so marker preservation is proved in zmx history rather than merely in outer Ghostty scrollback.

### No restore failure debug lines

Resolved for the strict live run.

The harness records the debug-log line number at scenario start and computes `restore_failure_count_since()` using the pattern `restore failed step=`. The `cmd-q-restore` pass condition requires `restore_failures=0`. The live result is PASS, and a direct grep of the retained full log did not surface `restore failed step=` lines in the Cmd-Q evidence.

### Restore queue no longer masks partial layout creation

Resolved for v0.1 release gating.

R3 noted that the old restore path wrote the full queue before AppleScript surface creation, allowing marker/history checks to pass while the physical layout was reduced. In the current `session-manager.zsh`, restore queue exposure is incremental and failed surface creation removes the corresponding queued session before continuing. Combined with the live harness's shape/client/failure-log assertions, this former false-positive path is no longer a release blocker.

## No new E2E fix-now blockers found

The strict live evidence covers all design-required manual E2E scenarios:

```text
SCENARIO_RESULT cmd-q-restore PASS sessions_remain=4 markers_in_history=1 layout_shape=1;2,1 clients=1
SCENARIO_RESULT working-directory-inheritance PASS testdir=/tmp/ghostty-zmx-e2e-rerun-1781109829-cwd norm=/private/tmp/ghostty-zmx-e2e-rerun-1781109829-cwd
SCENARIO_RESULT pane-close-cleanup PASS closed=zmx-600001fe87e0-12e306c10-3117E235 unmanaged_alive=unmanaged-pane
SCENARIO_RESULT window-close-cleanup PASS closed_window_session=zmx-600003ce4f30-12493ba60-92387ABA open_session=zmx-600003ce18c0-124d2b2b0-8D07F156
SCENARIO_RESULT close-all-windows-cleanup PASS running=true old_count=2 new_count=1
SCENARIO_RESULT cmd-q-does-not-clean PASS remain=2 restored_windows=2
SCENARIO_RESULT reboot-scrollback-simulation PASS session=zmx-60000032d290-155f40120-A249EFB3 snapshot=/var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T//ghostty-zmx-e2e-rerun-1781109829/state/history/zmx-60000032d290-155f40120-A249EFB3.txt
SCENARIO_RESULT unmanaged-not-reaped PASS unmanaged_alive=unmanaged-final
```

The supervised run also restored the user's real files byte-for-byte:

```text
CONFIG_RESTORE_BYTE_FOR_BYTE=PASS
MANAGER_RESTORE_BYTE_FOR_BYTE=PASS
UNINSTALL_RESTORE_BYTE_FOR_BYTE=PASS
```

## Remaining non-blocking adversarial notes

The unresolved R2/R3 hardening items remain correctly tracked in `deferred.md` and are not new fix-now blockers given the strict live pass:

- `R2-E2E-ADV-1`: reboot scrollback failure-path hardening after `zmx run` failure.
- `R2-E2E-ADV-2`: stale restore-in-progress flag if a restore driver is killed mid-restore.
- `R2-E2E-ADV-3`: unsynchronized `sessions` mutations between attach and reaper cleanup.
- `R2-E2E-ADV-4`: positional parsing of current `zmx list` fields.

I did not find evidence that any of these deferred issues invalidates the passing v0.1 live E2E gate.

## Summary

The corrected cumulative E2E evidence is release-clean from the adversarial E2E perspective. The specific R3 false-positive hole is closed: Cmd-Q restore now must and did prove matching layout shape, all restored managed sessions attached with `clients=1`, markers present in `zmx history`, and no restore failure debug lines. No new E2E fix-now blocker remains.
