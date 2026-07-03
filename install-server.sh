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
source_remote_layout="$repo_dir/ghostty-zmx-remote-layout"
install_dir="$HOME/.config/ghostty-zmx"
manager_dest="$install_dir/session-manager.zsh"
lib_dest="$install_dir/session-manager-lib.zsh"
terminfo_dest="$install_dir/terminfo/xterm-ghostty.terminfo"
remote_layout_dest="$install_dir/ghostty-zmx-remote-layout"
zshrc="$HOME/.zshrc"
source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"'
backup_counter=0

# Managed remote-env block: set TERM_PROGRAM/COLORTERM for remote interactive
# shells only when the transport did not forward them (SSH_CONNECTION set and
# TERM_PROGRAM empty). This lets remote Ghostty shell integration auto-activate
# even when the transport is `tsh ssh` (which does not forward these vars).
#
# Also suppresses terminal-query-response leaks into zmx scrollback. Remote
# shell startup (oh-my-zsh + zsh-autosuggestions + prompt-init) emits terminal
# queries (OSC 11 foreground-color, CSI 6n cursor-position). Ghostty answers;
# the response bytes flow back into the zmx PTY as input and get captured into
# scrollback, appearing as stray `11;rgb:...1R` characters. Two mitigations:
#   1. Set ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8' so zsh-autosuggestions uses an
#      explicit color and skips its OSC 11 foreground-color query.
#   2. Install a precmd hook that drains any pending query-response bytes from
#      stdin before each prompt draws. This catches CSI 6n (and any other DSR)
#      from all sources (prompt-init, themes, the fixture's direct emitter).
remote_env_block='# BEGIN ghostty-zmx remote-env
if [[ -n "${SSH_CONNECTION:-}" && -z "${TERM_PROGRAM:-}" ]]; then
  export TERM_PROGRAM=ghostty
  export COLORTERM=truecolor
fi
# Suppress terminal-query-response leaks into zmx scrollback. The primary
# fix is laptop-side: the installer sets `osc-color-report-format = none` in
# the managed Ghostty config block so Ghostty never responds to OSC 4/10/11
# color queries, eliminating the OSC 11 response leak at the source. As a
# defense-in-depth measure for zsh-autosuggestions (which queries OSC 11 when
# the highlight style is unset), set an explicit style so the plugin skips its
# query. This does not affect the CSI 6n cursor-position response (no zsh-side
# emitter found on the tested hosts; handled by the laptop-side fix only if a
# future Ghostty release adds a DSR-disable option).
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=8"
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
  local file="$1"
  mkdir -p "${file:h}" 2>/dev/null || return 1
  touch "$file" || return 1
  validate_block_pairs "$file" "ghostty-zmx remote-env" || return 1
  strip_block "$file" "ghostty-zmx remote-env" || return 1
  {
    print ""
    print -r -- "$remote_env_block"
  } >> "$file"
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
  print "  - install files under $install_dir (session-manager.zsh, session-manager-lib.zsh, terminfo, ghostty-zmx-remote-layout)"
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

mkdir -p "$install_dir/terminfo" || exit 1
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
