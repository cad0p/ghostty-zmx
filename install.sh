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
source_lib="$repo_dir/session-manager-lib.zsh"
source_early_manager="$repo_dir/session-manager-early.zsh"
source_v01_manager="$repo_dir/session-manager-v0.1.zsh"
source_wrapper="$repo_dir/ghostty-zmx"
source_uninstall="$repo_dir/uninstall.sh"
source_server_install="$repo_dir/install-server.sh"
source_terminfo="$repo_dir/terminfo/xterm-ghostty.terminfo"
install_dir="$HOME/.config/ghostty-zmx"
manager_dest="$install_dir/session-manager.zsh"
lib_dest="$install_dir/session-manager-lib.zsh"
early_manager_dest="$install_dir/session-manager-early.zsh"
v01_manager_dest="$install_dir/session-manager-v0.1.zsh"
wrapper_dest="$install_dir/ghostty-zmx"
uninstall_dest="$install_dir/uninstall.sh"
server_install_dest="$install_dir/install-server.sh"
terminfo_dest="$install_dir/terminfo/xterm-ghostty.terminfo"
zshrc="$HOME/.zshrc"
zprofile="$HOME/.zprofile"
ghostty_config="${GHOSTTY_ZMX_INTERNAL_TEST_GHOSTTY_CONFIG:-$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty}"
source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"'
early_source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager-early.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager-early.zsh"'
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
  local file="$1" line="${2:-$source_line}"
  touch "$file" || return 1
  if grep -qxF "$line" "$file" 2>/dev/null; then
    print "Source line already present in $file"
    return 0
  fi
  {
    print ""
    print "# ghostty-zmx"
    print -r -- "$line"
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

# Best-effort probe for the Ghostty 1.4.0 AppleScript `tty`/`pid` terminal
# capability (PR #11922). The v0.2 remote features and tty-based identity
# require it. We probe capability (does the hosting app respond to `tty of
# focused terminal`?) rather than parsing TERM_PROGRAM_VERSION, because
# pre-release dev builds (e.g. a tip build) already carry the 1.4.0 features
# while reporting a 1.3.x version string. Warn but do not refuse — the
# manager early-sources the v0.1 fallback on 1.3.x surfaces so they keep
# unchanged v0.1 behavior. Only warn if a Ghostty app is actually running
# but lacks the property; a not-yet-running Ghostty is not a warning.
probe_ghostty_capability() {
  local app_name="Ghostty"
  if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
    local bundle="${GHOSTTY_RESOURCES_DIR%/Contents/Resources/ghostty}"
    app_name="${bundle##*/}"
    app_name="${app_name%.app}"
  fi
  # If no Ghostty app is running, osascript launches it; detect that by
  # checking the running process list first so we don't false-alarm.
  pgrep -if "Ghostty" >/dev/null 2>&1 || return 0
  if ! osascript -e "tell application \"$app_name\" to get tty of focused terminal of selected tab of front window" >/dev/null 2>&1; then
    print "Warning: the running Ghostty lacks the 1.4.0 tty/pid AppleScript capability."
    print "         Remote SSH/tsh features and tty-based identity will be inactive;"
    print "         surfaces on 1.3.x will use the v0.1 behavior (early-source fallback)."
    print "         Upgrade to Ghostty 1.4.0+ to enable v0.2 remote features."
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

# Refresh the vendored Ghostty terminfo from the installed Ghostty at install
# time so the vendored copy always matches the laptop's Ghostty version. If a
# running Ghostty bundle is found, dump its compiled xterm-ghostty entry to the
# source form via infocmp; otherwise fall back to the repo's committed copy.
refresh_vendored_terminfo() {
  local dest="$1" dest_dir="${1:h}"
  mkdir -p "$dest_dir" 2>/dev/null || return 1
  local bundle terminfo_dir dumped=0 ghostty_resources="${GHOSTTY_RESOURCES_DIR:-}"
  for bundle in "$ghostty_resources" \
                "/Applications/Ghostty.app/Contents/Resources/ghostty" \
                "/Applications/Ghostty-tip.app/Contents/Resources/ghostty"; do
    [[ -n "$bundle" && -d "${bundle:h}/terminfo" ]] || continue
    terminfo_dir="${bundle:h}/terminfo"
    if TERMINFO="$terminfo_dir" infocmp -x xterm-ghostty >"${dest}.tmp" 2>/dev/null; then
      # Drop the "Reconstructed via infocmp from file:" comment line so the
      # file is portable and stable across hosts.
      sed -i '' '1d' "${dest}.tmp" 2>/dev/null || sed -i '1d' "${dest}.tmp" 2>/dev/null
      mv "${dest}.tmp" "$dest" 2>/dev/null && dumped=1
      print "Refreshed vendored terminfo from ${bundle}"
      break
    fi
  done
  if [[ "$dumped" -ne 1 ]]; then
    install -m 0644 "$source_terminfo" "$dest"
    print "Used committed vendored terminfo (no running Ghostty bundle found)"
  fi
}

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
  print "To enable remote panes, copy install-server.sh to each remote host and run it."
  print ""
  print "Managed Ghostty block to add:"
  print -r -- "$managed_block"
}

[[ -f "$source_manager" ]] || { print -u2 "Missing $source_manager"; exit 1; }
[[ -f "$source_lib" ]] || { print -u2 "Missing $source_lib"; exit 1; }
[[ -f "$source_early_manager" ]] || { print -u2 "Missing $source_early_manager"; exit 1; }
[[ -f "$source_v01_manager" ]] || { print -u2 "Missing $source_v01_manager"; exit 1; }
[[ -f "$source_wrapper" ]] || { print -u2 "Missing $source_wrapper"; exit 1; }
[[ -f "$source_uninstall" ]] || { print -u2 "Missing $source_uninstall"; exit 1; }
[[ -f "$source_server_install" ]] || { print -u2 "Missing $source_server_install"; exit 1; }
[[ -f "$source_terminfo" ]] || { print -u2 "Missing $source_terminfo"; exit 1; }

require_command zmx
require_command osascript
require_command zsh
refuse_symlinked_install_dir

# Best-effort capability probe. Warn (do not refuse) if the running Ghostty
# lacks the 1.4.0 tty/pid AppleScript capability — remote features and
# tty-based identity will be inactive, and 1.3.x surfaces fall back to v0.1.
probe_ghostty_capability

print_plan
confirm "Apply this installation plan?" || { print "Installation declined; no files changed."; exit 0; }

backup_file "$zshrc"
ensure_source_line "$zshrc" || exit 1
backup_file "$zprofile"
ensure_source_line "$zprofile" "$early_source_line" || exit 1

mkdir -p "$install_dir"
if [[ -L "$install_dir" ]]; then
  print -u2 "Refusing to install into symlinked install directory: $install_dir"
  exit 1
fi
install -m 0644 "$source_manager" "$manager_dest"
install -m 0644 "$source_lib" "$lib_dest"
install -m 0644 "$source_early_manager" "$early_manager_dest"
install -m 0644 "$source_v01_manager" "$v01_manager_dest"
install -m 0755 "$source_wrapper" "$wrapper_dest"
install -m 0755 "$source_uninstall" "$uninstall_dest"
install -m 0755 "$source_server_install" "$server_install_dest"
# Refresh the vendored Ghostty terminfo from the installed Ghostty at install
# time so the copy always matches the laptop's Ghostty version (per the v0.2
# design, "Vendored terminfo staleness"). If infocmp against the installed
# Ghostty fails, fall back to the repo's committed copy.
refresh_vendored_terminfo "$terminfo_dest"
print "Installed $manager_dest"
print "Installed $lib_dest"
print "Installed $early_manager_dest"
print "Installed $v01_manager_dest"
print "Installed $wrapper_dest"
print "Installed $uninstall_dest"
print "Installed $server_install_dest"
print "Installed $terminfo_dest"

backup_file "$ghostty_config"
ensure_ghostty_block "$ghostty_config"

print ""
print "ghostty-zmx installation complete. Restart Ghostty or open a new Ghostty window to start managed sessions."
