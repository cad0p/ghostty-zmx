#!/usr/bin/env zsh
# Prepare an isolated Ghostty-tip app bundle and optional live ghostty-zmx dev
# install for E2E/manual testing.
#
# This never installs Homebrew's ghostty@tip cask because that cask conflicts
# with stable Ghostty and targets /Applications/Ghostty.app. Instead it copies
# a downloaded tip DMG's Ghostty.app to /Applications/Ghostty-tip.app, rewrites
# only the copied bundle identity to Ghostty-tip, ad-hoc signs it, and registers
# it with LaunchServices so AppleScript can address "Ghostty-tip".
#
# With --install-live, this also installs the checkout's ghostty-zmx files into
# ~/.config/ghostty-zmx-tip and writes isolated Ghostty-tip config/zdotdir files.
# It never edits stable Ghostty config or global ~/.zshrc / ~/.zprofile.
set -eu

emulate -L zsh
setopt no_sh_word_split

local target="${GZMX_E2E_GHOSTTY_TIP_APP:-/Applications/Ghostty-tip.app}"
local app_name="${GZMX_E2E_GHOSTTY_TIP_NAME:-Ghostty-tip}"
local bundle_id="${GZMX_E2E_GHOSTTY_TIP_BUNDLE_ID:-com.mitchellh.ghostty.tip}"
local dmg="${GZMX_E2E_GHOSTTY_TIP_DMG:-}"
local url="${GZMX_E2E_GHOSTTY_TIP_URL:-}"
local sha="${GZMX_E2E_GHOSTTY_TIP_SHA256:-}"
local replace="${GZMX_E2E_GHOSTTY_TIP_REPLACE:-0}"
local install_live=0
local repo_dir="${0:A:h:h}"
local install_dir="${GZMX_E2E_GHOSTTY_TIP_INSTALL_DIR:-$HOME/.config/ghostty-zmx-tip}"
local tip_config_dir="${GZMX_E2E_GHOSTTY_TIP_CONFIG_DIR:-$HOME/.config/ghostty-tip}"
local tip_zdotdir="${GZMX_E2E_GHOSTTY_TIP_ZDOTDIR:-$HOME/.config/ghostty-tip-zdotdir}"
local tip_data_home="${GZMX_E2E_GHOSTTY_TIP_DATA_HOME:-$HOME/.local/share/ghostty-zmx-tip}"
local tip_state_home="${GZMX_E2E_GHOSTTY_TIP_STATE_HOME:-$HOME/.local/state/ghostty-zmx-tip}"
local tip_path="${GZMX_E2E_GHOSTTY_TIP_PATH:-$HOME/.local/bin:$HOME/.toolbox/bin:/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin}"
local tip_config="$tip_config_dir/config.ghostty"
local tip_launcher="$tip_config_dir/open-ghostty-tip.zsh"
local mount_dir=""

usage() {
  cat <<'EOF'
Usage: e2e/setup-ghostty-tip.zsh [--install-live]

Options:
  --install-live                   Install this checkout for Ghostty-tip-only testing

Environment:
  GZMX_E2E_GHOSTTY_TIP_APP       Target app, default /Applications/Ghostty-tip.app
  GZMX_E2E_GHOSTTY_TIP_DMG       Existing Ghostty tip DMG to copy from
  GZMX_E2E_GHOSTTY_TIP_URL       Download URL for Ghostty tip DMG
  GZMX_E2E_GHOSTTY_TIP_SHA256    Optional SHA-256 for the DMG
  GZMX_E2E_GHOSTTY_TIP_REPLACE=1 Replace existing target app before copying
  GZMX_E2E_GHOSTTY_TIP_INSTALL_DIR
                                  Live ghostty-zmx install dir, default ~/.config/ghostty-zmx-tip
  GZMX_E2E_GHOSTTY_TIP_CONFIG_DIR Isolated Ghostty-tip config dir, default ~/.config/ghostty-tip
  GZMX_E2E_GHOSTTY_TIP_ZDOTDIR    Isolated Ghostty-tip ZDOTDIR, default ~/.config/ghostty-tip-zdotdir
  GZMX_E2E_GHOSTTY_TIP_DATA_HOME  Isolated data dir, default ~/.local/share/ghostty-zmx-tip
  GZMX_E2E_GHOSTTY_TIP_STATE_HOME Isolated state dir, default ~/.local/state/ghostty-zmx-tip
  GZMX_E2E_GHOSTTY_TIP_PATH       Spotlight/app-launch PATH for proxy commands

If the target app already exists and no DMG/URL is provided, the script only
ensures the copied app has the isolated Ghostty-tip identity and signature.

--install-live copies this checkout into ~/.config/ghostty-zmx-tip, refreshes the
vendored terminfo from /Applications/Ghostty-tip.app, and writes only isolated
Ghostty-tip config/zdotdir files. It never touches stable Ghostty config,
/Applications/Ghostty.app, ~/.zshrc, or ~/.zprofile.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --install-live) install_live=1; shift ;;
    *) print -u2 "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

[[ "$target" == */Ghostty-tip.app ]] || {
  print -u2 "Refusing target that is not named Ghostty-tip.app: $target"
  exit 1
}
[[ "$target" != "/Applications/Ghostty.app" ]] || {
  print -u2 "Refusing to touch stable Ghostty: $target"
  exit 1
}
if [[ -e "/Applications/Ghostty.app" && "${target:A}" == "/Applications/Ghostty.app" ]]; then
  print -u2 "Refusing target that resolves to stable Ghostty: $target"
  exit 1
fi
[[ "$tip_config" != "$HOME/.config/ghostty/config"* ]] || {
  print -u2 "Refusing Ghostty-tip config path under stable Ghostty config: $tip_config"
  exit 1
}
[[ "$tip_config" != "$HOME/Library/Application Support/com.mitchellh.ghostty/"* ]] || {
  print -u2 "Refusing Ghostty-tip config path under stable Ghostty app-support config: $tip_config"
  exit 1
}
[[ "$tip_zdotdir" != "$HOME" && "$tip_zdotdir" != "$HOME/" ]] || {
  print -u2 "Refusing to use HOME as Ghostty-tip ZDOTDIR"
  exit 1
}
[[ "$tip_data_home" != "${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx" ]] || {
  print -u2 "Refusing to use default/stable ghostty-zmx data dir for Ghostty-tip: $tip_data_home"
  exit 1
}
[[ "$tip_state_home" != "${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-zmx" ]] || {
  print -u2 "Refusing to use default/stable ghostty-zmx state dir for Ghostty-tip: $tip_state_home"
  exit 1
}

cleanup() {
  [[ -n "$mount_dir" && -d "$mount_dir" ]] && hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM HUP

install_live_files() {
  emulate -L zsh
  setopt local_options no_sh_word_split

  local -a required=(
    session-manager.zsh
    session-manager-lib.zsh
    session-manager-early.zsh
    session-manager-v0.1.zsh
    ghostty-zmx
    uninstall.sh
    install-server.sh
    ghostty-zmx-remote-layout
    terminfo/xterm-ghostty.terminfo
  )
  local f
  for f in "${required[@]}"; do
    [[ -r "$repo_dir/$f" ]] || { print -u2 "Missing checkout file: $repo_dir/$f"; exit 1; }
  done

  mkdir -p "$install_dir/terminfo" "$tip_config_dir" "$tip_zdotdir" "$tip_data_home" "$tip_state_home"
  install -m 0644 "$repo_dir/session-manager.zsh" "$install_dir/session-manager.zsh"
  install -m 0644 "$repo_dir/session-manager-lib.zsh" "$install_dir/session-manager-lib.zsh"
  install -m 0644 "$repo_dir/session-manager-early.zsh" "$install_dir/session-manager-early.zsh"
  install -m 0644 "$repo_dir/session-manager-v0.1.zsh" "$install_dir/session-manager-v0.1.zsh"
  install -m 0755 "$repo_dir/ghostty-zmx" "$install_dir/ghostty-zmx"
  install -m 0755 "$repo_dir/uninstall.sh" "$install_dir/uninstall.sh"
  install -m 0755 "$repo_dir/install-server.sh" "$install_dir/install-server.sh"
  install -m 0755 "$repo_dir/ghostty-zmx-remote-layout" "$install_dir/ghostty-zmx-remote-layout"

  local tip_terminfo="$target/Contents/Resources/terminfo"
  if [[ -d "$tip_terminfo" ]] && TERMINFO="$tip_terminfo" infocmp -x xterm-ghostty >"$install_dir/terminfo/xterm-ghostty.terminfo.tmp" 2>/dev/null; then
    sed -i '' '1d' "$install_dir/terminfo/xterm-ghostty.terminfo.tmp" 2>/dev/null || sed -i '1d' "$install_dir/terminfo/xterm-ghostty.terminfo.tmp" 2>/dev/null
    mv "$install_dir/terminfo/xterm-ghostty.terminfo.tmp" "$install_dir/terminfo/xterm-ghostty.terminfo"
    print "Refreshed vendored terminfo from $target"
  else
    rm -f "$install_dir/terminfo/xterm-ghostty.terminfo.tmp" 2>/dev/null || true
    install -m 0644 "$repo_dir/terminfo/xterm-ghostty.terminfo" "$install_dir/terminfo/xterm-ghostty.terminfo"
    print "Warning: could not read Ghostty-tip terminfo; used checkout terminfo"
  fi

  cat > "$tip_config" <<EOF
# ghostty-tip isolated ghostty-zmx config
env = ZDOTDIR=$tip_zdotdir
env = GHOSTTY_ZMX_APP_NAME=$app_name
env = GHOSTTY_ZMX_AUTO_ATTACH=1
env = GHOSTTY_ZMX_INSTALL_DIR=$install_dir
env = GHOSTTY_ZMX_DATA_HOME=$tip_data_home
env = GHOSTTY_ZMX_STATE_HOME=$tip_state_home
env = PATH=$tip_path
window-save-state = never
confirm-close-surface = true
EOF

  cat > "$tip_zdotdir/.zprofile" <<EOF
# ghostty-tip isolated zprofile for ghostty-zmx
typeset _gzmx_tip_saved_auto_attach="\${GHOSTTY_ZMX_AUTO_ATTACH-}"
typeset -i _gzmx_tip_had_auto_attach="\${+GHOSTTY_ZMX_AUTO_ATTACH}"
export GHOSTTY_ZMX_AUTO_ATTACH=0
[[ -r "$HOME/.zprofile" ]] && source "$HOME/.zprofile"
if (( _gzmx_tip_had_auto_attach )); then
  export GHOSTTY_ZMX_AUTO_ATTACH="\$_gzmx_tip_saved_auto_attach"
else
  unset GHOSTTY_ZMX_AUTO_ATTACH
fi
unset _gzmx_tip_saved_auto_attach _gzmx_tip_had_auto_attach
unset _GHOSTTY_ZMX_LIB_SOURCED
[[ -r ${(qqq)install_dir}/session-manager-early.zsh ]] && source ${(qqq)install_dir}/session-manager-early.zsh
EOF

  cat > "$tip_zdotdir/.zshrc" <<EOF
# ghostty-tip isolated zshrc for ghostty-zmx
typeset _gzmx_tip_saved_auto_attach="\${GHOSTTY_ZMX_AUTO_ATTACH-}"
typeset -i _gzmx_tip_had_auto_attach="\${+GHOSTTY_ZMX_AUTO_ATTACH}"
typeset _gzmx_tip_saved_p9k_instant="\${POWERLEVEL9K_INSTANT_PROMPT-}"
typeset -i _gzmx_tip_had_p9k_instant="\${+POWERLEVEL9K_INSTANT_PROMPT}"
export GHOSTTY_ZMX_AUTO_ATTACH=0
export POWERLEVEL9K_INSTANT_PROMPT=off
[[ -r "$HOME/.zshrc" ]] && source "$HOME/.zshrc"
if (( _gzmx_tip_had_p9k_instant )); then
  export POWERLEVEL9K_INSTANT_PROMPT="\$_gzmx_tip_saved_p9k_instant"
else
  unset POWERLEVEL9K_INSTANT_PROMPT
fi
if (( _gzmx_tip_had_auto_attach )); then
  export GHOSTTY_ZMX_AUTO_ATTACH="\$_gzmx_tip_saved_auto_attach"
else
  unset GHOSTTY_ZMX_AUTO_ATTACH
fi
unset _gzmx_tip_saved_auto_attach _gzmx_tip_had_auto_attach _gzmx_tip_saved_p9k_instant _gzmx_tip_had_p9k_instant
unset _GHOSTTY_ZMX_LIB_SOURCED
[[ -r ${(qqq)install_dir}/session-manager.zsh ]] && source ${(qqq)install_dir}/session-manager.zsh
EOF

  cat > "$tip_launcher" <<EOF
#!/bin/zsh
exec open -F -n -a ${(q)app_name} --args \\
  --config-default-files=false \\
  --config-file=${(q)tip_config}
EOF
  chmod 0755 "$tip_launcher"

  print "Ghostty-tip live ghostty-zmx install ready:"
  print "  install dir: $install_dir"
  print "  config:      $tip_config"
  print "  zdotdir:     $tip_zdotdir"
  print "  data home:   $tip_data_home"
  print "  state home:  $tip_state_home"
  print "  launcher:    $tip_launcher"
  print ""
  print "Launch with:"
  print "  $tip_launcher"
  print "or:"
  print "  open -F -n -a ${(q)app_name} --args --config-default-files=false --config-file=${(q)tip_config}"
}

configure_tip_bundle_environment() {
  emulate -L zsh
  setopt local_options no_sh_word_split

  local plist="$target/Contents/Info.plist"
  local buddy="/usr/libexec/PlistBuddy"
  [[ -x "$buddy" ]] || { print -u2 "PlistBuddy not found"; exit 1; }

  "$buddy" -c "Print :LSEnvironment" "$plist" >/dev/null 2>&1 ||
    "$buddy" -c "Add :LSEnvironment dict" "$plist"
  "$buddy" -c "Set :LSEnvironment:GHOSTTY_MAC_LAUNCH_SOURCE app" "$plist" >/dev/null 2>&1 ||
    "$buddy" -c "Add :LSEnvironment:GHOSTTY_MAC_LAUNCH_SOURCE string app" "$plist"

  local key value
  for key value in \
    ZDOTDIR "$tip_zdotdir" \
    GHOSTTY_ZMX_APP_NAME "$app_name" \
    GHOSTTY_ZMX_AUTO_ATTACH 1 \
    GHOSTTY_ZMX_INSTALL_DIR "$install_dir" \
    GHOSTTY_ZMX_DATA_HOME "$tip_data_home" \
    GHOSTTY_ZMX_STATE_HOME "$tip_state_home" \
    PATH "$tip_path"; do
    "$buddy" -c "Set :LSEnvironment:$key $value" "$plist" >/dev/null 2>&1 ||
      "$buddy" -c "Add :LSEnvironment:$key string $value" "$plist"
  done
}

if [[ -n "$url" ]]; then
  dmg="${dmg:-/tmp/Ghostty-tip.dmg}"
  print "Downloading Ghostty tip DMG..."
  curl -L -o "$dmg" "$url"
fi

if [[ -n "$dmg" ]]; then
  [[ -r "$dmg" ]] || { print -u2 "DMG not readable: $dmg"; exit 1; }
  if [[ -n "$sha" ]]; then
    local actual
    actual="$(shasum -a 256 "$dmg" | awk '{ print $1 }')"
    [[ "$actual" == "$sha" ]] || {
      print -u2 "SHA-256 mismatch for $dmg"
      print -u2 "expected: $sha"
      print -u2 "actual:   $actual"
      exit 1
    }
  fi

  if [[ -e "$target" ]]; then
    [[ "$replace" == "1" ]] || {
      print -u2 "$target already exists. Set GZMX_E2E_GHOSTTY_TIP_REPLACE=1 to replace it."
      exit 1
    }
    rm -rf "$target"
  fi

  mount_dir="$(mktemp -d /tmp/ghostty-tip-mount-XXXXXX)"
  hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg" >/dev/null
  [[ -d "$mount_dir/Ghostty.app" ]] || { print -u2 "Ghostty.app not found in DMG"; exit 1; }
  ditto "$mount_dir/Ghostty.app" "$target"
fi

[[ -d "$target" ]] || {
  print -u2 "$target does not exist. Provide GZMX_E2E_GHOSTTY_TIP_DMG or GZMX_E2E_GHOSTTY_TIP_URL."
  exit 1
}

plutil -replace CFBundleName -string "$app_name" "$target/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$app_name" "$target/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$target/Contents/Info.plist"
[[ "$install_live" == "1" ]] && configure_tip_bundle_environment
codesign --force --deep --sign - "$target" >/dev/null
codesign --verify --deep --strict "$target" >/dev/null

local actual_name actual_bundle_id
actual_name="$(plutil -extract CFBundleName raw "$target/Contents/Info.plist")"
actual_bundle_id="$(plutil -extract CFBundleIdentifier raw "$target/Contents/Info.plist")"
[[ "$actual_name" == "$app_name" ]] || {
  print -u2 "Ghostty-tip bundle name verification failed: expected $app_name, got $actual_name"
  exit 1
}
[[ "$actual_bundle_id" == "$bundle_id" ]] || {
  print -u2 "Ghostty-tip bundle id verification failed: expected $bundle_id, got $actual_bundle_id"
  exit 1
}

local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ -x "$lsregister" ]] && "$lsregister" -f "$target" >/dev/null 2>&1 || true

print "Ghostty-tip E2E app ready:"
print "  app:       $target"
print "  name:      $actual_name"
print "  bundle id: $actual_bundle_id"
print "  signature: verified"

if [[ "$install_live" == "1" ]]; then
  print ""
  install_live_files
fi
