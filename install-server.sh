#!/bin/zsh
# ghostty-zmx server installer.
#
# Run on each remote host that will be used as a remote-zmx target. The UX flow
# is: install ghostty-zmx on the laptop, install ghostty-zmx on the server, then
# remote panes work.
#
# The server installer:
#   1. verifies zsh and zmx exist (zmx is a prerequisite, not managed here),
#   2. installs session-manager.zsh + session-manager-lib.zsh + the vendored Ghostty terminfo,
#   3. appends the same guarded source line to ~/.zshrc (dormant on a headless
#      host, but keeps the install symmetric),
#   4. adds a managed remote-env block to ~/.zshrc that sets TERM_PROGRAM and
#      COLORTERM for remote interactive shells when the transport did not
#      forward them (tsh ssh does not; +ssh would),
#   5. saves timestamped backups of edited files.
#
# It is interactive by default and supports --yes. It must not modify Teleport,
# sshd, or any system-level config.
#
# See the v0.2 design doc, "Server installation behavior".

set -u
setopt NULL_GLOB

YES=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --help|-h)
      print "Usage: ./install-server.sh [--yes]"
      print "Install ghostty-zmx server-side prerequisites on this host."
      exit 0
      ;;
    *) print -u2 "Unknown argument: $arg"; exit 2 ;;
  esac
done

[[ -n "${HOME:-}" ]] || { print -u2 "HOME is not set"; exit 1; }

repo_dir="${0:A:h}"
source_manager="$repo_dir/session-manager.zsh"
source_lib="$repo_dir/session-manager-lib.zsh"
source_terminfo="$repo_dir/terminfo/xterm-ghostty.terminfo"
source_remote_layout="$repo_dir/cli/remote-layout"
install_dir="$HOME/.config/ghostty-zmx"
manager_dest="$install_dir/session-manager.zsh"
lib_dest="$install_dir/session-manager-lib.zsh"
terminfo_dest="$install_dir/terminfo/xterm-ghostty.terminfo"
remote_layout_dest="$install_dir/cli/remote-layout"
zshrc="$HOME/.zshrc"
source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"'
backup_counter=0

# Managed remote-env block: set TERM_PROGRAM/COLORTERM/TERM for remote
# interactive shells so terminal integration works correctly.
#
# Why this is needed: the projection wrapper sets TERM=dumb locally before
# exec-ing the tsh transport (to suppress tsh's OSC 11 / CSI 6n probe — see
# ghostty-zmx wrapper). tsh DOES forward the local TERM to the remote over a
# pty (-t), so the remote interactive shell inherits TERM=dumb. This breaks:
#   - oh-my-zsh's termsupport.zsh OSC 7 emitter (its `case "$TERM"` gate
#     rejects `dumb`, so it never defines omz_termsupport_cwd -> Ghostty's
#     `working directory` terminal property stays empty for remote panes,
#     which blocks local cwd reads for split inheritance).
#   - every curses/tui app in the projection pane (TERM=dumb disables colors,
#     cursor addressing, alt screen).
#   - any terminal-integration check that gates on TERM or TERM_PROGRAM.
#
# The fix runs in the remote ~/.zshrc (sourced by the interactive shell) and
# restores a working TERM when the Ghostty terminfo is installed. It is gated
# on SSH_CONNECTION (only remote sessions) and only overrides TERM when it is
# `dumb` or empty (never clobbers a valid user/transport TERM like
# xterm-256color or screen-256color). TERM_PROGRAM/COLORTERM are set when the
# transport did not forward them (tsh does not; plain ssh + Ghostty's +ssh
# does, handled there — this block is a no-op for +ssh hosts).
remote_env_block='# BEGIN ghostty-zmx remote-env
if [[ -n "${SSH_CONNECTION:-}" ]]; then
  [[ -n "${TERM_PROGRAM:-}" ]] || export TERM_PROGRAM=ghostty
  [[ -n "${COLORTERM:-}" ]] || export COLORTERM=truecolor
  # Pin ZMX_DIR so the interactive shell queries the same socket dir the
  # projection created the session in. zmx resolves ZMX_DIR > XDG_RUNTIME_DIR
  # > TMPDIR; the projection (non-interactive ssh) has no XDG_RUNTIME_DIR, so
  # without this pin the session lands in TMPDIR (/tmp/zmx-<uid>) while this
  # interactive shell (XDG_RUNTIME_DIR set by pam_systemd) queries
  # /run/user/<uid>/zmx — a mismatch where `zmx ls` in the pane cannot see the
  # gzr-* session it is attached to. See ghostty_zmx_zmx_dir.
  # mkdir first: zmx does not create ZMX_DIR for read-only commands (version,
  # list), so it must exist before any zmx call in this shell.
  _gzmx_zmx_dir="$HOME/.local/state/ghostty-zmx/zmx"
  mkdir -p "$_gzmx_zmx_dir" 2>/dev/null
  export ZMX_DIR="$_gzmx_zmx_dir"
  # Restore a working TERM when the transport left it dumb/empty (the
  # projection wrapper sets TERM=dumb locally to suppress the tsh probe; tsh
  # forwards it to the remote). Only override dumb/empty — never clobber a
  # valid TERM. Requires the Ghostty terminfo (installed by this installer
  # via `tic -x`; a prior `ghostty +ssh` connect also installs it).
  if [[ "${TERM:-}" == "dumb" || -z "${TERM:-}" ]]; then
    if infocmp -x xterm-ghostty >/dev/null 2>&1; then
      export TERM=xterm-ghostty
    else
      export TERM=xterm-256color
    fi
  fi
fi
# Pin the zsh-autosuggestions highlight style to its default (`fg=8`) explicitly.
# This is NOT a leak mitigation — the OSC 11 leak was a tsh-client quirk
# (tsh emits OSC 11 + CSI 6n on every connection; fixed by the projection
# wrapper setting TERM=dumb for tsh transports). zsh-autosuggestions does not
# emit OSC 11 (it defaults to `fg=8`, no query). This pin is a no-cost default
# that keeps the suggestion color stable across environments.
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=8"
# Emit OSC 7 (current working directory) on every prompt so the local Ghostty
# tracks the remote cwd via its `working directory` terminal property. This is
# needed because: (1) oh-my-zsh deliberately skips its omz_termsupport_cwd
# emitter in any SSH session (oh-my-zsh #11696: the guard `if [[ -n
# $SSH_CLIENT || -n $SSH_TTY ]]; then return`); and (2) even if oh-my-zsh did
# emit it, Ghostty rejects OSC 7 with a non-localhost host (a security design
# so a remote shell cannot set the local working-directory property). Our
# emitter uses `file://localhost/<remote-path>` so Ghostty accepts it, and the
# path is the remote cwd we want for split inheritance. Fires for interactive
# shells under Ghostty only.
if [[ -o interactive && "${TERM_PROGRAM:-}" == "ghostty" && -z "${_GZMX_OSC7_HOOK:-}" ]]; then
  export _GZMX_OSC7_HOOK=1
  _gzmx_osc7_cwd() {
    # file: URI with percent-encoded path. Use `localhost` as the host so
    # Ghostty accepts the OSC 7 (it rejects non-localhost hosts for
    # security: a remote shell must not set the local working-directory
    # property). The path is the REMOTE path, which is what we want for
    # split cwd inheritance (we cd to it over ssh). Reuse oh-my-zsh encoder
    # if available, otherwise emit the raw path (paths are usually safe).
    local _op
    if (( ${+functions[omz_urlencode]} )); then
      _op="$(omz_urlencode -P "${PWD}")" 2>/dev/null
    else
      _op="${PWD}"
    fi
    printf "\e]7;file://localhost%s\e\\" "$_op"
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _gzmx_osc7_cwd
fi
# END ghostty-zmx remote-env'

backup_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  backup_counter=$(( ${backup_counter:-0} + 1 ))
  local backup="${file}.ghostty-zmx.$(date +%Y%m%d-%H%M%S).$$.${backup_counter}.bak"
  cp "$file" "$backup" || { print -u2 "Failed to back up $file"; return 1; }
  print "Backed up $file to $backup"
}

confirm() {
  local prompt="$1"
  [[ "$YES" -eq 1 ]] && return 0
  print -n "$prompt [y/N] "
  local reply
  read -r reply
  [[ "$reply" == [Yy] || "$reply" == [Yy][Ee][Ss] ]]
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    print -u2 "Missing required command: $cmd"
    exit 1
  fi
}

refuse_symlinked_install_dir() {
  if [[ -L "$install_dir" ]]; then
    print -u2 "Refusing to install into symlinked install directory: $install_dir"
    exit 1
  fi
}

# Refuse a non-directory install path (e.g. a stray regular file at
# ~/.config/ghostty-zmx). Otherwise `mkdir -p $install_dir/terminfo` silently
# fails and later `install -m` calls exit — but the shell startup source line
# and remote-env block have already been written to ~/.zshrc, leaving a
# guarded-but-dangling reference forever. Mirrors validate_install_dir in
# install.sh (round 3 fix).
refuse_non_directory_install_dir() {
  if [[ -e "$install_dir" && ! -d "$install_dir" ]]; then
    print -u2 "Refusing to install into non-directory install path: $install_dir"
    exit 1
  fi
}

ensure_source_line() {
  local file="$1"
  touch "$file" || return 1
  if grep -qxF "$source_line" "$file" 2>/dev/null; then
    print "Source line already present in $file"
    return 0
  fi
  {
    print ""
    print "# ghostty-zmx"
    print -r -- "$source_line"
  } >> "$file"
  print "Added ghostty-zmx source line to $file"
}

# Block markers use the form `# BEGIN <marker>` / `# END <marker>` (matching
# install.sh's `# BEGIN ghostty-zmx` convention), not `# <marker> BEGIN`.
validate_block_pairs() {
  local file="$1" begins ends marker="$2"
  [[ -f "$file" ]] || return 0
  begins=$(awk -v m="# BEGIN ${marker}" '$0==m { count++ } END { print count + 0 }' "$file") || return 1
  ends=$(awk -v m="# END ${marker}" '$0==m { count++ } END { print count + 0 }' "$file") || return 1
  if [[ "$begins" -ne "$ends" ]]; then
    print -u2 "Refusing to edit $file: managed ${marker} block is malformed (BEGIN count: $begins, END count: $ends)."
    return 1
  fi
}

strip_block() {
  local file="$1" marker="$2"
  awk -v begin="# BEGIN ${marker}" -v end="# END ${marker}" '
    $0==begin { skip=1; next }
    $0==end && skip { skip=0; next }
    skip { next }
    { print }
  ' "$file" > "${file}.tmp"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    rm -f "${file}.tmp"
    print -u2 "Failed to prepare $file"
    return 1
  fi
  mv "${file}.tmp" "$file"
}

ensure_remote_env_block() {
  local file="$1" tmp
  mkdir -p "${file:h}" 2>/dev/null || return 1
  touch "$file" || return 1
  validate_block_pairs "$file" "ghostty-zmx remote-env" || return 1
  strip_block "$file" "ghostty-zmx remote-env" || return 1
  # PREPEND the block (not append) so it runs before oh-my-zsh's termsupport.zsh
  # loads. oh-my-zsh's OSC 7 emitter (omz_termsupport_cwd) is only defined if
  # its `case "$TERM"` gate passes at load time; if TERM is still dumb/empty
  # when oh-my-zsh sources, the function is never defined and our later TERM
  # fix comes too late. By prepending, TERM/TERM_PROGRAM/COLORTERM are set
  # before any interactive-shell customization sees them.
  tmp="${file}.tmp.$$"
  {
    print -r -- "$remote_env_block"
    print ""
    [[ -f "$file" ]] && cat "$file"
  } > "$tmp" 2>/dev/null && mv "$tmp" "$file" 2>/dev/null || {
    rm -f "$tmp" 2>/dev/null || true
    print -u2 "Failed to update $file"
    return 1
  }
  print "Updated managed ghostty-zmx remote-env block in $file"
}

# Install the vendored Ghostty terminfo into the remote terminfo DB via tic.
# Skip if xterm-ghostty is already installed (e.g. by a prior +ssh connect) so
# we do not clobber a newer/matching entry. tic -x installs to the user's
# terminfo db (~/.terminfo or $TERMINFO) by default, which is sufficient for
# the remote user's own shells.
install_terminfo() {
  local terminfo_src="$1"
  if infocmp -x xterm-ghostty >/dev/null 2>&1; then
    print "xterm-ghostty terminfo already installed on this host; skipping tic"
    return 0
  fi
  if ! command -v tic >/dev/null 2>&1; then
    print -u2 "Warning: tic not found; skipping terminfo install. Remote panes may lack full Ghostty capabilities until xterm-ghostty is installed."
    return 0
  fi
  tic -x "$terminfo_src" || { print -u2 "Failed to install xterm-ghostty terminfo via tic"; return 1; }
  print "Installed xterm-ghostty terminfo via tic"
}

print_plan() {
  print "ghostty-zmx SERVER installer will:"
  print "  - verify zsh and zmx are installed (zmx is a prerequisite)"
  print "  - install files under $install_dir (session-manager.zsh, session-manager-lib.zsh, terminfo, cli/remote-layout)"
  print "  - install the vendored Ghostty terminfo (xterm-ghostty) via tic (skipped if already present)"
  print "  - update $zshrc with one guarded source line (dormant on a headless host)"
  print "  - add a managed remote-env block to $zshrc (TERM_PROGRAM/COLORTERM for remote shells)"
  print "  - save timestamped backups of edited files"
  print "  - NOT modify Teleport, sshd, or any system-level config"
  print ""
  print "Managed remote-env block to add to $zshrc:"
  print -r -- "$remote_env_block"
}

# Prerequisites: zsh and zmx. zmx is a prerequisite, not managed by this script.
# Refuse if zmx is missing. Check both the non-interactive PATH and the
# interactive zsh PATH (some users add ~/.local/bin to PATH only in .zshrc,
# which is sourced for interactive shells but not for `ssh host 'cmd'`).
require_command zsh
if ! command -v zmx >/dev/null 2>&1; then
  if ! zsh -ic 'command -v zmx >/dev/null 2>&1' 2>/dev/null; then
    print -u2 "zmx is not installed on this host. ghostty-zmx requires zmx as a prerequisite."
    print -u2 "Install zmx first (see https://github.com/aurera/zmx or your package manager), then re-run this installer."
    exit 1
  fi
fi

[[ -f "$source_manager" ]] || { print -u2 "Missing $source_manager"; exit 1; }
[[ -f "$source_lib" ]] || { print -u2 "Missing $source_lib"; exit 1; }
[[ -f "$source_terminfo" ]] || { print -u2 "Missing $source_terminfo"; exit 1; }
[[ -f "$source_remote_layout" ]] || { print -u2 "Missing $source_remote_layout"; exit 1; }

refuse_symlinked_install_dir
refuse_non_directory_install_dir

print_plan
confirm "Apply this server installation plan?" || { print "Installation declined; no files changed."; exit 0; }

backup_file "$zshrc"
ensure_source_line "$zshrc" || exit 1
ensure_remote_env_block "$zshrc" || exit 1

mkdir -p "$install_dir/terminfo" "$install_dir/cli" || exit 1
if [[ -L "$install_dir" ]]; then
  print -u2 "Refusing to install into symlinked install directory: $install_dir"
  exit 1
fi
if [[ ! -d "$install_dir" ]]; then
  print -u2 "Failed to create install directory: $install_dir"
  exit 1
fi
install -m 0644 "$source_manager" "$manager_dest" || exit 1
install -m 0644 "$source_lib" "$lib_dest" || exit 1
install -m 0644 "$source_terminfo" "$terminfo_dest" || exit 1
install -m 0755 "$source_remote_layout" "$remote_layout_dest" || exit 1
print "Installed $manager_dest"
print "Installed $lib_dest"
print "Installed $terminfo_dest"
print "Installed $remote_layout_dest"

install_terminfo "$terminfo_dest" || exit 1

print ""
print "ghostty-zmx server installation complete."
print "Remote panes from a laptop with ghostty-zmx installed will now attach to zmx sessions on this host."
