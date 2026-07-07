# ghostty-zmx

ghostty-zmx makes local Ghostty terminal surfaces persistent with zmx. It is a zsh-first integration for macOS: each managed Ghostty pane attaches to a named zmx session, normal pane/window closes clean up the matching managed sessions, and Cmd-Q preserves sessions so Ghostty can rebuild the layout on reopen.

## Tested environment

- macOS
- Ghostty 1.3.1 with AppleScript enabled
- zmx 0.6.x
- zsh

Run manual tests from iTerm2 or another terminal outside managed Ghostty and outside any zmx session. Ghostty may be quit and reopened during testing.

## Development sources and required reading

Development work should track the upstream interfaces ghostty-zmx depends on:

- Ghostty AppleScript support: https://github.com/ghostty-org/website/blob/main/docs/features/applescript.mdx
- zmx session manager: https://github.com/neurosnap/zmx

The current limitations are listed in the [Limitations](#limitations) section.

## Install

### Stable Homebrew install

`ghostty-zmx` is published in the stable tap:

```sh
brew tap neurosnap/tap
brew trust --formula neurosnap/tap/zmx
brew trust --formula cad0p/tap/ghostty-zmx
brew install cad0p/tap/ghostty-zmx
```

The formula depends on `neurosnap/tap/zmx` and installs the `ghostty-zmx` CLI (with `install`, `uninstall`, and `install-server` subcommands). It does not modify your shell or Ghostty config by itself.

After installing, run:

```sh
ghostty-zmx install
```

For non-interactive setup:

```sh
ghostty-zmx install --yes
```

### Prerelease Homebrew install

Prerelease builds are published to a separate tap:

```sh
brew tap neurosnap/tap
brew trust --formula neurosnap/tap/zmx
brew trust --formula cad0p/prerelease/ghostty-zmx
brew install cad0p/prerelease/ghostty-zmx
```

The prerelease tap tracks prerelease GitHub releases, not `--HEAD` builds. The installed commands are the same as the stable formula:

```sh
ghostty-zmx install
ghostty-zmx uninstall
ghostty-zmx install-server <host>
```

Use the prerelease tap only when testing prerelease `ghostty-zmx` behavior. Stable users should use:

```sh
brew install cad0p/tap/ghostty-zmx
```

### Local development install

Install directly from a checkout when developing `ghostty-zmx`:

```sh
git clone https://github.com/cad0p/ghostty-zmx.git
cd ghostty-zmx
./install.sh
```

For non-interactive local installation:

```sh
./install.sh --yes
```

The installer verifies `zmx`, `osascript`, and `zsh`, installs:

```text
~/.config/ghostty-zmx/session-manager.zsh
~/.config/ghostty-zmx/session-manager-lib.zsh
~/.config/ghostty-zmx/session-manager-early.zsh
~/.config/ghostty-zmx/uninstall.sh
```

and appends this guarded source line to `~/.zshrc`:

```zsh
[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"
```

For Ghostty 1.4.0+ remote-split inheritance, the installer also appends an early guarded source line to `~/.zprofile`:

```zsh
[[ -r "$HOME/.config/ghostty-zmx/session-manager-early.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager-early.zsh"
```

That early hook runs before `.zshrc` only for Ghostty surfaces, and only to replace a native split of a remote projection pane with the projection wrapper before local shell plugins run. Ordinary local panes fall through to `.zshrc`, so aliases/prompts/plugins still load normally.

The installer saves timestamped backups before editing shell or Ghostty config files.

### Ghostty-tip dev install (`install-dev`)

For developing `ghostty-zmx` against Ghostty-tip (the 1.4.0 prerelease), use `ghostty-zmx install-dev`. This is a one-command dev onboarding that installs the checkout into an isolated location, separate from your stable install:

```sh
git clone https://github.com/cad0p/ghostty-zmx.git
cd ghostty-zmx
ghostty-zmx install-dev
```

`install-dev` will:

- Ensure a signed `Ghostty-tip.app` exists at `/Applications/Ghostty-tip.app`. If it's missing, or if you pass `--update-tip`, the latest tip is downloaded from the [official Ghostty appcast](https://tip.files.ghostty.org/appcast.xml) (TLS-verified, length-checked), copied, renamed to `Ghostty-tip`, ad-hoc signed, and registered with LaunchServices.
- Install the checkout's files under `~/.config/ghostty-zmx-tip/`.
- Write an isolated Ghostty-tip config under `~/.config/ghostty-tip/config.ghostty` with `GHOSTTY_ZMX_DEBUG=1` always baked in.
- Write an isolated `ZDOTDIR` under `~/.config/ghostty-tip-zdotdir/` (sources your user `.zshrc`/`.zprofile` with `GHOSTTY_ZMX_AUTO_ATTACH=0` first, then sources the tip install so a stable install stays dormant).
- Keep tip state under `~/.local/share/ghostty-zmx-tip/` and `~/.local/state/ghostty-zmx-tip/`.
- Stamp the tip bundle's `LSEnvironment` so Spotlight/double-click launches get the isolated env.
- Write a launcher at `~/.config/ghostty-tip/open-ghostty-tip.zsh`.

It never touches stable Ghostty, stable Ghostty config, `~/.zshrc`, or `~/.zprofile`.

Flags: `--yes` (non-interactive), `--update-tip` (replace the app with the latest from the appcast).

Launch the tip with the launcher:

```sh
~/.config/ghostty-tip/open-ghostty-tip.zsh
```

or via Spotlight (the bundle's `LSEnvironment` carries the isolated env).

### Ghostty config paths (macOS)

Ghostty discovers its config from these locations, in order (later files override earlier):

1. `$XDG_CONFIG_HOME/ghostty/config.ghostty` (if `XDG_CONFIG_HOME` set; defaults to `~/.config`)
2. `$XDG_CONFIG_HOME/ghostty/config`
3. `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` (macOS app-support)
4. `~/Library/Application Support/com.mitchellh.ghostty/config`

The macOS app-support path is **always** read, regardless of `XDG_CONFIG_HOME`. This is the file the Ghostty > Settings menu opens.

- **Stable install** (`ghostty-zmx install`): writes the managed `# BEGIN/END ghostty-zmx` block to the **app-support** path (`~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`), so it applies to every Ghostty surface.
- **Dev install** (`ghostty-zmx install-dev`): writes its isolated config to `~/.config/ghostty-tip/config.ghostty` and stamps `LSEnvironment` on the tip bundle. It does **not** redirect `XDG_CONFIG_HOME` via `launchctl setenv` — the Ghostty maintainer's suggestion ([ghostty-org/ghostty#12408](https://github.com/ghostty-org/ghostty/issues/12408)) is global and would break stable Ghostty and every other GUI app that reads `XDG_CONFIG_HOME`. Instead, the isolated env is carried per-app by `LSEnvironment` (for Spotlight launches) and by `--config-file` (for launcher launches), both generated from a single shared env list to prevent drift.

## Remote server install

Remote zmx panes require the ghostty-zmx server-side files on each remote host. The `ghostty-zmx install-server` subcommand bootstraps them in one shot over your existing ssh/tsh transport — no manual `scp`:

```sh
ghostty-zmx install-server pcad-dev
```

It bundles `install-server.sh` and its sibling files from your laptop, streams the tarball over ssh/tsh into a temp dir on the remote, runs `install-server.sh --yes` there, and cleans up. The remote installer verifies `zsh` and `zmx` (zmx is a prerequisite, not managed here), installs the server-side manager + vendored Ghostty terminfo, and adds a managed `TERM_PROGRAM`/`COLORTERM` remote-env block to the remote `~/.zshrc` so Ghostty shell integration auto-activates over `tsh ssh`.

Transport resolution:

- Known host (already used in a projection): reuses the stored transport prefix from `remote-hosts` (so `tsh ssh` vs `ssh` and any `-F`/`-i`/`-l` options are reused).
- Unknown host: falls back to `ssh <host>`.
- Explicit transport: `ghostty-zmx install-server -- tsh ssh -i /key pier@host`.

Run `ghostty-zmx install --yes` on the laptop first so the local bundle files are present.

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

Debug logging writes to `${GHOSTTY_ZMX_STATE_HOME}/debug.log` (default `~/.local/state/ghostty-zmx/debug.log`). The log is capped at 1 MB and rotated to `debug.log.1` (one backup) when it exceeds the cap; configure with `GHOSTTY_ZMX_DEBUG_LOG_MAX_BYTES`.

The `ghostty-zmx debug` subcommand manages debug logging and produces bug-report-ready output:

```sh
ghostty-zmx debug on       # enable debug in the managed Ghostty config (survives restart)
ghostty-zmx debug off      # disable debug
ghostty-zmx debug status   # show on/off + log path
ghostty-zmx debug log --lines 200   # print versions + remotes + last 200 log lines
```

`debug on` edits the managed `# BEGIN/END ghostty-zmx` block to add `env = GHOSTTY_ZMX_DEBUG=1`; restart Ghostty for it to take effect. `debug log` prints a pre-formatted context block (ghostty-zmx version via `git describe`, Ghostty version, macOS version, configured remotes with their stored zmx version, and the debug-log tail) suitable for pasting into a bug report.

The log records shell initialization, path resolution, Ghostty PID detection, restore-driver election, grouping, queue operations, AppleScript timing, id-map writes, reaper decisions, scrollback snapshots, fresh-session detection, and zmx attach/print failures. It records event metadata and session names, not terminal history contents.

To report a bug, run `ghostty-zmx debug on`, restart Ghostty, reproduce the issue, then run `ghostty-zmx debug log --lines 200` and paste the output into the [bug report template](https://github.com/cad0p/ghostty-zmx/issues/new?template=bug_report.yml). Run `ghostty-zmx debug off` when done.

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
ghostty-zmx uninstall
```

or non-interactively:

```sh
ghostty-zmx uninstall --yes
```

Uninstall removes the `.zshrc` and `.zprofile` source lines, removes the managed Ghostty block when accepted interactively or when `--yes` is used, removes generated runtime files, removes installed ghostty-zmx files under `~/.config/ghostty-zmx` where present, and leaves zmx sessions/data/state alive by default. `--yes` is non-interactive but still preserves data and state unless explicit destructive flags are provided:

```sh
ghostty-zmx uninstall --yes --remove-install-dir --remove-data --remove-state
```

Deletion flags refuse unsafe targets such as `$HOME`, `/`, parent directories, paths not owned by the current user, or paths whose final component is not `ghostty-zmx`.

## Limitations

- zsh only.
- macOS and Ghostty AppleScript only.
- Local sessions only; SSH and remote zmx session inheritance are deferred to v0.2.
- Restore is serial for correctness.
- Reboot restores layout and saved scrollback text only, not live process state.
- `quit-after-last-window-closed = true` is unsupported.
