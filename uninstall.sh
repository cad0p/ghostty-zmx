#!/bin/zsh
set -u
setopt NULL_GLOB

YES=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --help|-h)
      print "Usage: uninstall.sh [--yes]"
      exit 0
      ;;
    *) print -u2 "Unknown argument: $arg"; exit 2 ;;
  esac
done

install_dir="$HOME/.config/ghostty-zmx"
zshrc="$HOME/.zshrc"
ghostty_config="${GHOSTTY_ZMX_GHOSTTY_CONFIG:-$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty}"
data_home="${GHOSTTY_ZMX_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx}"
state_home="${GHOSTTY_ZMX_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-zmx}"
source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"'

timestamp() { date +%Y%m%d-%H%M%S; }

backup_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local backup="${file}.ghostty-zmx.$(timestamp).bak"
  cp "$file" "$backup"
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

remove_source_line() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  grep -vxF "$source_line" "$file" > "${file}.tmp" 2>/dev/null || true
  mv "${file}.tmp" "$file"
  print "Removed ghostty-zmx source line from $file"
}

remove_ghostty_block() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk '
    /^# BEGIN ghostty-zmx$/ { skip=1; next }
    /^# END ghostty-zmx$/ && skip { skip=0; next }
    !skip { print }
  ' "$file" > "${file}.tmp"
  mv "${file}.tmp" "$file"
  print "Removed managed ghostty-zmx block from $file"
}

print "ghostty-zmx uninstall will remove shell/config integration. zmx sessions are left alive by default."
confirm "Continue?" || { print "Uninstall declined; no files changed."; exit 0; }

backup_file "$zshrc"
remove_source_line "$zshrc"

if confirm "Remove the managed ghostty-zmx block from Ghostty config?"; then
  backup_file "$ghostty_config"
  remove_ghostty_block "$ghostty_config"
else
  print "Left Ghostty config unchanged."
fi

command rm -rf /tmp/ghostty-zmx-restore-* /tmp/ghostty-zmx-restoring-* /tmp/ghostty-zmx-reaper-* /tmp/ghostty-zmx-reaper-*.zsh /tmp/ghostty-zmx-reaper-*.log 2>/dev/null || true
print "Removed generated ghostty-zmx runtime files under /tmp."

if confirm "Remove installed files under $install_dir?"; then
  rm -rf "$install_dir"
  print "Removed $install_dir"
else
  print "Left $install_dir in place."
fi

if [[ -d "$data_home" ]] && confirm "Delete data directory $data_home? This removes the managed sessions list."; then
  rm -rf "$data_home"
  print "Deleted $data_home"
else
  print "Left data directory in place."
fi

if [[ -d "$state_home" ]] && confirm "Delete state directory $state_home? This removes debug logs and saved scrollback snapshots."; then
  rm -rf "$state_home"
  print "Deleted $state_home"
else
  print "Left state directory in place."
fi

print "ghostty-zmx uninstall complete."
