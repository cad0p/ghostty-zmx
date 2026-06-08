#!/bin/zsh
set -u
setopt NULL_GLOB

YES=0
REMOVE_INSTALL_DIR=0
REMOVE_DATA=0
REMOVE_STATE=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --remove-install-dir) REMOVE_INSTALL_DIR=1 ;;
    --remove-data) REMOVE_DATA=1 ;;
    --remove-state) REMOVE_STATE=1 ;;
    --help|-h)
      print "Usage: uninstall.sh [--yes] [--remove-install-dir] [--remove-data] [--remove-state]"
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

safe_remove_tree() {
  local target="$1"
  local label="$2"
  local resolved parent base
  [[ -n "$target" && -d "$target" ]] || return 0
  resolved="${target:A}"
  parent="${resolved:h}"
  base="${resolved:t}"
  if [[ "$base" != "ghostty-zmx" || "$resolved" == "/" || "$resolved" == "$HOME" || "$parent" == "/" ]]; then
    print -u2 "Refusing to delete unsafe $label path: $target"
    return 1
  fi
  if [[ ! -O "$resolved" ]]; then
    print -u2 "Refusing to delete $label path not owned by current user: $target"
    return 1
  fi
  rm -rf "$resolved"
  print "Deleted $resolved"
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

if [[ "$REMOVE_INSTALL_DIR" -eq 1 ]]; then
  safe_remove_tree "$install_dir" "install" || exit 1
else
  print "Left $install_dir in place. Pass --remove-install-dir to delete it."
fi

if [[ "$REMOVE_DATA" -eq 1 ]]; then
  safe_remove_tree "$data_home" "data" || exit 1
else
  print "Left data directory in place. Pass --remove-data to delete it."
fi

if [[ "$REMOVE_STATE" -eq 1 ]]; then
  safe_remove_tree "$state_home" "state" || exit 1
else
  print "Left state directory in place. Pass --remove-state to delete it."
fi

print "ghostty-zmx uninstall complete."
