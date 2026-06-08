# ghostty-zmx v0.1 design

## Status

Canonical implementation spec for draft PR #1: https://github.com/cad0p/ghostty-zmx/pull/1

This is the locked design for a v0.1 package that makes Ghostty terminal surfaces persistent using zmx.

This design follows the release-grade workflow in `pi-shipit/methodology.md`: it is the canonical spec for a future implementation PR, with explicit scope, decisions, invariants, manual E2E scenarios, known limitations, and deferred items.

## Goal

Package the current Ghostty + zmx session-management experiment into a zsh-first installable integration.

The integration should make Ghostty behave like a native-window terminal multiplexer:

- every managed Ghostty terminal surface gets a named zmx session,
- Cmd-Q preserves zmx sessions and restores the Ghostty layout on reopen,
- closing a pane/tab/window removes the corresponding managed zmx session,
- closing all windows clears the managed layout,
- new local splits, tabs, and windows inherit the active terminal's working directory, including when the active terminal is inside a managed zmx session,
- after OS reboot, the layout is rebuilt and previous scrollback is restored into the new zmx sessions as saved text,
- unmanaged zmx sessions are never reaped or modified.

## Non-goals for v0.1

- Shells other than zsh.
- Linux support.
- SSH support. Remote zmx sessions are deferred to v0.2; the intended v0.2 behavior is analogous to local working-directory inheritance, but creates/attaches remote zmx sessions.
- Fast/parallel restore.
- Homebrew formula.
- `doctor` command.
- Full process persistence across laptop reboot.
- Restoring TUI process state after reboot.
- Managing user-created zmx sessions that are not recorded by ghostty-zmx.
- Depending on gmx.

## Target environment

- macOS.
- Ghostty 1.3.1 with AppleScript enabled. v0.1 should document this tested version explicitly.
- zmx 0.6.x.
- zsh.
- Implementation and manual E2E testing are performed from an iTerm2 terminal session, outside Ghostty and outside any managed zmx session, so Ghostty can be freely quit/reopened during tests.
- Ghostty config contains `env = GHOSTTY_ZMX_AUTO_ATTACH=1`.
- Ghostty config should not set `quit-after-last-window-closed = true`; macOS default `false` is required for correct close-all-windows behavior.
- Ghostty's working-directory reporting was empirically verified through zmx: after `cd` inside a managed zmx shell, AppleScript `working directory of terminal` reflected the inner zmx shell cwd. New split creation also started the new managed zmx session in that cwd, with `/tmp` normalized to `/private/tmp` by macOS.

## Package shape

Repository/package name: `ghostty-zmx`.

Installed files for v0.1:

```text
~/.config/ghostty-zmx/
  session-manager.zsh
  uninstall.sh
```

Optional generated runtime scripts:

```text
/tmp/ghostty-zmx-reaper-${ghosttyPID}.zsh
```

State files:

```text
~/.local/share/ghostty-zmx/
  sessions
  restore-queue
  restore-first
  id-map
```

Debug/state logs:

```text
~/.local/state/ghostty-zmx/
  debug.log
  history/
    <session>.txt
```

The installer may also place a helper executable later, but v0.1 can be pure shell.

## Installation behavior

The installer should:

1. Verify `zmx`, `osascript`, and `zsh` exist.
2. Install `session-manager.zsh` and `uninstall.sh` under `~/.config/ghostty-zmx/`.
3. Append a single guarded source line to `~/.zshrc`:

   ```zsh
   [[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"
   ```

4. Add or verify the Ghostty config block:

   ```ini
   env = GHOSTTY_ZMX_AUTO_ATTACH=1
   window-save-state = never
   confirm-close-surface = true
   ```

5. Remove or warn about:

   ```ini
   quit-after-last-window-closed = true
   ```

   On macOS, Ghostty's default is `false`, and v0.1 relies on that behavior.

6. Save timestamped backups of edited files.

Confirmed installer decisions:

- `confirm-close-surface = true` is required in the managed section because closing a managed surface is destructive.
- Installer is interactive by default and supports a non-interactive `--yes` path. Both paths must be tested.
- If conflicting Ghostty settings exist outside the managed section, leave them untouched and warn; only manage the ghostty-zmx block.

The installer should edit Ghostty config automatically, but only inside a clearly marked managed section and after printing exactly what will be added and where.

Example managed section:

```ini
# BEGIN ghostty-zmx
# Managed by ghostty-zmx. Re-run the installer to update this block.
env = GHOSTTY_ZMX_AUTO_ATTACH=1
window-save-state = never
confirm-close-surface = true
# END ghostty-zmx
```

The installer must not overwrite user shell configuration wholesale.

## Recommended but user-controlled Ghostty settings

The README should document Ghostty's working-directory inheritance settings as recommended knobs, but the installer should not manage or force them:

```ini
window-inherit-working-directory = true
tab-inherit-working-directory = true
split-inherit-working-directory = true
```

ghostty-zmx observes Ghostty's behavior. If users disable or customize these settings, new managed zmx sessions should follow Ghostty's chosen working-directory behavior rather than ghostty-zmx overriding it.

## Migration from the experimental setup

The installer must support migrating the current experimental setup used during design.

Known experimental state:

- `~/.zshrc` contains an inline block headed `zmx session management` and ending with `# end zmx session management`.
- Ghostty config may contain `env = ZMX_AUTO_ATTACH=1`.
- Ghostty config may contain `confirm-close-surface = false`.
- state lives under `~/.local/share/zmx/`:
  - `sessions`,
  - `restore-queue`,
  - `restore-first`,
  - `id-map`.
- runtime flags use `/tmp/zmx-*` names.

Migration behavior:

1. Back up `~/.zshrc` and Ghostty config before editing.
2. Detect and remove the experimental inline `.zshrc` block by its begin/end comments.
3. Add the single `source ~/.config/ghostty-zmx/session-manager.zsh` line.
4. Replace experimental Ghostty config entries with the managed ghostty-zmx section:
   - remove `env = ZMX_AUTO_ATTACH=1`,
   - replace with `env = GHOSTTY_ZMX_AUTO_ATTACH=1`,
   - set `confirm-close-surface = true` in the managed section,
   - leave working-directory inheritance settings under user control,
   - leave unrelated user config unchanged.
5. Copy `~/.local/share/zmx/sessions` to `~/.local/share/ghostty-zmx/sessions`; do not move it during v0.1 migration.
6. Do not migrate old `restore-queue`, `restore-first`, or `id-map`; they are process/runtime state and should be recreated.
7. Remove stale `/tmp/zmx-restore-*`, `/tmp/zmx-restoring-*`, and `/tmp/zmx-reaper-*` flags.
8. Preserve existing live zmx sessions; the migrated sessions file continues to reference their existing names.
9. At the end of migration/testing, remind the user to clean up the old experimental files after both maintainer and agent have tested the new version.

The installer should print the migration plan and ask for confirmation before applying it.

## Uninstall behavior

`~/.config/ghostty-zmx/uninstall.sh` should:

- remove the source line from `~/.zshrc`,
- optionally remove the Ghostty config lines it added,
- remove generated runtime files under `/tmp/ghostty-zmx-*`,
- remove `~/.config/ghostty-zmx/` if requested,
- leave zmx sessions alive by default,
- ask before deleting `~/.local/share/ghostty-zmx/` or `~/.local/state/ghostty-zmx/`.

## Managed session identity

Managed session names use:

```text
zmx-{logical-window-id}-{logical-tab-id}-{terminal-id}
```

Rules:

- Use the full Ghostty window hex portion, not an eight-character prefix.
- Use the full Ghostty tab hex portion, not an eight-character prefix.
- Use the first eight characters of the terminal UUID for the pane component.

Rationale: Ghostty object IDs share long common prefixes. Earlier truncation caused collisions where sessions from different windows restored into the same logical window.

## Persistent layout state

The canonical layout/session list is:

```text
~/.local/share/ghostty-zmx/sessions
```

It is plain text, one managed zmx session name per terminal surface.

Example:

```text
zmx-W1-T1-P1
zmx-W1-T1-P2
zmx-W1-T2-P1
zmx-W2-T1-P1
```

Restore groups by logical window and tab:

```text
Window W1
  Tab T1
    Pane P1
    Pane P2
  Tab T2
    Pane P1
Window W2
  Tab T1
    Pane P1
```

The session log is append-only during ordinary use, but restore must not trust append order as layout order. A tab added later to an existing window may appear after sessions for other windows. Restore must regroup sessions by logical window before creating the layout.

## Runtime mapping state

Ghostty physical window/tab IDs change across app restart. To let new tabs/splits created after restore inherit the correct logical identity, ghostty-zmx maintains:

```text
~/.local/share/ghostty-zmx/id-map
```

Example:

```text
W <physical-window-id> <logical-window-id>
T <physical-window-id> <physical-tab-id> <logical-window-id> <logical-tab-id>
```

The restore driver writes this map. Restored child shells must not rewrite it using `front window`, because focus can move while restore is still creating surfaces.

The map is runtime state for the current Ghostty process. It is rebuilt on every restore.

## Restore algorithm

Restore is serial for v0.1.

1. First Ghostty startup shell sees `GHOSTTY_ZMX_AUTO_ATTACH=1`.
2. It identifies the Ghostty process by walking its parent process tree.
3. It creates a process flag under `/tmp/ghostty-zmx-restore-${ghosttyPID}` so only one shell acts as restore driver.
4. It reads `sessions`.
5. It groups sessions by logical window and tab.
6. It writes `restore-first` and `restore-queue`.
7. It serially creates Ghostty windows, tabs, and splits via AppleScript.
8. Each newly-created shell sees the restore flag, skips restore, pops one session from `restore-queue`, and runs `zmx attach "$SESSION_NAME"`.
9. The first shell reads `restore-first` and attaches to that session.
10. A reaper is started for the Ghostty process.

AppleScript creation remains serial in v0.1. Parallel/batched layout creation was explored but was not reliable during startup restore. It may be revisited behind an experimental flag after v0.1.

## Close cleanup and reaper

Ghostty surface closure usually detaches zmx clients without returning control to shell code after `zmx attach`. Cleanup therefore lives in a separate reaper process.

The reaper:

- is started once per Ghostty process,
- runs under `nohup` so it survives closing the terminal/window that spawned it,
- only manages sessions listed in ghostty-zmx's `sessions` file,
- never reaps arbitrary user-created zmx sessions,
- skips while restore files/flags are present,
- snapshots scrollback before any kill or preserve decision,
- kills and unlogs detached managed sessions when Ghostty still has other attached managed sessions,
- kills and unlogs all detached managed sessions if Ghostty remains alive with `windows=0` for a stable interval,
- preserves detached sessions when Ghostty is quitting or all clients detach as a Cmd-Q-shaped event.

The `windows=0` behavior depends on macOS default `quit-after-last-window-closed = false`. With `quit-after-last-window-closed = true`, closing the final window is indistinguishable from app quit at this layer and v0.1 should warn that the setting is unsupported.

## Scrollback snapshots

zmx restores scrollback while its live daemon exists. It does not appear to persist terminal scrollback durably across OS reboot. zmx's logs are debug/event logs and live under its socket directory; they do not contain terminal output.

Therefore ghostty-zmx v0.1 must save managed scrollback itself.

Snapshot location:

```text
~/.local/state/ghostty-zmx/history/<session>.txt
```

Snapshot trigger:

- The reaper observes a managed session with `clients=0`.
- Before deciding whether to kill or preserve, it runs `zmx history "$session" > "$STATE_HOME/ghostty-zmx/history/$session.txt"`.
- If the session is intentionally closed and unlogged, the snapshot should be deleted immediately by default.
- If the session is preserved for Cmd-Q/restart, the snapshot remains.
- Cmd-Q snapshots are kept and overwritten on every detach; this provides crash/reboot recovery.
- Snapshot files are plain `.txt` files, one per managed session.

Ghostty's `confirm-close-surface` defaults to `true`; v0.1 should keep it enabled in the managed config section. This gives users a confirmation path for Cmd-W / window-close accidents. With confirmation enabled, deleting snapshots immediately for intentional closes is acceptable.

This avoids periodic history polling and captures the last known scrollback at detach time.

Snapshot truncation policy:

- Default to the common iTerm2-style baseline of 1000 scrollback lines.
- Make the limit configurable with `GHOSTTY_ZMX_SCROLLBACK_LINES`.
- Apply truncation at snapshot time, for example with `zmx history "$session" | tail -n "$GHOSTTY_ZMX_SCROLLBACK_LINES"`.
- Document that this is a line-count limit for saved reboot scrollback, not zsh command history and not Ghostty's own live scrollback.

## Reboot scrollback restore

After laptop/OS reboot:

- the `sessions` file survives,
- zmx daemon processes do not,
- live zmx terminal state and scrollback do not,
- history snapshots saved by ghostty-zmx survive.

v0.1 should restore saved scrollback into the new zmx session, not merely print it outside zmx.

Required behavior:

1. Before attaching, determine whether the zmx session already exists with `zmx list --short | grep -qx "$SESSION_NAME"`.
2. If the session does not exist and a history snapshot exists, create a fresh zmx session and inject the saved scrollback into that session's display state.
3. The injection mechanism is `zmx print`, because it writes directly into the session display/scrollback without sending input to the shell PTY.

Empirical result recorded during design:

- `zmx print <missing-session>` does not create the session. It reports the session as unresponsive, exits successfully, and no history is created.
- `zmx run "$session" true` creates a detached session, after which `zmx print "$session" ...` injects text into `zmx history`.

Required flow:

```sh
if ! zmx list --short | grep -qx "$SESSION_NAME" && [[ -s "$historyFile" ]]; then
  zmx run "$SESSION_NAME" true >/dev/null 2>&1 || true
  zmx print "$SESSION_NAME" "$(cat "$historyFile")"
fi
zmx attach "$SESSION_NAME"
```

Implementation must verify that attaching after this flow preserves the printed scrollback inside `zmx history`.

The injected history should include this exact banner:

```text
[ghostty-zmx restored saved scrollback from a previous boot; process state was not restored]
```

The new shell process starts below the restored scrollback.

## Debug logging

Debug logging is mandatory for v0.1 and controlled by environment/config.

Environment variable:

```sh
GHOSTTY_ZMX_DEBUG=1
```

Log path:

```text
~/.local/state/ghostty-zmx/debug.log
```

Debug logs should include shell init, path resolution, Ghostty PID detection, restore-driver election, session grouping, queue activity, AppleScript timing, id-map writes, reaper decisions, scrollback snapshots, reboot/fresh-session detection, and zmx print/attach failures.

Debug logging must avoid leaking command output beyond saved scrollback files. It should log session names and event types, not full terminal history.

## Configuration

v0.1 is implemented in zsh + shell scripts only. It can use environment variables rather than a separate config parser.

```sh
GHOSTTY_ZMX_AUTO_ATTACH=1
GHOSTTY_ZMX_DEBUG=0|1
GHOSTTY_ZMX_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx
GHOSTTY_ZMX_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-zmx
GHOSTTY_ZMX_REAPER_INTERVAL=2
GHOSTTY_ZMX_ZERO_WINDOWS_GRACE=6
GHOSTTY_ZMX_RESTORE_STEP_DELAY=1
GHOSTTY_ZMX_SCROLLBACK_LINES=1000
```

Defaults should be embedded in `session-manager.zsh`.

## E2E automation configuration

Production v0.1 should keep `confirm-close-surface = true`, but automated E2E tests need deterministic close behavior. The E2E harness must run Ghostty with a temporary test config or temporary managed block that sets:

```ini
confirm-close-surface = false
```

for the duration of automated tests only. The harness must restore the user's real config afterward. Manual E2E can exercise the production confirmation behavior separately.

The implementation is tested from iTerm2, outside Ghostty and outside any managed zmx session, so tests can freely quit, reopen, and close Ghostty surfaces without killing the orchestrating terminal.

## Manual E2E scenarios

### Cmd-Q restore

Create multiple windows, tabs, and splits; add unique markers; Cmd-Q Ghostty; reopen; verify same session names, `clients=1`, same layout shape, and markers in `zmx history`.

### Working-directory inheritance

In a managed Ghostty session, `cd` into a unique local directory. Create a new split, tab, and window from that active terminal. Verify each new managed zmx session starts in the same working directory. Verify this is local-only in v0.1; SSH/remote inheritance is deferred to v0.2.

### Close pane cleanup

Create a new split, record its managed zmx session name, close the pane, and verify the session is killed and removed from `sessions`. Verify unmanaged zmx sessions are untouched.

### Close window cleanup

Create a new window with at least one managed session, close that window while another Ghostty window remains, and verify all managed sessions from that closed window are killed and unlogged.

### Close all windows cleanup

With `quit-after-last-window-closed` unset, create two windows, close both one by one, verify Ghostty remains running with `windows=0`, verify the reaper kills and unlogs all managed sessions, then reopen one Ghostty window and verify it starts one fresh session rather than rebuilding the old layout.

### Cmd-Q does not clean

Create two windows, Cmd-Q Ghostty, wait longer than the reaper interval, verify sessions remain, reopen Ghostty, and verify both windows restore.

### Reboot-scrollback simulation

Create a managed session with a unique marker, Cmd-Q Ghostty so the reaper snapshots scrollback, kill the zmx session/daemon or clear the zmx socket directory to simulate daemon loss, reopen Ghostty, verify a new zmx session with the same name is created, verify the implementation used `zmx run "$session" true` or an equivalent tested primitive before `zmx print`, and verify the saved marker appears in `zmx history <session>` after restore, not merely in the outer Ghostty scrollback.

### Unmanaged sessions not reaped

Create a zmx session manually outside Ghostty-zmx management, close Ghostty panes/windows, and verify the unmanaged session remains alive unless explicitly killed by the user.

## Implementation phase plan

A future implementation PR should use the methodology's release-grade phases.

Implementation commits:

1. Extract current zsh integration into `session-manager.zsh` with XDG paths under `ghostty-zmx`.
2. Add interactive installer and uninstall script with backups, `--yes` non-interactive mode, idempotent source-line/config handling, experimental-config migration, conflict warnings, and an automatically managed Ghostty config section.
3. Add debug logging controlled by `GHOSTTY_ZMX_DEBUG`.
4. Observe Ghostty's local working-directory behavior for new splits, tabs, and windows through managed zmx sessions; document recommended Ghostty inheritance settings without managing them.
5. Add reaper-owned scrollback snapshots on detach.
6. Add reboot/fresh-session detection and scrollback injection into new zmx sessions using `zmx run "$session" true` followed by `zmx print`.
7. Add README with install, uninstall, `--yes` usage, migration from the experimental setup, required Ghostty config, conflict-warning behavior, cleanup reminder for old experimental files, usage, and known limitations.
8. Add manual E2E script snippets or a test checklist, including the automated-test override for `confirm-close-surface = false`.

Implementation review should use correctness, coverage, cleanness/API surface, and security/adversarial lenses. E2E should use e2e-tester and adversarial lenses. Bloat review should use bloat-production, bloat-docs, and correctness for over-trim.

## Known limitations

- v0.1 is zsh-only.
- v0.1 is macOS/Ghostty-AppleScript-only.
- Restore is serial for correctness.
- Laptop reboot cannot restore live processes, only layout and saved scrollback.
- Scrollback after reboot must be injected as saved text into a fresh zmx session.
- Manual `zmx detach` inside a managed Ghostty surface may be treated like a close by the reaper.
- `quit-after-last-window-closed = true` is unsupported on macOS for the desired close-all-windows behavior.
- SSH and remote zmx session inheritance are deferred to v0.2.
- Ghostty AppleScript `environment variables of cfg` was observed unreliable in Ghostty 1.3.1, so v0.1 must not depend on it.
- `initial input` / direct batch restore was observed unreliable during startup restore; v0.1 should keep serial queue restore.
- The integration should only reap sessions listed in its managed `sessions` file.

## Locked decisions before implementation

1. `confirm-close-surface = true` is required in the managed Ghostty config section.
2. Cmd-Q snapshots are kept and overwritten on every detach for crash/reboot recovery.
3. History snapshots are plain `.txt` files.
4. Reboot scrollback banner is exactly: `[ghostty-zmx restored saved scrollback from a previous boot; process state was not restored]`.
5. Installer is interactive by default and supports a non-interactive `--yes` path. Both paths must be tested.
6. Experimental state migration copies `~/.local/share/zmx/sessions`; it does not move it. The installer should remind the user to clean up old experimental files after both maintainer and agent have tested the new version.
7. v0.1 implementation language is zsh + shell scripts only.
8. If conflicting Ghostty settings exist outside the managed section, leave them untouched and warn; only manage the ghostty-zmx block.
9. `zmx print <missing-session>` does not create the session. Use `zmx run "$session" true` or an equivalent tested primitive before `zmx print`.
10. Saved scrollback snapshots must use a truncation policy. Default to the common iTerm2-style baseline of 1000 lines, configurable via `GHOSTTY_ZMX_SCROLLBACK_LINES`.
11. Intentionally closed pane/window snapshots are deleted immediately.
12. `ghostty-zmx reset` is deferred.

## Release readiness criteria

v0.1 is ready only when install/uninstall is idempotent, interactive install and `--yes` install are both tested, `.zshrc` integration is one source line, Ghostty config guidance is explicit, conflict warnings are tested, debug logging works, Cmd-Q restore passes, close cleanup passes, unmanaged zmx sessions are untouched, reboot-scrollback simulation proves saved scrollback is inside the new zmx session history, and README documents known limitations and required config.
