## Findings

### E2E-BLOCKER-001 (high) — Live E2E run was stopped after `zmx run ... echo ...` stalled during Cmd-Q marker setup
**Where:** `docs/manual-e2e.md:13`, `docs/manual-e2e.md:28`

**What:** The manual Cmd-Q restore scenario requires unique markers in each surface and later verification via `zmx history <session>`. I attempted to automate marker insertion from outside Ghostty with commands of this form:

```sh
zmx run "$session" echo "ghostty-zmx-e2e-1781105930-cmdq-$session"
```

The current live run was stopped by the orchestrator while stuck in `/tmp/ghostty-zmx-e2e-run.zsh` on this `zmx run ... echo ...` step. The orchestrator terminated PID `66363` and child `69453` and restored the real Ghostty config and installed manager from backups.

Captured diagnostic output before the stop included:

```text
RUN_ID=ghostty-zmx-e2e-1781105930
CONFIG_HASH_BEFORE=d973fbe7bff3e640e7f6a582dabdfcfcd9ddf5f42b4707d83265a844781a9125
CONFIG_HASH_DURING=9795e8f7ec46e95994923bc735bfcb119ed356499caa6414ed63a94a6906dc49
DATA_HOME=/var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T//ghostty-zmx-e2e-1781105930/data
STATE_HOME=/var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T//ghostty-zmx-e2e-1781105930/state
ZMX_DIR=/tmp/gzmx-66363
INSTALLED_MANAGER_HASH=99eb60333aa333460b657defb705f6bb2d573402d9a05c4eaadd4d6123999fdc REPO_MANAGER_HASH=99eb60333aa333460b657defb705f6bb2d573402d9a05c4eaadd4d6123999fdc
```

The same log showed Ghostty AppleScript diagnostics while building the test layout:

```text
Ghostty got an error: Can’t set selected tab of window to tab id "tab-145066a20" of window id "tab-group-600001768750". (-10006)
Ghostty got an error: Can’t set index of window id "tab-group-600001761560" to 1. (-10006)
```

Because the run was stopped mid-scenario, I did not continue to execute live Ghostty/zmx commands and did not complete any of the eight manual scenarios to a reliable PASS.

**Recommendation:** Treat this E2E run as blocked/inconclusive, not as evidence that Cmd-Q restore itself fails. For the next live run, avoid blocking `zmx run` marker injection against attached interactive sessions; prefer a fire-and-forget `zmx send` marker with bounded polling, or enter markers manually in Ghostty surfaces. Also avoid AppleScript focus/index operations that can fail non-deterministically while Ghostty is creating surfaces.

### E2E-BLOCKER-002 (high) — Initial disposable `ZMX_DIR` path made generated v0.1 session names exceed zmx socket-name limits
**Where:** `session-manager.zsh:848`, `session-manager.zsh:850`

**What:** In an earlier aborted harness attempt, I isolated zmx with a long disposable socket directory under the macOS temp folder. The generated managed session name was valid for ghostty-zmx, but zmx rejected it because the long socket directory left too little socket path budget:

```text
error: session name is too long (35 bytes, max 22 for socket directory "/var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T//ghostty-zmx-e2e-1781105532/zmx")
```

This blocked reliable live assertions in that attempt. The implementation attaches generated sessions in `session-manager.zsh:850`, and the current v0.1 session identity intentionally uses full Ghostty window/tab hex portions plus an eight-character terminal component, so long disposable zmx socket paths are unsafe for E2E isolation.

**Recommendation:** Use a very short disposable `ZMX_DIR` such as `/tmp/gzmx-<pid>` for future automated E2E, or document that the E2E harness must keep the zmx socket directory short enough for generated `zmx-<window>-<tab>-<pane>` names.

### E2E-BLOCKER-003 (medium) — Temporary config override and installed-manager replacement were required and were restored externally
**Where:** `docs/manual-e2e.md:130`, `docs/manual-e2e.md:140`, `docs/manual-e2e.md:147`

**What:** Per the manual E2E instructions, I temporarily replaced only the managed Ghostty block with an automated-test block containing `confirm-close-surface = false`. I also temporarily installed the repository `session-manager.zsh` into `$HOME/.config/ghostty-zmx/session-manager.zsh` so live Ghostty shells would execute the branch under review. The current run recorded:

```text
CONFIG_HASH_BEFORE=d973fbe7bff3e640e7f6a582dabdfcfcd9ddf5f42b4707d83265a844781a9125
CONFIG_HASH_DURING=9795e8f7ec46e95994923bc735bfcb119ed356499caa6414ed63a94a6906dc49
INSTALLED_MANAGER_HASH=99eb60333aa333460b657defb705f6bb2d573402d9a05c4eaadd4d6123999fdc
REPO_MANAGER_HASH=99eb60333aa333460b657defb705f6bb2d573402d9a05c4eaadd4d6123999fdc
```

After the live run stuck, the orchestrator explicitly restored both the real Ghostty config and installed manager from backups. I did not run further live Ghostty/zmx commands after that stop instruction. An earlier completed harness attempt did verify a byte-for-byte config restore with:

```text
CONFIG_HASH_AFTER=d973fbe7bff3e640e7f6a582dabdfcfcd9ddf5f42b4707d83265a844781a9125
CONFIG_RESTORE_BYTE_FOR_BYTE=PASS
```

**Recommendation:** Keep the temporary close-confirmation override requirement. For future runs, log both config and installed-manager before/during/after hashes, and perform restoration in a minimal wrapper that is independent of the E2E scenario process.

## Manual E2E scenario status

- Cmd-Q restore: **BLOCKED/INCONCLUSIVE**. Layout creation began, but marker insertion via `zmx run ... echo ...` stalled and the run was stopped.
- Working-directory inheritance: **NOT COMPLETED** after stop instruction.
- Pane close cleanup: **NOT COMPLETED** after stop instruction.
- Window close cleanup: **NOT COMPLETED** after stop instruction.
- Close all windows cleanup: **NOT COMPLETED** after stop instruction.
- Cmd-Q does not clean: **NOT COMPLETED** after stop instruction.
- Reboot scrollback simulation: **NOT COMPLETED** after stop instruction. The implementation path to check later is `session-manager.zsh:186` (`zmx run "$session" true`) followed by `session-manager.zsh:190` (`zmx print "$session"`).
- Unmanaged sessions are not reaped: **NOT COMPLETED** after stop instruction.

## Commands attempted

```sh
# Required static/shell test suite; completed successfully with no output.
zsh -n session-manager.zsh install.sh uninstall.sh
zsh tests/install-uninstall.zsh
zsh tests/snapshot-scrollback.zsh
zsh tests/restore-id-map.zsh
zsh tests/release-control.zsh

# Environment/config inspection before live E2E.
git status --short --branch
command -v zmx
zmx --version
osascript -e 'tell application "Ghostty" to get version'
shasum -a 256 "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"

# Live E2E harness attempts from outside Ghostty/zmx.
zsh /tmp/ghostty-zmx-e2e-run.zsh
```

The first harness attempt reached a full cleanup path and restored the real Ghostty config hash to `d973fbe7bff3e640e7f6a582dabdfcfcd9ddf5f42b4707d83265a844781a9125`, but it used an overly long disposable `ZMX_DIR` and produced zmx session-name/socket-length failures. The second harness attempt used short `ZMX_DIR=/tmp/gzmx-66363` but was stopped while stuck on `zmx run ... echo ...` during Cmd-Q marker setup.

## Well-maintained areas

- The shell/static test suite completed successfully with the required commands.
- The implementation contains explicit reboot scrollback restore primitives: fresh-session creation with `zmx run "$session" true` and display injection with `zmx print "$session"` at `session-manager.zsh:186` and `session-manager.zsh:190`.
- The implementation emits debug strings useful for future E2E verification, including fresh-session detection and zmx print restore events at `session-manager.zsh:187`, `session-manager.zsh:191`, and `session-manager.zsh:193`.

## Summary

Phase 2 live E2E did not converge. The required shell tests passed, and the automated close-confirmation override was applied with recorded before/during hashes. However, the current live run became unsafe to continue because the harness stalled on `zmx run ... echo ...` while preparing Cmd-Q markers. Per maintainer steering, no further live Ghostty/zmx commands were run. The orchestrator restored the real Ghostty config and installed manager from backups. The report should be treated as a partial E2E/blocker report, with all eight manual scenarios still requiring a safe rerun.
