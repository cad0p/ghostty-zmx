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
ghostty_config="${GHOSTTY_ZMX_GHOSTTY_CONFIG:-$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty}"
data_home="${GHOSTTY_ZMX_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx}"
old_data_home="${XDG_DATA_HOME:-$HOME/.local/share}/zmx"
source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"'
managed_block='# BEGIN ghostty-zmx
# Managed by ghostty-zmx. Re-run the installer to update this block.
env = GHOSTTY_ZMX_AUTO_ATTACH=1
window-save-state = never
confirm-close-surface = true
# END ghostty-zmx'

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

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    print -u2 "Missing required command: $cmd"
    exit 1
  fi
}

remove_experimental_zsh_block() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  awk '
    skip && /^# end zmx session management$/ { skip=0; next }
    /zmx session management/ { skip=1; changed=1; next }
    !skip { print }
    END { if (skip) exit 3; if (changed) exit 2; exit 0 }
  ' "$file" > "${file}.tmp"
  local rc=$?
  if [[ $rc -eq 3 ]]; then
    rm -f "${file}.tmp"
    print -u2 "Found an unterminated experimental zmx block in $file; leaving it unchanged."
    return 1
  fi
  if [[ $rc -eq 2 ]]; then
    mv "${file}.tmp" "$file"
    print "Removed experimental inline zmx block from $file"
  else
    rm -f "${file}.tmp"
  fi
}

ensure_source_line() {
  local file="$1"
  touch "$file"
  remove_experimental_zsh_block "$file" || true
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

strip_managed_block_and_experimental_env() {
  local file="$1"
  awk '
    /^# BEGIN ghostty-zmx$/ { skip=1; next }
    /^# END ghostty-zmx$/ && skip { skip=0; next }
    skip { next }
    /^[[:space:]]*env[[:space:]]*=[[:space:]]*ZMX_AUTO_ATTACH=1[[:space:]]*$/ { next }
    { print }
  ' "$file" > "${file}.tmp"
  mv "${file}.tmp" "$file"
}

warn_ghostty_conflicts() {
  local file="$1"
  local warned=0
  while IFS= read -r key; do
    if grep -nE "^[[:space:]]*${key}[[:space:]]*=" "$file" >/dev/null 2>&1; then
      print "Warning: $file contains $key outside the managed ghostty-zmx section; leaving it untouched."
      warned=1
    fi
  done <<'EOF'
env
window-save-state
confirm-close-surface
EOF
  if grep -nE '^[[:space:]]*quit-after-last-window-closed[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$file" >/dev/null 2>&1; then
    print "Warning: quit-after-last-window-closed = true is unsupported by ghostty-zmx v0.1; remove it or set it to false."
    warned=1
  fi
  return $warned
}

ensure_ghostty_block() {
  local file="$1"
  mkdir -p "${file:h}"
  touch "$file"
  strip_managed_block_and_experimental_env "$file"
  warn_ghostty_conflicts "$file" || true
  {
    print ""
    print -r -- "$managed_block"
  } >> "$file"
  print "Updated managed ghostty-zmx block in $file"
}

migrate_sessions() {
  local old_sessions="$old_data_home/sessions"
  local new_sessions="$data_home/sessions"
  [[ -f "$old_sessions" ]] || return 0
  mkdir -p "${new_sessions:h}"
  if [[ -f "$new_sessions" ]]; then
    print "Existing ghostty-zmx sessions file found at $new_sessions; leaving migrated copy unchanged."
  else
    cp "$old_sessions" "$new_sessions"
    print "Copied experimental sessions file to $new_sessions"
  fi
}

clean_old_runtime_flags() {
  command rm -rf /tmp/zmx-restore-* /tmp/zmx-restoring-* /tmp/zmx-reaper-* 2>/dev/null || true
  print "Removed stale experimental /tmp/zmx-* runtime flags."
}

print_plan() {
  print "ghostty-zmx installer will:"
  print "  - verify zmx, osascript, and zsh"
  print "  - install files under $install_dir"
  print "  - update $zshrc with one guarded source line"
  print "  - update only the managed ghostty-zmx section in $ghostty_config"
  print "  - migrate $old_data_home/sessions if present"
  print "  - remove stale experimental /tmp/zmx-* flags"
  print ""
  print "Managed Ghostty block to add:"
  print -r -- "$managed_block"
}

[[ -f "$source_manager" ]] || { print -u2 "Missing $source_manager"; exit 1; }
[[ -f "$source_uninstall" ]] || { print -u2 "Missing $source_uninstall"; exit 1; }

require_command zmx
require_command osascript
require_command zsh

print_plan
confirm "Apply this installation plan?" || { print "Installation declined; no files changed."; exit 0; }

mkdir -p "$install_dir"
install -m 0644 "$source_manager" "$manager_dest"
install -m 0755 "$source_uninstall" "$uninstall_dest"
print "Installed $manager_dest"
print "Installed $uninstall_dest"

backup_file "$zshrc"
ensure_source_line "$zshrc"

backup_file "$ghostty_config"
ensure_ghostty_block "$ghostty_config"

migrate_sessions
clean_old_runtime_flags

print ""
print "ghostty-zmx installation complete. Restart Ghostty or open a new Ghostty window to start managed sessions."
print "After testing the new integration, clean up old experimental files under $old_data_home and any old inline zmx config backups."
