#!/bin/zsh
# Shared helpers for ghostty-zmx installers and the `ghostty-zmx debug`
# subcommand. Sourced by install.sh, install-dev.sh, and the inline `debug`
# handler in the ghostty-zmx CLI wrapper. Keep side effects out of this file:
# only function definitions and the shared managed-block constant.

# The managed Ghostty config block. Written by install.sh into the stable
# Ghostty app-support config, and toggled by `ghostty-zmx debug on/off` to
# add/remove the GHOSTTY_ZMX_DEBUG line. install-dev.sh does NOT use this block
# (the tip install writes its own isolated config under XDG_CONFIG_HOME).
managed_block='# BEGIN ghostty-zmx
# Managed by ghostty-zmx. Re-run the installer to update this block.
env = GHOSTTY_ZMX_AUTO_ATTACH=1
window-save-state = never
confirm-close-surface = true
# END ghostty-zmx'

# Per-source-call backup counter so multiple edits in one run get distinct
# backup filenames. Callers may reset this (e.g. install-dev reuses it).
backup_counter=0

backup_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  backup_counter=$(( ${backup_counter:-0} + 1 ))
  local backup="${file}.ghostty-zmx.$(date +%Y%m%d-%H%M%S).$$.${backup_counter}.bak"
  cp "$file" "$backup" || { print -u2 "Failed to back up $file"; return 1; }
  print "Backed up $file to $backup"
}

# $1=prompt. Returns 0 (yes) or non-zero (no). Honors YES=1 for non-interactive.
confirm() {
  local prompt="$1"
  [[ "${YES:-0}" -eq 1 ]] && return 0
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

validate_install_dir() {
  if [[ -L "$install_dir" ]]; then
    print -u2 "Refusing to install into symlinked install directory: $install_dir"
    exit 1
  fi
  if [[ -e "$install_dir" && ! -d "$install_dir" ]]; then
    print -u2 "Refusing to install into non-directory install path: $install_dir"
    exit 1
  fi
}

ensure_source_line() {
  local file="$1" line="${2:-$source_line}"
  touch "$file" || return 1
  if grep -qxF "$line" "$file" 2>/dev/null; then
    print "Source line already present in $file"
    return 0
  fi
  {
    if [[ -s "$file" ]] && [[ -n "$(tail -n 1 "$file" 2>/dev/null)" ]]; then
      print ""
    fi
    print "# ghostty-zmx"
    print -r -- "$line"
  } >> "$file"
  print "Added ghostty-zmx source line to $file"
}

remove_source_line() {
  local file="$1" line="${2:-$source_line}"
  [[ -f "$file" ]] || return 0
  if ! grep -qxF "$line" "$file" 2>/dev/null; then
    return 0
  fi
  awk -v source_line="$line" '
    $0 == source_line { next }
    { print }
  ' "$file" > "${file}.tmp"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    rm -f "${file}.tmp"
    print -u2 "Failed to remove stale ghostty-zmx source line from $file"
    return 1
  fi
  mv "${file}.tmp" "$file" || return 1
  print "Removed stale ghostty-zmx source line from $file"
}

strip_managed_block() {
  local file="$1"
  awk '
    /^# BEGIN ghostty-zmx$/ { skip=1; next }
    /^# END ghostty-zmx$/ && skip { skip=0; next }
    skip { next }
    { print }
  ' "$file" > "${file}.tmp"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    rm -f "${file}.tmp"
    print -u2 "Failed to prepare Ghostty config $file"
    return 1
  fi
  mv "${file}.tmp" "$file"
}

validate_managed_block_pairs() {
  local file="$1" begins ends
  [[ -f "$file" ]] || return 0
  begins=$(awk '/^# BEGIN ghostty-zmx$/ { count++ } END { print count + 0 }' "$file") || return 1
  ends=$(awk '/^# END ghostty-zmx$/ { count++ } END { print count + 0 }' "$file") || return 1
  if [[ "$begins" -ne "$ends" ]]; then
    print -u2 "Refusing to edit $file: managed ghostty-zmx block is malformed (BEGIN count: $begins, END count: $ends)."
    return 1
  fi
}

warn_ghostty_conflicts() {
  local file="$1"
  local warned=0
  if grep -nE '^[[:space:]]*env[[:space:]]*=[[:space:]]*(GHOSTTY_ZMX_AUTO_ATTACH|ZMX_AUTO_ATTACH)=[^[:space:]]*[[:space:]]*$' "$file" >/dev/null 2>&1; then
    print "Warning: $file contains an auto-attach env setting outside the managed ghostty-zmx section; leaving it untouched."
    warned=1
  fi
  for key in window-save-state confirm-close-surface; do
    if grep -nE "^[[:space:]]*${key}[[:space:]]*=" "$file" >/dev/null 2>&1; then
      print "Warning: $file contains $key outside the managed ghostty-zmx section; leaving it untouched."
      warned=1
    fi
  done
  if grep -nE '^[[:space:]]*quit-after-last-window-closed[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$file" >/dev/null 2>&1; then
    print "Warning: quit-after-last-window-closed = true is unsupported by ghostty-zmx v0.1; remove it or set it to false."
    warned=1
  fi
  return $warned
}

ensure_ghostty_block() {
  local file="$1"
  mkdir -p "${file:h}" || return 1
  touch "$file" || return 1
  validate_managed_block_pairs "$file" || return 1
  strip_managed_block "$file" || return 1
  warn_ghostty_conflicts "$file" || true
  {
    print ""
    print -r -- "$managed_block"
  } >> "$file"
  print "Updated managed ghostty-zmx block in $file"
}

# Best-effort probe for the Ghostty 1.4.0 AppleScript `tty`/`pid` terminal
# capability (PR #11922). Warn but do not refuse — the manager early-sources
# the v0.1 fallback on 1.3.x surfaces so they keep unchanged v0.1 behavior.
probe_ghostty_capability() {
  local app_name="Ghostty"
  if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
    local bundle="${GHOSTTY_RESOURCES_DIR%/Contents/Resources/ghostty}"
    app_name="${bundle##*/}"
    app_name="${app_name%.app}"
  fi
  pgrep -if "Ghostty" >/dev/null 2>&1 || return 0
  if ! osascript -e "tell application \"$app_name\" to get tty of focused terminal of selected tab of front window" >/dev/null 2>&1; then
    print "Warning: the running Ghostty lacks the 1.4.0 tty/pid AppleScript capability."
    print "         Remote SSH/tsh features and tty-based identity will be inactive;"
    print "         surfaces on 1.3.x will use the v0.1 behavior (early-source fallback)."
    print "         Upgrade to Ghostty 1.4.0+ to enable v0.2 remote features."
  fi
}

# Refresh the vendored Ghostty terminfo from a running Ghostty bundle so the
# vendored copy always matches the installed Ghostty version. Falls back to the
# committed repo copy if no bundle is found.
refresh_vendored_terminfo() {
  local dest="$1" dest_dir="${1:h}" source_terminfo="${2:-}"
  mkdir -p "$dest_dir" 2>/dev/null || return 1
  local bundle terminfo_dir dumped=0 ghostty_resources="${GHOSTTY_RESOURCES_DIR:-}"
  for bundle in "$ghostty_resources" \
                "/Applications/Ghostty.app/Contents/Resources/ghostty" \
                "/Applications/Ghostty-tip.app/Contents/Resources/ghostty"; do
    [[ -n "$bundle" && -d "${bundle:h}/terminfo" ]] || continue
    terminfo_dir="${bundle:h}/terminfo"
    if TERMINFO="$terminfo_dir" infocmp -x xterm-ghostty >"${dest}.tmp" 2>/dev/null; then
      sed -i '' '1d' "${dest}.tmp" 2>/dev/null || sed -i '1d' "${dest}.tmp" 2>/dev/null
      mv "${dest}.tmp" "$dest" 2>/dev/null && dumped=1
      print "Refreshed vendored terminfo from ${bundle}"
      break
    fi
  done
  if [[ "$dumped" -ne 1 ]]; then
    [[ -n "$source_terminfo" && -r "$source_terminfo" ]] || return 1
    install -m 0644 "$source_terminfo" "$dest"
    print "Used committed vendored terminfo (no running Ghostty bundle found)"
  fi
}
