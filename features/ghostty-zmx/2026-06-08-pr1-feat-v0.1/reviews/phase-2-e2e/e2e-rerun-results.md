# E2E rerun supervised results

## Summary

A supervised E2E rerun was attempted with a safer harness:

- short `ZMX_DIR=/tmp/gzmx-84182`,
- `zmx print` marker injection instead of blocking `zmx run ... echo ...`,
- outer restore trap for Ghostty config and installed files,
- temporary `confirm-close-surface = false` in the managed block.

The run was stopped by the orchestrator because Scenario 1 did not progress beyond one managed session. The orchestrator restored the real Ghostty config and installed files from backups.

## Restoration hashes

```text
config restored:  d973fbe7bff3e640e7f6a582dabdfcfcd9ddf5f42b4707d83265a844781a9125
manager restored: f8c457d8e83e97571aa3900d869e7aff4a21ee96f65ffff886609a6e832b14e3
uninstall restored: 983b19d35997be05db7e414957b4243eb94fb4edd11607ce549f85aef6707444
```

## Evidence

The harness wrote its raw log to:

```text
/var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T/ghostty-zmx-e2e-rerun-1781106951/e2e.log
```

Key log excerpts:

```text
RUN_ID=ghostty-zmx-e2e-rerun-1781106951
CONFIG_HASH_BEFORE=d973fbe7bff3e640e7f6a582dabdfcfcd9ddf5f42b4707d83265a844781a9125
CONFIG_HASH_DURING=55f303765e74a6a00a66379196919eec23238ff344392e252ee529af9906a040
MANAGER_HASH_BEFORE=f8c457d8e83e97571aa3900d869e7aff4a21ee96f65ffff886609a6e832b14e3
MANAGER_HASH_DURING=99eb60333aa333460b657defb705f6bb2d573402d9a05c4eaadd4d6123999fdc
ZMX_DIR=/tmp/gzmx-84182

===== Scenario 1 Cmd-Q restore =====
terminal id 9CE269C3-0220-4A81-A6C0-1379E42570EA
140:167: execution error: Ghostty got an error: Can’t set selected tab of window to tab id "tab-157047560" of window id "tab-group-6000013cff00". (-10006)
window id tab-group-6000013ce640
```

Disposable sessions file remained at one session:

```text
zmx-6000013cff00-1573193d0-230735D0
```

Disposable id-map after attempted new window/surface creation:

```text
W 6000013ce640 6000013cff00
T 6000013ce640 157036d80 6000013cff00 1573193d0
```

Debug log showed the same Ghostty PID repeatedly electing a restore driver and restoring the same existing session after the first startup shell released `restore-${ghosttyPID}.lock`:

```text
2026-06-10T15:55:54Z restore-driver elected ghostty_pid=84251 flag=.../restore-84251.lock
2026-06-10T15:55:54Z restore sessions loaded count=1 file=.../data/sessions
2026-06-10T15:55:54Z restore first session=zmx-6000013cff00-1573193d0-230735D0 file=.../data/restore-first
2026-06-10T15:55:54Z restore-driver released ghostty_pid=84251 flag=.../restore-84251.lock
...
2026-06-10T15:56:26Z restore-driver elected ghostty_pid=84251 flag=.../restore-84251.lock
2026-06-10T15:56:26Z restore sessions loaded count=1 file=.../data/sessions
2026-06-10T15:56:26Z restore first session=zmx-6000013cff00-1573193d0-230735D0 file=.../data/restore-first
2026-06-10T15:56:26Z restore-driver released ghostty_pid=84251 flag=.../restore-84251.lock
...
2026-06-10T15:56:57Z restore-driver elected ghostty_pid=84251 flag=.../restore-84251.lock
2026-06-10T15:56:57Z restore sessions loaded count=1 file=.../data/sessions
2026-06-10T15:56:57Z restore first session=zmx-6000013cff00-1573193d0-230735D0 file=.../data/restore-first
```

## Finding

### E2E-IMPL-1 (high) — Restore-driver election is not one-shot per Ghostty process

**Where:** `session-manager.zsh` restore-driver election/release around `_ghostty_zmx_auto_attach`.

**What:** Releasing `restore-${ghosttyPID}.lock` after startup fixed stale locks across restarts, but it also allows every later shell in the same Ghostty process to become a restore driver. In the live E2E rerun, new split/tab/window shells repeatedly restored the existing first session instead of generating new per-surface session names. This prevents ordinary new surfaces from creating their own managed zmx sessions.

**Recommendation:** Add a per-Ghostty-process sentinel that records restore has already been attempted/completed for that Ghostty PID. The election lock can still be released to avoid stale lock issues, but subsequent shells in the same Ghostty process must skip `_ghostty_zmx_restore`, then proceed to queue pop or fresh session generation.

## Scenario status

- Cmd-Q restore: **BLOCKED** by `E2E-IMPL-1`.
- Remaining manual scenarios: **NOT RUN** after stopping the supervised rerun.
