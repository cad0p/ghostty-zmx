# R3 cumulative live E2E tester

## Verdict

PASS. The corrected cumulative check exercised the software through the live supervised Ghostty/zmx harness from outside Ghostty and outside any managed zmx session. All eight required end-user scenarios passed in the new run, the temporary close-confirmation override and installed-file replacements were restored byte-for-byte, and the shell test suite passed afterward.

## Scope and commands

Read before running:

- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/design.md`
- `docs/manual-e2e.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-supervisor.zsh`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md`

Live supervised harness run from the repository root:

```sh
/opt/local/bin/gtimeout --kill-after=30s 1200s \
  /bin/zsh features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-supervisor.zsh
```

The wrapper was only a timeout guard around a single live E2E process; no second concurrent broad live E2E process was started.

Harness exit status: `0`.

Primary generated evidence:

- Summary: `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-results.md`
- Full log: `/var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T//ghostty-zmx-e2e-rerun-1781109021/e2e.log`
- Wrapper log: `/tmp/ghostty-zmx-live-e2e-1781109021/stdout-stderr.log`

## Live E2E scenario results

The new run used disposable live state:

```text
DATA_HOME=/var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T//ghostty-zmx-e2e-rerun-1781109021/data
STATE_HOME=/var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T//ghostty-zmx-e2e-rerun-1781109021/state
ZMX_DIR=/tmp/gzmx-73642
```

All eight scenarios passed:

```text
SCENARIO_RESULT cmd-q-restore PASS sessions_remain=4 markers_in_history=1
SCENARIO_RESULT working-directory-inheritance PASS testdir=/tmp/ghostty-zmx-e2e-rerun-1781109021-cwd norm=/private/tmp/ghostty-zmx-e2e-rerun-1781109021-cwd
SCENARIO_RESULT pane-close-cleanup PASS closed=zmx-6000028853b0-142e14150-0309E691 unmanaged_alive=unmanaged-pane
SCENARIO_RESULT window-close-cleanup PASS closed_window_session=zmx-6000001c4750-123753dc0-5FDE3983 open_session=zmx-6000001f94d0-1241346b0-199FB308
SCENARIO_RESULT close-all-windows-cleanup PASS running=true old_count=2 new_count=1
SCENARIO_RESULT cmd-q-does-not-clean PASS remain=2 restored_windows=2
SCENARIO_RESULT reboot-scrollback-simulation PASS session=zmx-6000006c6640-14fe2b060-65C3E371 snapshot=/var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T//ghostty-zmx-e2e-rerun-1781109021/state/history/zmx-6000006c6640-14fe2b060-65C3E371.txt
SCENARIO_RESULT unmanaged-not-reaped PASS unmanaged_alive=unmanaged-final
```

Additional reboot-scrollback evidence in the full log showed both fresh-session detection and scrollback injection for the reboot simulation session:

```text
fresh-session detection session=zmx-6000006c6640-14fe2b060-65C3E371 exists=0 snapshot=...
zmx print restored scrollback session=zmx-6000006c6640-14fe2b060-65C3E371 file=...
```

The scenario itself also verified the exact reboot banner and marker in `zmx history <session>`, not merely in outer Ghostty scrollback.

## Restoration/hash checks

The harness temporarily installed the repository manager/uninstaller and replaced only the managed Ghostty config block with an automated-test override containing `confirm-close-surface = false`. It then restored real files through its exit path and verified hashes.

Recorded hashes and restoration checks:

```text
CONFIG_HASH_AFTER=d973fbe7bff3e640e7f6a582dabdfcfcd9ddf5f42b4707d83265a844781a9125
MANAGER_HASH_BEFORE=f8c457d8e83e97571aa3900d869e7aff4a21ee96f65ffff886609a6e832b14e3
MANAGER_HASH_AFTER=f8c457d8e83e97571aa3900d869e7aff4a21ee96f65ffff886609a6e832b14e3
UNINSTALL_HASH_BEFORE=983b19d35997be05db7e414957b4243eb94fb4edd11607ce549f85aef6707444
UNINSTALL_HASH_AFTER=983b19d35997be05db7e414957b4243eb94fb4edd11607ce549f85aef6707444
CONFIG_RESTORE_BYTE_FOR_BYTE=PASS
MANAGER_RESTORE_BYTE_FOR_BYTE=PASS
UNINSTALL_RESTORE_BYTE_FOR_BYTE=PASS
```

The live post-run filesystem hashes also matched the restored values:

```text
d973fbe7bff3e640e7f6a582dabdfcfcd9ddf5f42b4707d83265a844781a9125  ~/Library/Application Support/com.mitchellh.ghostty/config.ghostty
f8c457d8e83e97571aa3900d869e7aff4a21ee96f65ffff886609a6e832b14e3  ~/.config/ghostty-zmx/session-manager.zsh
983b19d35997be05db7e414957b4243eb94fb4edd11607ce549f85aef6707444  ~/.config/ghostty-zmx/uninstall.sh
```

## Shell test suite after live run

After the live harness completed and restored files, I ran the shell/static suite:

```sh
/bin/zsh -n session-manager.zsh install.sh uninstall.sh
/bin/zsh tests/install-uninstall.zsh
/bin/zsh tests/release-control.zsh
/bin/zsh tests/restore-id-map.zsh
/bin/zsh tests/snapshot-scrollback.zsh
```

Results:

```text
PASS zsh -n session-manager.zsh install.sh uninstall.sh
PASS tests/install-uninstall.zsh
PASS tests/release-control.zsh
PASS tests/restore-id-map.zsh
PASS tests/snapshot-scrollback.zsh
```

Logs:

- Syntax log: `/tmp/ghostty-zmx-syntax-1781109251.log`
- Shell test log: `/tmp/ghostty-zmx-shell-tests-1781109195.log`

## Findings

None.

## Notes

- The harness did not hang, so no manual backup restoration was required beyond the harness's own successful trap/final restore path.
- The live log includes transient Ghostty AppleScript restore/layout diagnostics while exercising real UI surfaces, but the supervised harness's scenario assertions still passed and restoration checks passed.
- I did not edit production code.
