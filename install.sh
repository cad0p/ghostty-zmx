#!/bin/zsh
set -u
setopt NULL_GLOB

YES=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --help|-h)
      print "Usage: ./install.sh [--yes]"
      exit 0
      ;;
    *) print -u2 "Unknown argument: $arg"; exit 2 ;;
  esac
done

repo_dir="${0:A:h}"
source_manager="$repo_dir/session-manager.zsh"
source_uninstall="$repo_dir/uninstall.sh"
install_dir="$HOME/.config/ghostty-zmx"
manager_dest="$install_dir/session-manager.zsh"
uninstall_dest="$install_dir/uninstall.sh"
zshrc="$HOME/.zshrc"
ghostty_config="${GHOSTTY_ZMX_INTERNAL_TEST_GHOSTTY_CONFIG:-$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty}"
source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"'
backup_counter=0
managed_block='# BEGIN ghostty-zmx
# Managed by ghostty-zmx. Re-run the installer to update this block.
env = GHOSTTY_ZMX_AUTO_ATTACH=1
window-save-state = never
confirm-close-surface = true
# END ghostty-zmx'

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
  strip_managed_block "$file" || return 1
  warn_ghostty_conflicts "$file" || true
  {
    print ""
    print -r -- "$managed_block"
  } >> "$file"
  print "Updated managed ghostty-zmx block in $file"
}

print_plan() {
  print "ghostty-zmx installer will:"
  print "  - verify zmx, osascript, and zsh"
  print "  - install files under $install_dir"
  print "  - update $zshrc with one guarded source line"
  print "  - update only the managed ghostty-zmx section in $ghostty_config"
  print "  - warn about unsupported or conflicting Ghostty settings outside the managed section"
  print ""
  print "Managed Ghostty block to add:"
  print -r -- "$managed_block"
}

[[ -f "$source_manager" ]] || { print -u2 "Missing $source_manager"; exit 1; }
[[ -f "$source_uninstall" ]] || { print -u2 "Missing $source_uninstall"; exit 1; }

require_command zmx
require_command osascript
require_command zsh
refuse_symlinked_install_dir

print_plan
confirm "Apply this installation plan?" || { print "Installation declined; no files changed."; exit 0; }

backup_file "$zshrc"
ensure_source_line "$zshrc" || exit 1

mkdir -p "$install_dir"
install -m 0644 "$source_manager" "$manager_dest"
install -m 0755 "$source_uninstall" "$uninstall_dest"
print "Installed $manager_dest"
print "Installed $uninstall_dest"

backup_file "$ghostty_config"
ensure_ghostty_block "$ghostty_config"

print ""
print "ghostty-zmx installation complete. Restart Ghostty or open a new Ghostty window to start managed sessions."
