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

[[ -n "${HOME:-}" ]] || { print -u2 "HOME is not set"; exit 1; }

repo_dir="${0:A:h}"
source_manager="$repo_dir/session-manager.zsh"
source_lib="$repo_dir/session-manager-lib.zsh"
source_install_lib="$repo_dir/install-lib.sh"
source_install_server_sub="$repo_dir/ghostty-zmx-install-server"
source_debug_sub="$repo_dir/ghostty-zmx-debug"
source_package_json="$repo_dir/package.json"
source_early_manager="$repo_dir/session-manager-early.zsh"
source_v01_manager="$repo_dir/session-manager-v0.1.zsh"
source_wrapper="$repo_dir/ghostty-zmx"
source_uninstall="$repo_dir/uninstall.sh"
source_server_install="$repo_dir/install-server.sh"
source_remote_layout="$repo_dir/ghostty-zmx-remote-layout"
source_terminfo="$repo_dir/terminfo/xterm-ghostty.terminfo"
install_dir="$HOME/.config/ghostty-zmx"
manager_dest="$install_dir/session-manager.zsh"
lib_dest="$install_dir/session-manager-lib.zsh"
install_lib_dest="$install_dir/install-lib.sh"
install_server_sub_dest="$install_dir/ghostty-zmx-install-server"
debug_sub_dest="$install_dir/ghostty-zmx-debug"
early_manager_dest="$install_dir/session-manager-early.zsh"
v01_manager_dest="$install_dir/session-manager-v0.1.zsh"
wrapper_dest="$install_dir/ghostty-zmx"
uninstall_dest="$install_dir/uninstall.sh"
server_install_dest="$install_dir/install-server.sh"
remote_layout_dest="$install_dir/ghostty-zmx-remote-layout"
terminfo_dest="$install_dir/terminfo/xterm-ghostty.terminfo"
zshrc="$HOME/.zshrc"
zprofile="$HOME/.zprofile"
ghostty_config="${GHOSTTY_ZMX_INTERNAL_TEST_GHOSTTY_CONFIG:-$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty}"
source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"'
early_source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager-early.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager-early.zsh"'

# Shared helpers (backup_file, confirm, require_command, validate_install_dir,
# ensure/remove_source_line, strip_managed_block, ensure_ghostty_block,
# probe_ghostty_capability, refresh_vendored_terminfo, managed_block constant).
# Sourced by install.sh, install-dev.sh, and the `ghostty-zmx debug` subcommand.
source "${0:A:h}/install-lib.sh"

print_plan() {
  print "ghostty-zmx installer will:"
  print "  - verify zmx, osascript, and zsh"
  print "  - install files under $install_dir"
  print "  - refresh the vendored Ghostty terminfo from the installed Ghostty"
  print "  - update $zshrc with one guarded source line"
  print "  - update $zprofile with an early-inherit guarded source line"
  print "  - update only the managed ghostty-zmx section in $ghostty_config"
  print "  - warn about unsupported or conflicting Ghostty settings outside the managed section"
  print ""
  print "To enable remote panes, run: ghostty-zmx install-server <host> on each remote host."
  print ""
  print "Managed Ghostty block to add:"
  print -r -- "$managed_block"
}

[[ -f "$source_manager" ]] || { print -u2 "Missing $source_manager"; exit 1; }
[[ -f "$source_lib" ]] || { print -u2 "Missing $source_lib"; exit 1; }
[[ -f "$source_install_lib" ]] || { print -u2 "Missing $source_install_lib"; exit 1; }
[[ -f "$source_install_server_sub" ]] || { print -u2 "Missing $source_install_server_sub"; exit 1; }
[[ -f "$source_debug_sub" ]] || { print -u2 "Missing $source_debug_sub"; exit 1; }
[[ -f "$source_package_json" ]] || { print -u2 "Missing $source_package_json"; exit 1; }
[[ -f "$source_early_manager" ]] || { print -u2 "Missing $source_early_manager"; exit 1; }
[[ -f "$source_v01_manager" ]] || { print -u2 "Missing $source_v01_manager"; exit 1; }
[[ -f "$source_wrapper" ]] || { print -u2 "Missing $source_wrapper"; exit 1; }
[[ -f "$source_uninstall" ]] || { print -u2 "Missing $source_uninstall"; exit 1; }
[[ -f "$source_server_install" ]] || { print -u2 "Missing $source_server_install"; exit 1; }
[[ -f "$source_remote_layout" ]] || { print -u2 "Missing $source_remote_layout"; exit 1; }
[[ -f "$source_terminfo" ]] || { print -u2 "Missing $source_terminfo"; exit 1; }

require_command zmx
require_command osascript
require_command zsh
validate_install_dir

# Best-effort capability probe. Warn (do not refuse) if the running Ghostty
# lacks the 1.4.0 tty/pid AppleScript capability — remote features and
# tty-based identity will be inactive, and 1.3.x surfaces fall back to v0.1.
probe_ghostty_capability

print_plan
confirm "Apply this installation plan?" || { print "Installation declined; no files changed."; exit 0; }

backup_file "$zshrc"
ensure_source_line "$zshrc" || exit 1
backup_file "$zprofile"
# v0.2.0-rc migrated the early inherit hook from the full manager to a
# dedicated .zprofile entry. Older development/prerelease installs may have
# sourced session-manager.zsh from .zprofile; remove that stale line so the
# full manager is not loaded before the early hook.
remove_source_line "$zprofile" "$source_line" || exit 1
ensure_source_line "$zprofile" "$early_source_line" || exit 1

validate_install_dir
mkdir -p "$install_dir" || exit 1
validate_install_dir
install -m 0644 "$source_manager" "$manager_dest" || exit 1
install -m 0644 "$source_lib" "$lib_dest" || exit 1
install -m 0644 "$source_install_lib" "$install_lib_dest" || exit 1
install -m 0755 "$source_install_server_sub" "$install_server_sub_dest" || exit 1
install -m 0755 "$source_debug_sub" "$debug_sub_dest" || exit 1
install -m 0644 "$source_package_json" "$install_dir/package.json" || exit 1
install -m 0644 "$source_early_manager" "$early_manager_dest" || exit 1
install -m 0644 "$source_v01_manager" "$v01_manager_dest" || exit 1
install -m 0755 "$source_wrapper" "$wrapper_dest" || exit 1
install -m 0755 "$source_uninstall" "$uninstall_dest" || exit 1
install -m 0755 "$source_server_install" "$server_install_dest" || exit 1
install -m 0755 "$source_remote_layout" "$remote_layout_dest" || exit 1
# Refresh the vendored Ghostty terminfo from the installed Ghostty at install
# time so the copy always matches the laptop's Ghostty version (per the v0.2
# design, "Vendored terminfo staleness"). If infocmp against the installed
# Ghostty fails, fall back to the repo's committed copy.
refresh_vendored_terminfo "$terminfo_dest" "$source_terminfo" || exit 1
print "Installed $manager_dest"
print "Installed $lib_dest"
print "Installed $install_lib_dest"
print "Installed $install_server_sub_dest"
print "Installed $debug_sub_dest"
print "Installed $install_dir/package.json"
print "Installed $early_manager_dest"
print "Installed $v01_manager_dest"
print "Installed $wrapper_dest"
print "Installed $uninstall_dest"
print "Installed $server_install_dest"
print "Installed $remote_layout_dest"
print "Installed $terminfo_dest"

backup_file "$ghostty_config"
ensure_ghostty_block "$ghostty_config"

print ""
print "ghostty-zmx installation complete. Restart Ghostty or open a new Ghostty window to start managed sessions."
