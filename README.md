# ghostty-zmx

ghostty-zmx makes local Ghostty terminal surfaces persistent with zmx. It is a zsh-first integration for macOS: each managed Ghostty pane attaches to a named zmx session, normal pane/window closes clean up the matching managed sessions, and Cmd-Q preserves sessions so Ghostty can rebuild the layout on reopen.

## Tested environment

- macOS
- Ghostty 1.3.1 with AppleScript enabled
- zmx 0.6.x
- zsh

Run manual tests from iTerm2 or another terminal outside managed Ghostty and outside any zmx session. Ghostty may be quit and reopened during testing.

## Install

```sh
git clone https://github.com/cad0p/ghostty-zmx.git
cd ghostty-zmx
./install.sh
```

The installer is interactive by default. For non-interactive installation:

```sh
./install.sh --yes
```

The installer verifies `zmx`, `osascript`, and `zsh`, installs:

```text
~/.config/ghostty-zmx/session-manager.zsh
~/.config/ghostty-zmx/uninstall.sh
```

and appends this single guarded source line to `~/.zshrc`:

```zsh
[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"
```

The installer saves timestamped backups before editing shell or Ghostty config files.

## Ghostty config managed by ghostty-zmx

The installer manages only this section in the Ghostty config:

```ini
# BEGIN ghostty-zmx
# Managed by ghostty-zmx. Re-run the installer to update this block.
env = GHOSTTY_ZMX_AUTO_ATTACH=1
window-save-state = never
confirm-close-surface = true
# END ghostty-zmx
```

Conflicting `env = GHOSTTY_ZMX_AUTO_ATTACH=...`, `window-save-state`, or `confirm-close-surface` settings outside the managed section are left untouched and reported as warnings. `confirm-close-surface = true` is required because closing a managed surface is destructive.

`quit-after-last-window-closed = true` is unsupported for v0.1 because close-all-windows cleanup relies on Ghostty remaining alive with zero windows. Remove that setting or set it to false.

Recommended Ghostty working-directory settings are user-controlled; the installer does not manage them:

```ini
window-inherit-working-directory = true
tab-inherit-working-directory = true
split-inherit-working-directory = true
```

ghostty-zmx observes Ghostty's chosen working-directory behavior. It does not override it.

## Experimental setup cleanup

v0.1 is packaged as a new integration. It does not automate migration from the earlier experimental inline `.zshrc` block or the old `~/.local/share/zmx/sessions` file.

If you previously used the experiment, manually remove the old inline `.zshrc` block, remove or leave unmanaged any old `ZMX_AUTO_ATTACH=1` Ghostty env line, and clean up old experimental files under `~/.local/share/zmx/` only after you have confirmed the new integration works.

## Usage model

Open Ghostty normally. When `GHOSTTY_ZMX_AUTO_ATTACH=1` is present in Ghostty's environment and an interactive zsh starts outside an existing zmx/tmux session, ghostty-zmx attaches the shell to a managed zmx session named:

```text
zmx-<logical-window-id>-<logical-tab-id>-<terminal-id-prefix>
```

The logical window and tab IDs use the full Ghostty hex portions. The terminal component uses the first eight characters of the terminal UUID.

Cmd-Q preserves managed zmx sessions. Reopening Ghostty restores the saved layout serially using AppleScript and attaches panes through a restore queue. Closing a pane, tab, or window is treated as an intentional close and reaps only the managed sessions listed in ghostty-zmx's sessions file. User-created zmx sessions that are not in that file are not reaped.

## State and data paths

Defaults can be overridden with environment variables:

```text
GHOSTTY_ZMX_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx
GHOSTTY_ZMX_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-zmx
GHOSTTY_ZMX_REAPER_INTERVAL=2
GHOSTTY_ZMX_ZERO_WINDOWS_GRACE=6
GHOSTTY_ZMX_RESTORE_STEP_DELAY=1
GHOSTTY_ZMX_SCROLLBACK_LINES=1000
```

User-actionable paths:

```text
~/.local/share/ghostty-zmx/          # data directory
~/.local/share/ghostty-zmx/sessions # managed-session support log
~/.local/state/ghostty-zmx/          # state directory
~/.local/state/ghostty-zmx/debug.log
~/.local/state/ghostty-zmx/history/<session>.txt
```

Other files under these directories and the per-user runtime directory are internal implementation state and may change.

## Debug logging

Set `GHOSTTY_ZMX_DEBUG=1` in Ghostty's environment to write debug events to:

```text
${GHOSTTY_ZMX_STATE_HOME}/debug.log
```

The log records shell initialization, path resolution, Ghostty PID detection, restore-driver election, grouping, queue operations, AppleScript timing, id-map writes, reaper decisions, scrollback snapshots, fresh-session detection, and zmx attach/print failures. It records event metadata and session names, not terminal history contents.

## Close semantics

- Close a pane/tab/window: ghostty-zmx snapshots scrollback, kills and unlogs the detached managed session, then deletes the snapshot for that intentional close.
- Close all windows while Ghostty remains running: after a stable zero-window interval, all detached managed sessions are killed and unlogged.
- Cmd-Q: sessions are preserved, snapshots are kept, and the layout is restored on the next Ghostty launch.

Manual `zmx detach` inside a managed Ghostty surface can look like a close to the reaper.

## Reboot scrollback semantics

zmx live process state and scrollback do not survive an OS reboot. ghostty-zmx saves a truncated plain-text scrollback snapshot on detach, defaulting to 1000 lines via `GHOSTTY_ZMX_SCROLLBACK_LINES`.

If Ghostty restores a layout after zmx sessions are missing but a snapshot exists, ghostty-zmx creates a fresh zmx session, injects this banner and the saved text with `zmx print`, then attaches:

```text
[ghostty-zmx restored saved scrollback from a previous boot; process state was not restored]
```

This restores saved text into the new zmx history. It does not restore live processes, TUI state, or shell jobs from before reboot.

## Uninstall

```sh
~/.config/ghostty-zmx/uninstall.sh
```

or non-interactively:

```sh
~/.config/ghostty-zmx/uninstall.sh --yes
```

Uninstall removes the `.zshrc` source line, removes the managed Ghostty block when accepted interactively or when `--yes` is used, removes generated runtime files, and leaves zmx sessions alive by default. `--yes` is non-interactive but still preserves installed files, data, and state unless explicit destructive flags are provided:

```sh
~/.config/ghostty-zmx/uninstall.sh --yes --remove-install-dir --remove-data --remove-state
```

Deletion flags refuse unsafe targets such as `$HOME`, `/`, parent directories, paths not owned by the current user, or paths whose final component is not `ghostty-zmx`.

## Limitations

- zsh only.
- macOS and Ghostty AppleScript only.
- Local sessions only; SSH and remote zmx session inheritance are deferred to v0.2.
- Restore is serial for correctness.
- Reboot restores layout and saved scrollback text only, not live process state.
- `quit-after-last-window-closed = true` is unsupported.
