# R4 cumulative live E2E tester

## Verdict

PASS. This corrected cumulative E2E run used the live supervised Ghostty/zmx harness after the restore-layout fix and stricter Cmd-Q assertions. It exercised the software through real Ghostty windows/tabs/splits and zmx sessions from outside Ghostty/zmx.

## Live run

Command:

```sh
/opt/local/bin/gtimeout --kill-after=30s 1200s \
  zsh features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-supervisor.zsh
```

Artifacts:

- Summary: `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-results.md`
- Full log: `/var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T//ghostty-zmx-e2e-rerun-1781109829/e2e.log`

## Scenario results

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

## Strengthened Cmd-Q restore assertions

The harness now requires the Cmd-Q restore scenario to prove:

- all original managed sessions still exist,
- each marker is present in `zmx history <session>` after reopen,
- the restored logical layout shape matches the pre-quit shape,
- every recorded managed session reports `clients=1`,
- no `restore failed step=` debug lines occurred during the scenario.

The successful run reported:

```text
layout_shape=1;2,1 clients=1 markers_in_history=1
```

## Restoration/hash checks

The supervised harness temporarily replaced only the managed Ghostty config block and installed the branch manager/uninstaller for live shells. It then restored the real files and verified hashes:

```text
CONFIG_HASH_AFTER=d973fbe7bff3e640e7f6a582dabdfcfcd9ddf5f42b4707d83265a844781a9125
MANAGER_HASH_AFTER=f8c457d8e83e97571aa3900d869e7aff4a21ee96f65ffff886609a6e832b14e3
UNINSTALL_HASH_AFTER=983b19d35997be05db7e414957b4243eb94fb4edd11607ce549f85aef6707444
CONFIG_RESTORE_BYTE_FOR_BYTE=PASS
MANAGER_RESTORE_BYTE_FOR_BYTE=PASS
UNINSTALL_RESTORE_BYTE_FOR_BYTE=PASS
```

## Findings

None.

## Summary

The live E2E gate passes with the corrected strict assertions. This supersedes the earlier static-only cumulative report and the earlier live report that did not assert layout/client invariants.
