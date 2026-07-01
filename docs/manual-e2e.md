# Manual E2E checklist

Run these checks from iTerm2 or another terminal outside managed Ghostty and outside any zmx session. Do not run the orchestrating shell inside Ghostty, because several checks quit or close Ghostty surfaces.

Use disposable marker text for every scenario, for example:

```sh
MARKER="ghostty-zmx-e2e-$(date +%s)"
```

Before testing, confirm the installed Ghostty config contains the managed production block with `confirm-close-surface = true` unless a scenario explicitly says to use a temporary automated-test override.

## Cmd-Q restore

1. Open Ghostty with ghostty-zmx installed.
2. Create multiple windows, tabs, and splits.
3. In each surface, print a unique marker and record `echo $ZMX_SESSION` or `zmx list` output.
4. Press Cmd-Q to quit Ghostty.
5. Wait longer than `GHOSTTY_ZMX_REAPER_INTERVAL`.
6. Verify recorded sessions still exist and are not unlogged:

   ```sh
   zmx list --short
   cat "${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx/sessions"
   ```

7. Reopen Ghostty.
8. Verify the same layout shape returns, each restored session has a client, and each marker appears in `zmx history <session>`.

## Create new window after restore

1. Temporarily use the automated-test override `confirm-close-surface = false`; restore the production value after the scenario.
2. Start from clean managed state or record the exact initial sessions file.
3. Create a base layout such as one window with two tabs where the second tab has one split. Expected shape: `1,2`.
4. Record every managed session and print a unique marker in each one.
5. Press Cmd-Q, reopen Ghostty, and wait until restore is complete.
6. Verify the restored shape is still `1,2`, the sessions file still has the same session count, and each recorded session has exactly `clients=1`.
7. Create one new Ghostty window after restore.
8. Verify this adds exactly one window and one managed session. The valid shape is order-insensitive: `1;1,2` or `1,2;1`.
9. Verify all pre-existing sessions still have exactly `clients=1`; no old session should gain extra clients.
10. Press Cmd-Q again, reopen Ghostty, and verify the two-window shape and four-session count are preserved without duplicating the restored layout.

## Working-directory inheritance observation

1. In a managed Ghostty session, create and enter a unique local directory:

   ```sh
   TESTDIR="/tmp/ghostty-zmx-cwd-$(date +%s)"
   mkdir -p "$TESTDIR"
   cd "$TESTDIR"
   pwd
   ```

2. Create a new split from the active terminal and verify its shell starts in the same directory.
3. Create a new tab from the active terminal and verify the same.
4. Create a new window from the active terminal and verify the same.
5. Note that `/tmp` may appear as `/private/tmp` on macOS.
6. Do not test SSH/remote inheritance as a v0.1 feature; remote support is deferred.

## Pane close cleanup

1. Create a split and record its managed session name.
2. Close only that pane through Ghostty.
3. Wait for the reaper interval.
4. Verify the recorded session is gone from `zmx list --short` and from the ghostty-zmx sessions file.
5. Unmanaged-session preservation is covered in the dedicated scenario below.

## Window close cleanup

1. Create at least two Ghostty windows.
2. In one window, create one or more managed sessions and record their names.
3. Close that window while another Ghostty window remains open.
4. Wait for the reaper interval.
5. Verify all sessions from the closed window are killed and removed from the sessions file.
6. Verify sessions from the still-open window remain attached.

## Close all windows cleanup

1. Ensure `quit-after-last-window-closed = true` is not set.
2. Create two Ghostty windows and record all managed session names.
3. Close both windows one by one without pressing Cmd-Q.
4. Verify Ghostty remains running with zero windows.
5. Wait for `GHOSTTY_ZMX_ZERO_WINDOWS_GRACE` plus one reaper interval.
6. Verify all recorded managed sessions are killed and removed from the sessions file.
7. Reopen Ghostty and verify it starts one fresh managed session rather than rebuilding the old layout.

## Cmd-Q does not clean

1. Create two Ghostty windows and record managed session names.
2. Press Cmd-Q.
3. Wait longer than `GHOSTTY_ZMX_ZERO_WINDOWS_GRACE`.
4. Verify sessions remain in `zmx list --short` and in the ghostty-zmx sessions file.
5. Reopen Ghostty and verify both windows restore.

## Close one window, then Cmd-Q

1. Temporarily use the automated-test override `confirm-close-surface = false`; restore the production value after the scenario.
2. Create two Ghostty windows, for example one `1,2` window and one single-terminal window.
3. Close exactly one window and wait until only the remaining window's sessions are present in the sessions file.
4. Press Cmd-Q using the actual keyboard shortcut path, not `tell application "Ghostty" to quit`.
5. Reopen Ghostty.
6. Verify only the remaining window restores, the closed window does not reappear, the sessions file count matches the remaining layout, and all managed sessions have `clients=1`.

## Close one split, then Cmd-Q

1. Temporarily use the automated-test override `confirm-close-surface = false`; restore the production value after the scenario.
2. Create a layout with at least one split, for example one window with two tabs where the second tab has two terminals (`1,2`).
3. Record all managed sessions and print a marker in the split that will be closed.
4. Close one split and immediately press Cmd-Q using the actual keyboard shortcut path.
5. Reopen Ghostty.
6. Verify the closed split does not reappear, the sessions file no longer contains the closed split's session, the remaining layout shape matches the surviving terminals (for example `1,1`), and all remaining managed sessions have `clients=1`.

## Reboot scrollback simulation

1. In a managed Ghostty session, print a unique marker.
2. Press Cmd-Q so the reaper snapshots scrollback.
3. Verify the snapshot file exists:

   ```sh
   ls "${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-zmx/history"
   ```

4. Simulate zmx daemon/session loss for the recorded session with `zmx kill <session>`. If testing full daemon loss, use a disposable zmx socket directory only.
5. Reopen Ghostty.
6. Verify ghostty-zmx creates a fresh zmx session before printing saved text. Debug logs should show fresh-session detection and zmx print restore events when `GHOSTTY_ZMX_DEBUG=1` is enabled.
7. Verify `zmx history <session>` contains both the exact banner and the unique marker:

   ```text
   [ghostty-zmx restored saved scrollback from a previous boot; process state was not restored]
   ```

8. Confirm the marker appears inside zmx history, not merely in the outer Ghostty scrollback.

## Unmanaged sessions are not reaped

1. From iTerm2, create an unmanaged zmx session:

   ```sh
   zmx run ghostty-zmx-unmanaged-e2e true
   ```

2. Open and close Ghostty panes/windows managed by ghostty-zmx.
3. Verify `ghostty-zmx-unmanaged-e2e` remains alive unless explicitly killed by the user.
4. Clean up:

   ```sh
   zmx kill ghostty-zmx-unmanaged-e2e
   ```

## Remote multi-client projection

These scenarios require the Ubuntu 24.04 Docker sshd fixture (`ghostty-zmx-sshd-fixture`, port 2222, zmx 0.6.0, `ghostty-zmx-remote-layout` helper installed) and `Ghostty-tip` (1.4.0+ `pid`/`tty` capability). Run them from iTerm2, not from inside a managed Ghostty pane.

### Fixture one-time setup

```sh
# ssh config alias
cat /tmp/ghostty-zmx-fixture-sshconfig
# → Host gzmx-fixture  HostName 127.0.0.1  Port 2222  User gzmx  IdentityFile /tmp/ghostty-zmx-docker-fixture/id_ed25519

# verify
ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'zmx version | tr "\t" " " | head -1; ls ~/.config/ghostty-zmx/ghostty-zmx-remote-layout'
```

### Clean state before each scenario

```sh
pkill -9 -f Ghostty-tip 2>/dev/null; sleep 1
rm -rf /var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T/ghostty-zmx-501
rm -rf ~/Library/Saved\ Application\ State/com.mitchellh.ghostty.tip.savedState
ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'rm -f ~/.local/share/ghostty-zmx/remote-layout ~/.local/share/ghostty-zmx/remote-layout.rev; rmdir ~/.local/share/ghostty-zmx/remote-layout.lock 2>/dev/null; pkill zmx 2>/dev/null'
# verify no orphaned pollers
lsof ~/.config/ghostty-zmx/session-manager.zsh   # must be empty
```

### No-prompt harness (client launch)

```sh
TMPDATA=$(mktemp -d /tmp/gzmx-e2e-XXXXXX)
TMPSTATE=$(mktemp -d /tmp/gzmx-e2e-state-XXXXXX)
open -na /Applications/Ghostty-tip.app --args \
  --env=GHOSTTY_ZMX_AUTO_ATTACH=1 \
  --env=GHOSTTY_ZMX_DEBUG=1 \
  --env=GHOSTTY_ZMX_DATA_HOME="$TMPDATA" \
  --env=GHOSTTY_ZMX_STATE_HOME="$TMPSTATE" \
  --window-save-state=never \
  --confirm-close-surface=false
```

Do **not** use `-e /bin/zsh -il` (triggers the macOS "Allow Ghostty to Execute /bin/zsh" prompt). Do **not** use AppleScript `new window with configuration cfg` for the first local shell (produces `pid=0`/empty-tty surfaces).

### Client B projects client A's `present` row (sequential)

1. Pre-seed a server `present` row simulating client A having created a remote session:

   ```sh
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture \
     '$HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout add wsAA winAA tabAA paneA1 gzr-AA-winAA-tabAA-paneA1 - root 1 present'
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture \
     '$HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout read'
   ```

2. Pre-seed client B's `remote-hosts` so its poller knows the transport:

   ```sh
   printf 'gzmx-fixture\tssh\t0.6.0\tactive\tssh -t -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture\n' \
     > "$TMPDATA/remote-hosts"
   ```

3. Launch Ghostty-tip as client B (no-prompt harness above) and wait ~5s.
4. Verify **exactly one** projection opened with **no multiplication**:

   ```sh
   osascript -e 'tell application "Ghostty-tip" to count of windows'   # expect 2 (local + projection)
   pgrep -fl 'zmx attach gzr' | wc -l                                       # expect 1
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'zmx list | grep gzr | grep clients'
   # expect clients=1
   cat "$TMPDATA/remote-projections"   # expect one attached row
   ```

5. Verify the poller debug log shows the reconcile/open/adopt sequence:

   ```sh
   grep poller "$TMPSTATE/debug.log" | tail
   # expect: reconcile opening → poller opened → poller adopted
   ```

### Server `deleted` removes a client's projection

1. From the previous scenario (client B has an `attached` projection), transition the server row to `deleted` (simulating another client closing it):

   ```sh
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture \
     '$HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout transition gzr-AA-winAA-tabAA-paneA1 deleted'
   ```

2. Wait one poller interval (~5s, `GHOSTTY_ZMX_REMOTE_POLL_INTERVAL` default 3s).
3. Verify the local projection was removed and the ssh killed:

   ```sh
   cat "$TMPDATA/remote-projections"              # expect empty/gone
   pgrep -fl 'zmx attach gzr' | wc -l              # expect 0
   grep 'server-removed' "$TMPSTATE/debug.log" | tail
   # expect: poller server-removed state=deleted
   ```

4. The projection surface is left as a `pid=0` empty window (cosmetic; close with Cmd-W) — this is consistent with v0.1 pane-close behavior.

### Pass criteria

- Window delta = 1 (exactly one projection, no multiplication).
- Exactly one local ssh process per `gzr` session.
- Server `clients=1` after projection, `clients=0` after kill.
- `remote-projections` shows one `attached` row, removed on server `deleted`.
- No orphaned poller shells after Ghostty-tip exits (`lsof ~/.config/ghostty-zmx/session-manager.zsh` empty).

### Known limitation

True simultaneous two-Ghostty-client E2E is not possible with a single coinstalled `Ghostty-tip` bundle (same AppleScript app name). Sequential A/B testing is the accepted v0.2 procedure; see `changelog/2026-06-30-v0-2-simultaneous-multiclient-e2e-gap.md`.

## Automated-test config override

Automated tests may use a disposable or temporary Ghostty config that sets `confirm-close-surface = false` for close scenarios. Harnesses that touch the real Ghostty config must restore it byte-for-byte on every exit path and fail if the restored file differs from the original.

Never leave `confirm-close-surface = false` in the production managed block after automated tests.
