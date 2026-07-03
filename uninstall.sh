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

[[ -n "${HOME:-}" ]] || { print -u2 "HOME is not set"; exit 1; }

install_dir="$HOME/.config/ghostty-zmx"
zshrc="$HOME/.zshrc"
zprofile="$HOME/.zprofile"
ghostty_config="${GHOSTTY_ZMX_INTERNAL_TEST_GHOSTTY_CONFIG:-$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty}"
data_home="${GHOSTTY_ZMX_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx}"
state_home="${GHOSTTY_ZMX_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-zmx}"
source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"'
early_source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager-early.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager-early.zsh"'
backup_counter=0

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

safe_remove_tree() {
  local target="$1"
  local label="$2"
  local resolved parent base
  if [[ -L "$target" ]]; then
    print -u2 "Refusing to delete $label path that is a symlink: $target"
    return 1
  fi
  [[ -d "$target" ]] || return 0
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

safe_remove_runtime_dir() {
  local root="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
  local expected="ghostty-zmx-${UID:-$(id -u)}"
  local dir="$root/$expected"
  local resolved parent base
  if [[ -L "$dir" ]]; then
    print -u2 "Refusing to delete runtime path that is a symlink: $dir"
    return 1
  fi
  [[ -d "$dir" ]] || return 0
  resolved="${dir:A}"
  parent="${resolved:h}"
  base="${resolved:t}"
  if [[ "$base" != "$expected" || "$resolved" == "/" || "$resolved" == "$HOME" || "$parent" == "/" ]]; then
    print -u2 "Refusing to delete unsafe runtime path: $dir"
    return 1
  fi
  if [[ ! -O "$resolved" ]]; then
    print -u2 "Refusing to delete runtime path not owned by current user: $dir"
    return 1
  fi
  rm -rf "$resolved"
  print "Deleted $resolved"
}

remove_source_line() {
  local file="$1" line="${2:-$source_line}"
  [[ -f "$file" ]] || return 0
  awk -v source_line="$line" '
    $0 == "# ghostty-zmx" { next }
    $0 == source_line { next }
    { print }
  ' "$file" > "${file}.tmp"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    rm -f "${file}.tmp"
    print -u2 "Failed to remove ghostty-zmx source line from $file"
    return 1
  fi
  mv "${file}.tmp" "$file"
  print "Removed ghostty-zmx source line from $file"
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

remove_ghostty_block() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  validate_managed_block_pairs "$file" || return 1
  awk '
    /^# BEGIN ghostty-zmx$/ { skip=1; next }
    /^# END ghostty-zmx$/ && skip { skip=0; next }
    !skip { print }
  ' "$file" > "${file}.tmp"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    rm -f "${file}.tmp"
    print -u2 "Failed to remove managed ghostty-zmx block from $file"
    return 1
  fi
  mv "${file}.tmp" "$file"
  print "Removed managed ghostty-zmx block from $file"
}

print "ghostty-zmx uninstall will remove shell/config integration. zmx sessions are left alive by default."
confirm "Continue?" || { print "Uninstall declined; no files changed."; exit 0; }

backup_file "$zshrc"
remove_source_line "$zshrc"
backup_file "$zprofile"
remove_source_line "$zprofile" "$early_source_line"
remove_source_line "$zprofile" "$source_line"

if confirm "Remove the managed ghostty-zmx block from Ghostty config?"; then
  backup_file "$ghostty_config"
  remove_ghostty_block "$ghostty_config"
else
  print "Left Ghostty config unchanged."
fi

safe_remove_runtime_dir || exit 1
print "Removed generated ghostty-zmx runtime files under the current per-user runtime directory."

if [[ -L "$install_dir" ]]; then
  print "Skipped installed-file removal because install path is a symlink: $install_dir"
else
  rm -f "$install_dir/session-manager.zsh" \
        "$install_dir/session-manager-lib.zsh" \
        "$install_dir/session-manager-early.zsh" \
        "$install_dir/session-manager-v0.1.zsh" \
        "$install_dir/ghostty-zmx" \
        "$install_dir/uninstall.sh" \
        "$install_dir/install-server.sh" \
        "$install_dir/terminfo/xterm-ghostty.terminfo" 2>/dev/null || true
  rmdir "$install_dir/terminfo" "$install_dir" 2>/dev/null || true
  print "Removed installed ghostty-zmx files under $install_dir where present."
fi

if [[ "$REMOVE_INSTALL_DIR" -eq 1 ]]; then
  safe_remove_tree "$install_dir" "install" || exit 1
else
  print "Left $install_dir in place if non-empty. Pass --remove-install-dir to delete it."
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
