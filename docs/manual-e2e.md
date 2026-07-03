# Manual E2E checklist

Run these checks from iTerm2 or another terminal outside managed Ghostty and outside any zmx session. Do not run the orchestrating shell inside Ghostty, because several checks quit or close Ghostty surfaces.

**Always use a disposable `GHOSTTY_ZMX_DATA_HOME` / `GHOSTTY_ZMX_STATE_HOME`** (tmpdirs) when launching Ghostty-tip for E2E. Never `rm` or overwrite files under your real `~/.local/share/ghostty-zmx/` or `~/.local/state/ghostty-zmx/` as test cleanup — this destroys your real `remote-hosts` and breaks reopen. See "Clean state before each scenario" below for the safe isolation pattern.

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

**Always run E2E with a disposable `GHOSTTY_ZMX_DATA_HOME` / `GHOSTTY_ZMX_STATE_HOME`** (see the no-prompt harness below). Never `rm` or overwrite files under your real `~/.local/share/ghostty-zmx/` or `~/.local/state/ghostty-zmx/` as test cleanup — doing so destroys your real `remote-hosts`, `remote-projections`, and `sessions` state. A prior E2E run that ran `rm -f ~/.local/share/ghostty-zmx/remote-hosts` as "cleanup" deleted the user's real host config, which silently broke Cmd-Q+reopen (the poller only starts if `remote-hosts` exists). The disposable-`DATA_HOME` harness isolates all test state in a tmpdir that can be `rm -rf`'d safely.

The only real-path cleanup that is safe is the runtime tmpdir (orphaned pollers/reapers) and the macOS saved-state:

```sh
pkill -9 -f Ghostty-tip 2>/dev/null; sleep 1
rm -rf /var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T/ghostty-zmx-501
rm -rf ~/Library/Saved\ Application\ State/com.mitchellh.ghostty.tip.savedState
# Fixture server state (disposable Docker container, safe to wipe):
ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'rm -f ~/.local/share/ghostty-zmx/remote-layout ~/.local/share/ghostty-zmx/remote-layout.rev; rmdir ~/.local/share/ghostty-zmx/remote-layout.lock 2>/dev/null; pkill zmx 2>/dev/null'
# verify no orphaned pollers
lsof ~/.config/ghostty-zmx/session-manager.zsh   # must be empty
```

If you must test against your real `DATA_HOME` (e.g. to reproduce a user-reported issue with real state), back up `remote-hosts` first and restore it on exit:

```sh
cp ~/.local/share/ghostty-zmx/remote-hosts /tmp/remote-hosts.bak
# ... run E2E ...
cp /tmp/remote-hosts.bak ~/.local/share/ghostty-zmx/remote-hosts
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

### Local pane close triggers the server close transaction

This verifies that closing a remote pane (Cmd-W, which kills the local ssh) triggers the full server-side `present -> closing -> zmx kill -> deleted` transaction, so the remote zmx session is killed and other clients see the deletion.

1. Set up a projected remote session as in the multi-client scenario above (pre-seed a server `present` row + `remote-hosts`, launch Ghostty-tip, wait for `attached`).
2. Record the projection pid and kill it to simulate pane close:

   ```sh
   PROJ_PID=$(awk -F '\t' '/gzr-/ {print $5; exit}' "$TMPDATA/remote-projections")
   kill "$PROJ_PID"; sleep 0.3
   pkill -f "zmx attach gzr-" 2>/dev/null
   sleep 8
   ```

3. Verify the server close transaction ran and the remote session was killed:

   ```sh
   grep 'close-txn\|server-removed' "$TMPSTATE/debug.log" | tail
   # expect: poller close-txn ... pid=<PROJ_PID>
   #         poller server-removed state=deleted
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture \
     '$HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout read'
   # expect: the row is state=deleted
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'zmx list' | grep gzr || echo none
   # expect: none (remote zmx session killed)
   cat "$TMPDATA/remote-projections" 2>/dev/null   # expect empty/gone
   ```

4. The projection surface is left as a `pid=0` empty window (cosmetic; close with Cmd-W).

### Cmd-Q preserves the remote session

This verifies that quitting Ghostty (Cmd-Q) does **not** trigger the server close transaction — the remote zmx session survives for re-attach on reopen.

1. Set up a projected remote session as above (pre-seed + launch, wait for `attached`).
2. Quit Ghostty-tip (kill the app process, simulating Cmd-Q):

   ```sh
   pkill -f "Ghostty-tip"; sleep 6
   ```

3. Verify the remote session survived and the poller exited cleanly:

   ```sh
   tail "$TMPSTATE/debug.log" | grep -E 'stopped|close-txn'
   # expect: poller stopped reason=ghostty-exit (and NO close-txn line)
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture \
     '$HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout read'
   # expect: the row is still state=present
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'zmx list' | grep gzr
   # expect: clients=0 (session survived, detached)
   lsof ~/.config/ghostty-zmx/session-manager.zsh   # expect empty (no orphaned pollers)
   ```

### Pass criteria

- Window delta = 1 (exactly one projection, no multiplication).
- Exactly one local ssh process per `gzr` session.
- Server `clients=1` after projection, `clients=0` after kill.
- `remote-projections` shows one `attached` row, removed on server `deleted`.
- Local pane close: server row -> `deleted`, remote zmx session killed.
- Cmd-Q: server row stays `present`, remote zmx session survives `clients=0`.
- No orphaned poller shells after Ghostty-tip exits (`lsof ~/.config/ghostty-zmx/session-manager.zsh` empty).

### Idempotence stress (delete projection row while ssh lives)

This verifies the poller repairs a lost local projection row by adopting the live ssh rather than opening a duplicate.

1. Set up a projected remote session as in the multi-client scenario (pre-seed + launch, wait for `attached`).
2. Delete the local `remote-projections` row (simulating local state loss) while keeping the live ssh and server row intact:

   ```sh
   rm -f "$TMPDATA/remote-projections"
   sleep 8
   ```
3. Verify the poller repaired the row without opening a duplicate:

   ```sh
   # exactly one ssh child (count by comm==ssh to avoid the login/wrapper parent)
   ps -eo pid,ppid,comm,args | awk '$3=="ssh" && /zmx attach gzr-/{cnt++} END{print cnt+0}'  # expect 1
   cat "$TMPDATA/remote-projections"   # expect one attached row, same pid as before
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'zmx list | grep gzr | grep clients'  # expect clients=1
   grep adopted "$TMPSTATE/debug.log" | tail   # expect poller adopted
   ```

4. The window count must not increase (no duplicate projection).

### Widget handoff via AppleScript input injection

`input text` + `send key "enter"` **does** trigger the zle `accept-line` widget (the prior claim that it doesn't was test contamination from the orphaned-poller era). This enables end-to-end handoff E2E without pre-seeding:

```sh
osascript <<'OSA'
tell application "Ghostty-tip"
  input text "ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture" to focused terminal of selected tab of front window
  send key "enter" to focused terminal of selected tab of front window
end tell
OSA
sleep 8
```

Verify the same as the multi-client scenario: `delta=1`, one ssh, `clients=1`, one `attached` row.

### Remote split/tab inheritance (native split)

This verifies that a native Ghostty split from a remote projection window inherits the remote context: the new split pane runs the `.zprofile` early hook, execs a projection wrapper **before `.zshrc`**, and attaches to a **new** remote zmx session.

1. Set up a projected remote session via the widget handoff above (wait for `attached`, `clients=1`).
2. Trigger a native split on the projection window:

   ```sh
   osascript <<'OSA'
   tell application "Ghostty-tip"
     split (focused terminal of selected tab of front window) direction down
   end tell
   OSA
   sleep 10
   ```

3. Verify the split pane inherited the remote context and attached to a new session:

   ```sh
   osascript -e 'tell application "Ghostty-tip" to count of terminals of every tab of every window'  # expect 3 (original proj + split proj + local)
   ps -eo pid,ppid,comm,args | awk '$3=="ssh" && /zmx attach gzr-/{cnt++} END{print cnt+0}'  # expect 2
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'zmx list | grep gzr | grep clients'  # expect two clients=1
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture '$HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout read'  # expect 2 present rows
   cat "$TMPDATA/remote-projections"   # expect 2 attached rows
   grep inherit "$TMPSTATE/debug.log" | tail  # expect early-inherit match + inherit exec
   ```

4. Verify the split did **not** source the local `.zshrc`: temporarily add a harmless marker near the top of local `.zshrc` (for example `print -r -- LOCAL_ZSHRC_MARKER >> /tmp/gzmx-zshrc-marker`) before the test, then confirm the marker count does not increase when the remote split is created. Ordinary local panes should still source `.zshrc` normally.

5. The split pane must stay open (not close after ~1s). The new session shares the same workspace/window id but has a distinct pane id.

### Known limitations

**Simultaneous multi-client E2E** — True simultaneous two-Ghostty-client E2E is not possible with a single coinstalled `Ghostty-tip` bundle (same AppleScript app name). Sequential A/B testing is the accepted v0.2 procedure; see `changelog/2026-06-30-v0-2-simultaneous-multiclient-e2e-gap.md`.

**Split axis fidelity** — Ghostty 1.4 AppleScript exposes terminal `pid`/`tty` but not per-terminal frame, parent, or split direction. Native remote-split inheritance therefore still records `axis=horizontal` for same-tab splits. The `.zprofile` early inherit hook fixes the local `.zshrc` terminal-query leak by execing before `.zshrc`, but exact horizontal-vs-vertical restore requires an upstream Ghostty action that can create `new_split` with a per-surface `command` argument.

### Remote reboot scrollback restore

This verifies that if a remote zmx session is lost (remote host rebooted, zmx daemon gone) and a local scrollback snapshot exists, ghostty-zmx injects the saved scrollback into a fresh remote session before attaching.

1. Set up a projected remote session as in the multi-client scenario (pre-seed + launch, wait for `attached`). Use the direct binary launch if `open -na` produces zero windows:

   ```sh
   /Applications/Ghostty-tip.app/Contents/MacOS/Ghostty-tip \
     --env=GHOSTTY_ZMX_AUTO_ATTACH=1 \
     --env=GHOSTTY_ZMX_DEBUG=1 \
     --env=GHOSTTY_ZMX_DATA_HOME="$TMPDATA" \
     --env=GHOSTTY_ZMX_STATE_HOME="$TMPSTATE" \
     --window-save-state=never \
     --confirm-close-surface=false &
   ```

2. Focus the projection window and type a unique marker via input injection:

   ```sh
   osascript <<'OSA'
   tell application "Ghostty-tip"
     activate window 2
   end tell
   OSA
   sleep 1
   osascript <<'OSA'
   tell application "Ghostty-tip"
     input text "echo $MARKER" to focused terminal of selected tab of front window
     send key "enter" to focused terminal of selected tab of front window
   end tell
   OSA
   sleep 3
   ```

3. Verify the marker is in the remote scrollback:

   ```sh
   gtimeout 8 ssh -T -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "zmx history $SESSION 2>/dev/null" | grep -q "$MARKER"
   ```

4. Cmd-Q (kill the Ghostty-tip binary only — do NOT `pkill -f Ghostty-tip`, which would kill the poller before it snapshots). Wait for the poller to detect the exit and snapshot:

   ```sh
   kill -9 $GHOSTPID
   sleep 10
   ```

5. Verify the snapshot file exists and contains the marker:

   ```sh
   SNAP="$TMPSTATE/history/gzmx-fixture/${SESSION}.txt"
   [[ -s "$SNAP" ]] && grep -q "$MARKER" "$SNAP"
   grep 'remote snapshot' "$TMPSTATE/debug.log" | tail
   ```

6. Simulate remote reboot by killing the remote zmx session (the server `remote-layout` row stays `present`):

   ```sh
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "zmx kill $SESSION"
   ```

7. Reopen Ghostty-tip (direct binary launch). The poller re-projects; the `ghostty-zmx` wrapper detects the missing remote session, creates a fresh one via `zmx run`, and injects the banner + saved scrollback via base64 + `zmx print`:

   ```sh
   pkill -9 -f "remote-poller" 2>/dev/null   # clear the old poller
   rm -rf /var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T/ghostty-zmx-501
   /Applications/Ghostty-tip.app/Contents/MacOS/Ghostty-tip ... &
   sleep 14
   ```

8. Verify the fresh session has both the banner and the marker in `zmx history`:

   ```sh
   gtimeout 8 ssh -T -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "zmx history $SESSION 2>/dev/null" | grep -q "restored saved scrollback"
   gtimeout 8 ssh -T -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "zmx history $SESSION 2>/dev/null" | grep -q "$MARKER"
   grep 'reboot-restore' "$TMPSTATE/debug.log" | tail
   ```

#### Pass criteria

- Snapshot file created on Cmd-Q (`history/<host>/<session>.txt`) with the marker.
- On reopen, the wrapper logs `reboot-restore session missing — creating fresh + injecting`.
- Remote `zmx history` contains both the banner (`[ghostty-zmx restored saved scrollback...]`) and the marker.
- The projection re-attaches (`clients=1`).
- Intentional pane close still runs the close transaction (`present → closing → kill → deleted`) after the first poll cycle (`startup_grace` does not block genuine pane closes).

### Server installer (install-server.sh)

These scenarios verify the server-side installer against the Docker sshd fixture. Run from iTerm2.

#### Fixture setup

Copy the installer and its dependencies to the fixture:

```sh
ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'rm -rf ~/.config/ghostty-zmx; echo "" > ~/.zshrc; rm -rf ~/.terminfo/x/xterm-ghostty 2>/dev/null; mkdir -p /tmp/gzmx-itest/terminfo'
scp -F /tmp/ghostty-zmx-fixture-sshconfig \
  install-server.sh session-manager.zsh session-manager-lib.zsh ghostty-zmx-remote-layout \
  gzmx-fixture:/tmp/gzmx-itest/
scp -F /tmp/ghostty-zmx-fixture-sshconfig \
  terminfo/xterm-ghostty.terminfo \
  gzmx-fixture:/tmp/gzmx-itest/terminfo/
```

#### Install with --yes

```sh
ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'cd /tmp/gzmx-itest && ./install-server.sh --yes'
```

Verify:

```sh
ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'ls ~/.config/ghostty-zmx/; cat ~/.zshrc; infocmp -x xterm-ghostty >/dev/null 2>&1 && echo "terminfo installed"'
```

Expected: `session-manager.zsh`, `session-manager-lib.zsh`, `ghostty-zmx-remote-layout`, `terminfo/xterm-ghostty.terminfo` installed; zshrc has one source line + one remote-env block; `xterm-ghostty` terminfo installed via `tic`.

#### Idempotent re-run

```sh
ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'cd /tmp/gzmx-itest && ./install-server.sh --yes'
```

Expected: "Source line already present", "terminfo already installed; skipping tic". Source line count and BEGIN block count must both be 1 (no duplication).

#### zmx missing refusal

```sh
ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'cd /tmp/gzmx-itest && PATH=/usr/bin:/bin ./install-server.sh --yes'
```

Expected: refuses with "zmx is not installed on this host" and exits non-zero.

#### Interactive decline

```sh
ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'cd /tmp/gzmx-itest && echo "n" | ./install-server.sh'
```

Expected: "Installation declined; no files changed."

#### Pass criteria

- `--yes` install: all files present, zshrc has one source line + one remote-env block, terminfo installed.
- Re-run is idempotent (no duplication).
- zmx missing: refuses with a clear hint.
- Interactive decline: no files changed.
- After install, the `ghostty-zmx-remote-layout` helper works (`add` → `present`, `close` → `deleted`).

### Remote grouped layout restore (windows/tabs/splits after Cmd-Q)

This verifies that after Cmd-Q + reopen, the poller recreates the remote window/tab/split structure from the server `remote-layout` (not one flat window per session), and that unique markers survive in each session's `zmx history`.

1. Pre-seed a server layout with 2 windows, each with 1 tab, each tab with 2 split panes (4 `present` rows with split geometry):

   ```sh
   H='$HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout'
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "$H add wsXX aaaaaaaa aabbba aaa111 gzr-wsXX-aaaaaaaa-aabbba-aaa111 - root 1 present"
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "$H add wsXX aaaaaaaa aabbba aaa222 gzr-wsXX-aaaaaaaa-aabbba-aaa222 aaa111 vertical 0.5 present"
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "$H add wsXX bbbbbbbb bbb111 bbb111 gzr-wsXX-bbbbbbbb-bbb111-bbb111 - root 1 present"
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "$H add wsXX bbbbbbbb bbb111 bbb222 gzr-wsXX-bbbbbbbb-bbb111-bbb222 bbb111 vertical 0.5 present"
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "$H read"  # 4 present rows, split geometry preserved
   ```

2. Pre-seed `remote-hosts` and launch Ghostty-tip (no-prompt harness). Wait ~14s.
3. Verify the initial restore:

   ```sh
   osascript -e 'tell application "Ghostty-tip" to count of windows'  # expect 3
   # terminals per window (expect "2 2 1")
   osascript -e 'tell application "Ghostty-tip" to set out to "
   repeat with w in windows
     set c to 0
     repeat with tb in tabs of w
       set c to c + (count of terminals of tb)
     end repeat
     set out to out & c & " "
   end repeat
   return out'
   ps -eo pid,ppid,comm,args | awk '$3=="ssh" && /zmx attach gzr-/{cnt++} END{print cnt+0}'  # expect 4
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'zmx list 2>/dev/null | grep gzr | grep -o "clients=[0-9]"'  # expect 4x clients=1
   ```

4. Inject unique markers into each remote session via `zmx send`:

   ```sh
   M=$'\n'
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "zmx send gzr-wsXX-aaaaaaaa-aabbba-aaa111 'echo MARKER-AAA111${M}'"
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "zmx send gzr-wsXX-aaaaaaaa-aabbba-aaa222 'echo MARKER-AAA222${M}'"
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "zmx send gzr-wsXX-bbbbbbbb-bbb111-bbb111 'echo MARKER-BBB111${M}'"
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "zmx send gzr-wsXX-bbbbbbbb-bbb111-bbb222 'echo MARKER-BBB222${M}'"
   sleep 2
   # verify each marker in zmx history
   for s in gzr-wsXX-aaaaaaaa-aabbba-aaa111 gzr-wsXX-aaaaaaaa-aabbba-aaa222 gzr-wsXX-bbbbbbbb-bbb111-bbb111 gzr-wsXX-bbbbbbbb-bbb111-bbb222; do
     echo -n "$s: "
     ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "zmx history $s 2>/dev/null | grep -o 'MARKER-[A-Z0-9]*' | tail -1"
   done
   ```

5. Cmd-Q (kill the Ghostty-tip process only) and verify preservation:

   ```sh
   GHOSTPID=$(pgrep -f "Ghostty-tip.app/Contents/MacOS" | head -1)
   kill -9 "$GHOSTPID"; sleep 8
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'zmx list 2>/dev/null | grep gzr | grep -o "clients=[0-9]"'  # expect 4x clients=0
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture '$HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout read | grep -c present'  # expect 4
   lsof ~/.config/ghostty-zmx/session-manager.zsh  # expect empty (no orphaned pollers)
   ```

6. Reopen Ghostty-tip with the same `GHOSTTY_ZMX_DATA_HOME`/`STATE_HOME` and wait ~14s.
7. Verify the layout is restored AND markers survived:

   ```sh
   osascript -e 'tell application "Ghostty-tip" to count of windows'  # expect 3
   # terminals per window (expect "2 2 1")
   ps -eo pid,ppid,comm,args | awk '$3=="ssh" && /zmx attach gzr-/{cnt++} END{print cnt+0}'  # expect 4
   ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture 'zmx list 2>/dev/null | grep gzr | grep -o "clients=[0-9]"'  # expect 4x clients=1
   # markers survived
   for s in gzr-wsXX-aaaaaaaa-aabbba-aaa111 gzr-wsXX-aaaaaaaa-aabbba-aaa222 gzr-wsXX-bbbbbbbb-bbb111-bbb111 gzr-wsXX-bbbbbbbb-bbb111-bbb222; do
     echo -n "$s: "
     ssh -F /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture "zmx history $s 2>/dev/null | grep -o 'MARKER-[A-Z0-9]*' | tail -1"
   done
   ```

#### Pass criteria (grouped restore)

- Initial restore: 3 windows, `2 2 1` terminals, 4 ssh, 4 `clients=1`.
- Split geometry preserved in server layout (`vertical 0.5` not clobbered to `root 1`).
- Cmd-Q: 4 `present` rows, 4 `clients=0`, no close-txn, no orphaned pollers.
- Reopen: 3 windows, `2 2 1` terminals, 4 ssh, 4 `clients=1`.
- All 4 markers survive in their correct sessions after reopen.

## Automated-test config override

Automated tests may use a disposable or temporary Ghostty config that sets `confirm-close-surface = false` for close scenarios. Harnesses that touch the real Ghostty config must restore it byte-for-byte on every exit path and fail if the restored file differs from the original.

Never leave `confirm-close-surface = false` in the production managed block after automated tests.
