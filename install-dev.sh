#!/bin/zsh
# ghostty-zmx install-dev — one-command dev onboarding against Ghostty-tip.
#
# Ensures a signed Ghostty-tip app exists at /Applications/Ghostty-tip.app
# (downloading the latest tip from the official Ghostty appcast with --update-tip
# or when the app is missing), installs this checkout's files into an isolated
# ~/.config/ghostty-zmx-tip, writes an isolated Ghostty-tip config + ZDOTDIR +
# launcher, and stamps a single LSEnvironment entry (XDG_CONFIG_HOME) into the
# tip bundle so Spotlight/double-click launches discover the isolated config.
#
# Never touches stable Ghostty, stable Ghostty config, ~/.zshrc, or ~/.zprofile.
# GHOSTTY_ZMX_DEBUG=1 is always baked into the tip config (dev install).
#
# Usage:
#   ghostty-zmx install-dev [--yes] [--update-tip]
#
# Shared helpers (backup_file, confirm, require_command, refresh_vendored_terminfo)
# are sourced from install-lib.sh.
set -u
setopt NULL_GLOB

YES=0
UPDATE_TIP=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --update-tip) UPDATE_TIP=1 ;;
    --help|-h)
      print "Usage: ghostty-zmx install-dev [--yes] [--update-tip]"
      print ""
      print "Ensures a signed Ghostty-tip app and an isolated ghostty-zmx dev install."
      print ""
      print "Options:"
      print "  --yes, -y        Non-interactive (assume yes to prompts)."
      print "  --update-tip     Download the latest Ghostty tip from the official appcast"
      print "                   and replace /Applications/Ghostty-tip.app. Also used when"
      print "                   the app is missing."
      exit 0 ;;
    *) print -u2 "Unknown argument: $arg"; exit 2 ;;
  esac
done

[[ -n "${HOME:-}" ]] || { print -u2 "HOME is not set"; exit 1; }

emulate -L zsh
setopt no_sh_word_split

repo_dir="${0:A:h}"
source "${repo_dir}/install-lib.sh"

# --- paths (all isolated from stable) ---
target="${GZMX_E2E_GHOSTTY_TIP_APP:-/Applications/Ghostty-tip.app}"
app_name="${GZMX_E2E_GHOSTTY_TIP_NAME:-Ghostty-tip}"
bundle_id="${GZMX_E2E_GHOSTTY_TIP_BUNDLE_ID:-com.mitchellh.ghostty.tip}"
install_dir="${GZMX_E2E_GHOSTTY_TIP_INSTALL_DIR:-$HOME/.config/ghostty-zmx-tip}"
tip_config_root="${GZMX_E2E_GHOSTTY_TIP_CONFIG_DIR:-$HOME/.config/ghostty-tip}"
tip_config="$tip_config_root/config.ghostty"
tip_zdotdir="${GZMX_E2E_GHOSTTY_TIP_ZDOTDIR:-$HOME/.config/ghostty-tip-zdotdir}"
tip_data_home="${GZMX_E2E_GHOSTTY_TIP_DATA_HOME:-$HOME/.local/share/ghostty-zmx-tip}"
tip_state_home="${GZMX_E2E_GHOSTTY_TIP_STATE_HOME:-$HOME/.local/state/ghostty-zmx-tip}"
tip_path="${GZMX_E2E_GHOSTTY_TIP_PATH:-$HOME/.local/bin:$HOME/.toolbox/bin:/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin}"
tip_launcher="$tip_config_root/open-ghostty-tip.zsh"

# Shared env list: the single source of truth for both the config `env =` block
# (launcher path) and the bundle LSEnvironment (Spotlight path).
#
# Why LSEnvironment (full duplication) instead of launchctl setenv XDG_CONFIG_HOME?
# The Ghostty maintainer's suggestion (ghostty-org/ghostty#12408) is to set
# XDG_CONFIG_HOME via `launchctl setenv` so Spotlight launches (which inherit
# from launchd, not the shell) discover a custom config. But launchctl setenv is
# GLOBAL: it would redirect every GUI app's XDG_CONFIG_HOME, breaking stable
# Ghostty and anything else that reads XDG_CONFIG_HOME. For an ISOLATED dev
# install we need a per-app mechanism. LSEnvironment is per-app (only the tip
# bundle), so we duplicate the full env there. The config `env =` block serves
# the launcher path (which passes --config-file explicitly). Generating both
# from this list prevents drift.
#
# Note: on machines where XDG_CONFIG_HOME is already set globally in launchctl
# (e.g. by a shell profile), LSEnvironment cannot override it for that var —
# but ZDOTDIR/GHOSTTY_ZMX_* are not globally set, so LSEnvironment sets them
# fine. The config `env =` block re-asserts all vars for the launcher path.
typeset -a tip_env
tip_env=(
  "ZDOTDIR=$tip_zdotdir"
  "GHOSTTY_ZMX_APP_NAME=$app_name"
  "GHOSTTY_ZMX_AUTO_ATTACH=1"
  "GHOSTTY_ZMX_DEBUG=1"
  "GHOSTTY_ZMX_INSTALL_DIR=$install_dir"
  "GHOSTTY_ZMX_DATA_HOME=$tip_data_home"
  "GHOSTTY_ZMX_STATE_HOME=$tip_state_home"
  "PATH=$tip_path"
)

# Official Ghostty tip appcast. We manage this URL (never accept a user-supplied
# download URL) so a compromised/mistyped endpoint can't deliver a tampered binary.
# TLS protects the download; the appcast's enclosure length is verified post-download.
appcast_url="https://tip.files.ghostty.org/appcast.xml"

# --- safety refusals (never touch stable) ---
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
[[ "$tip_config_root" != "$HOME/.config/ghostty" && "$tip_config_root" != "$HOME/.config/ghostty/" ]] || {
  print -u2 "Refusing Ghostty-tip config path that is the stable Ghostty XDG config: $tip_config_root"
  exit 1
}
[[ "$tip_config_root" != "$HOME/Library/Application Support/com.mitchellh.ghostty/"* ]] || {
  print -u2 "Refusing Ghostty-tip config path under stable Ghostty app-support config: $tip_config_root"
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

require_command osascript
require_command zsh
require_command curl
require_command hdiutil
require_command codesign
command -v plutil >/dev/null 2>&1 || { print -u2 "Missing required command: plutil"; exit 1; }
command -v ditto >/dev/null 2>&1 || { print -u2 "Missing required command: ditto"; exit 1; }
# Note: zmx is NOT required here. install-dev never invokes zmx itself — it only
# installs files. The original setup-ghostty-tip.zsh --install-live did not
# require zmx either. Requiring zmx would block fresh onboarding (a new
# contributor cloning the repo has no zmx on PATH until they run the stable
# `ghostty-zmx install`). The manager (session-manager.zsh) handles the
# missing-zmx case gracefully at runtime.

# --- Ghostty-tip app bundle: ensure, or update from appcast ---
# Fetch the newest enclosure from the official Ghostty tip appcast.
# Prints "url<TAB>length" on stdout for the caller to parse (avoids losing
# a global to command-substitution subshell scoping). Uses sed (portable
# across BSD/Linux) rather than gawk's 3-arg match().
#
# The appcast lists items OLDEST-FIRST (build numbers ascending), so the
# newest is the LAST <item>. We extract the last enclosure, not the first.
fetch_latest_tip_enclosure() {
  local tmp url length
  tmp="$(mktemp /tmp/ghostty-appcast.XXXXXX)"
  curl -fsS "$appcast_url" -o "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1 }
  # Extract every enclosure url+length, take the LAST one (newest build).
  # Each <enclosure> is on its own physical line, so sed -n prints one line
  # per match; tail -1 picks the last (newest).
  url="$(sed -n 's/.*<enclosure url="\([^"]*\)".*/\1/p' "$tmp" | tail -1)"
  length="$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' "$tmp" | tail -1)"
  rm -f "$tmp"
  [[ -n "$url" && -n "$length" ]] || return 1
  print -r -- "${url}"$'\t'"${length}"
}

download_and_install_tip_app() {
  local dmg="${GZMX_E2E_GHOSTTY_TIP_DMG:-/tmp/Ghostty-tip.dmg}" enclosure url expected_length
  print "Fetching latest Ghostty tip from the official appcast..."
  enclosure="$(fetch_latest_tip_enclosure)" || { print -u2 "Failed to parse appcast at $appcast_url"; exit 1; }
  url="${enclosure%%$'\t'*}"
  expected_length="${enclosure##*$'\t'}"
  print "  latest tip: $url"
  curl -fL -o "$dmg" "$url" 2>/dev/null || { print -u2 "Failed to download $url"; exit 1 }
  # Verify length (TLS protects transport; length catches truncation/corruption).
  local actual
  actual="$(stat -f %z "$dmg" 2>/dev/null || stat -c %s "$dmg" 2>/dev/null)"
  [[ "$actual" == "$expected_length" ]] || {
    print -u2 "Length mismatch: expected $expected_length, got $actual"
    exit 1
  }
  install_tip_app_from_dmg "$dmg"
  rm -f "$dmg"
}

install_tip_app_from_dmg() {
  local dmg="$1"
  [[ -r "$dmg" ]] || { print -u2 "DMG not readable: $dmg"; exit 1 }
  if [[ -e "$target" ]]; then
    [[ "$UPDATE_TIP" == "1" || "$app_needs_install" == "1" ]] || {
      print -u2 "$target already exists. Use --update-tip to replace it."
      exit 1
    }
    rm -rf "$target"
  fi
  local mount_dir
  mount_dir="$(mktemp -d /tmp/ghostty-tip-mount-XXXXXX)"
  hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg" >/dev/null
  [[ -d "$mount_dir/Ghostty.app" ]] || { print -u2 "Ghostty.app not found in DMG"; exit 1 }
  ditto "$mount_dir/Ghostty.app" "$target"
  hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
  rmdir "$mount_dir" 2>/dev/null || true
  normalize_tip_bundle
}

normalize_tip_bundle() {
  plutil -replace CFBundleName -string "$app_name" "$target/Contents/Info.plist"
  plutil -replace CFBundleDisplayName -string "$app_name" "$target/Contents/Info.plist"
  plutil -replace CFBundleIdentifier -string "$bundle_id" "$target/Contents/Info.plist"
  # Rename the executable to match the app name so the bundle is self-consistent.
  local _orig_exec
  _orig_exec="$(plutil -extract CFBundleExecutable raw "$target/Contents/Info.plist" 2>/dev/null || print ghostty)"
  if [[ "$_orig_exec" != "$app_name" ]]; then
    mv "$target/Contents/MacOS/$_orig_exec" "$target/Contents/MacOS/$app_name" 2>/dev/null || true
    plutil -replace CFBundleExecutable -string "$app_name" "$target/Contents/Info.plist"
  fi
  stamp_lsenvironment
  codesign --force --deep --sign - "$target" >/dev/null
  codesign --verify --deep --strict "$target" >/dev/null
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  [[ -x "$lsregister" ]] && "$lsregister" -f "$target" >/dev/null 2>&1 || true
  local actual_name actual_bundle_id
  actual_name="$(plutil -extract CFBundleName raw "$target/Contents/Info.plist")"
  actual_bundle_id="$(plutil -extract CFBundleIdentifier raw "$target/Contents/Info.plist")"
  [[ "$actual_name" == "$app_name" ]] || { print -u2 "Bundle name verification failed: expected $app_name, got $actual_name"; exit 1 }
  [[ "$actual_bundle_id" == "$bundle_id" ]] || { print -u2 "Bundle id verification failed: expected $bundle_id, got $actual_bundle_id"; exit 1 }
  print "Ghostty-tip app ready: $target (name=$actual_name, bundle_id=$actual_bundle_id)"
}

# Stamp LSEnvironment with every tip env var. Ghostty ignores custom
# XDG_CONFIG_HOME on macOS (ghostty-org/ghostty#12408), so we cannot redirect
# config discovery to isolate the tip from stable via XDG_CONFIG_HOME alone.
# Instead, every env var the tip needs is set directly in LSEnvironment so
# Spotlight/double-click launches get the isolated env even though Ghostty
# loads the stable app-support config (whose managed block has the identical
# AUTO_ATTACH=1, and user theme/keybinds which the tip inherits). The launcher
# path (open-ghostty-tip.zsh) uses --config-file and the config's env= block
# directly; LSEnvironment is the fallback for Spotlight launches.
stamp_lsenvironment() {
  local plist="$target/Contents/Info.plist"
  local buddy="/usr/libexec/PlistBuddy"
  [[ -x "$buddy" ]] || { print -u2 "PlistBuddy not found"; exit 1; }
  "$buddy" -c "Print :LSEnvironment" "$plist" >/dev/null 2>&1 ||
    "$buddy" -c "Add :LSEnvironment dict" "$plist"
  "$buddy" -c "Set :LSEnvironment:GHOSTTY_MAC_LAUNCH_SOURCE app" "$plist" >/dev/null 2>&1 ||
    "$buddy" -c "Add :LSEnvironment:GHOSTTY_MAC_LAUNCH_SOURCE string app" "$plist"
  local pair key value
  for pair in "${tip_env[@]}"; do
    key="${pair%%=*}"
    value="${pair#*=}"
    "$buddy" -c "Set :LSEnvironment:$key $value" "$plist" >/dev/null 2>&1 ||
      "$buddy" -c "Add :LSEnvironment:$key string $value" "$plist"
  done
  # Remove XDG_CONFIG_HOME if a prior install-dev attempt left it (the
  # XDG_CONFIG_HOME minimization was abandoned — Ghostty ignores it).
  "$buddy" -c "Delete :LSEnvironment:XDG_CONFIG_HOME" "$plist" >/dev/null 2>&1 || true
}

# Decide whether to download. app_needs_install=1 when the app is absent.
app_needs_install=0
if [[ ! -d "$target" ]]; then
  app_needs_install=1
  UPDATE_TIP=1  # missing app → must download
elif [[ "$UPDATE_TIP" == "1" ]]; then
  print "Ghostty-tip already installed at $target; --update-tip will replace it."
  confirm "Replace $target with the latest tip from the appcast?" || { print "Declined; keeping existing app."; UPDATE_TIP=0; }
fi
[[ "$UPDATE_TIP" == "1" ]] && download_and_install_tip_app

[[ -d "$target" ]] || { print -u2 "$target does not exist and could not be installed."; exit 1 }

# If the app already existed (not re-downloaded this run), the bundle may
# still carry a stale LSEnvironment from a prior setup-ghostty-tip.zsh run
# (the old 9-entry duplication). Re-stamp to the minimized single entry and
# re-sign, so we converge idempotently. Re-signing is required because any
# Info.plist edit invalidates the code signature.
if [[ "$app_needs_install" != "1" ]]; then
  stamp_lsenvironment
  codesign --force --deep --sign - "$target" >/dev/null
  codesign --verify --deep --strict "$target" >/dev/null || { print -u2 "Code signature verification failed for $target"; exit 1 }
fi
# Re-register with LaunchServices so the new LSEnvironment takes effect for
# Spotlight/Finder launches (cached registrations otherwise persist).
_lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ -x "$_lsregister" ]] && "$_lsregister" -f "$target" >/dev/null 2>&1 || true

# Remove a stale config from a prior XDG-form install-dev attempt
# (which wrote ~/.config/ghostty-tip/ghostty/config.ghostty). The non-XDG
# path ~/.config/ghostty-tip/config.ghostty is what the launcher uses.
[[ -d "$tip_config_root/ghostty" ]] && rm -rf "$tip_config_root/ghostty" 2>/dev/null || true

# --- live install: copy checkout files ---
install_live_files() {
  local -a required=(
    session-manager.zsh
    session-manager-lib.zsh
    session-manager-early.zsh
    session-manager-v0.1.zsh
    cli/ghostty-zmx
    cli/install-server
    cli/debug
    cli/remote-layout
    uninstall.sh
    install-server.sh
    install-lib.sh
    package.json
    terminfo/xterm-ghostty.terminfo
  )
  local f
  for f in "${required[@]}"; do
    [[ -r "$repo_dir/$f" ]] || { print -u2 "Missing checkout file: $repo_dir/$f"; exit 1; }
  done

  mkdir -p "$install_dir/cli" "$install_dir/terminfo" "$tip_config_root" "$tip_zdotdir" "$tip_data_home" "$tip_state_home"
  install -m 0644 "$repo_dir/session-manager.zsh" "$install_dir/session-manager.zsh"
  install -m 0644 "$repo_dir/session-manager-lib.zsh" "$install_dir/session-manager-lib.zsh"
  install -m 0644 "$repo_dir/session-manager-early.zsh" "$install_dir/session-manager-early.zsh"
  install -m 0644 "$repo_dir/session-manager-v0.1.zsh" "$install_dir/session-manager-v0.1.zsh"
  install -m 0755 "$repo_dir/cli/ghostty-zmx" "$install_dir/cli/ghostty-zmx"
  install -m 0755 "$repo_dir/cli/install-server" "$install_dir/cli/install-server"
  install -m 0755 "$repo_dir/cli/debug" "$install_dir/cli/debug"
  install -m 0755 "$repo_dir/cli/remote-layout" "$install_dir/cli/remote-layout"
  install -m 0755 "$repo_dir/uninstall.sh" "$install_dir/uninstall.sh"
  install -m 0755 "$repo_dir/install-server.sh" "$install_dir/install-server.sh"
  install -m 0644 "$repo_dir/install-lib.sh" "$install_dir/install-lib.sh"
  install -m 0644 "$repo_dir/package.json" "$install_dir/package.json"

  refresh_vendored_terminfo "$install_dir/terminfo/xterm-ghostty.terminfo" "$repo_dir/terminfo/xterm-ghostty.terminfo"

  # Isolated Ghostty-tip config. The launcher passes --config-file= to load it
  # directly; LSEnvironment (stamped on the bundle) carries the same env vars
  # for Spotlight launches that don't pass --config-file. Both are generated
  # from the shared tip_env list so they cannot drift.
  # GHOSTTY_ZMX_DEBUG=1 is always baked in (dev install).
  {
    print "# ghostty-tip isolated ghostty-zmx config (dev install)"
    local pair
    for pair in "${tip_env[@]}"; do
      print "env = $pair"
    done
    print "window-save-state = never"
    print "confirm-close-surface = true"
  } > "$tip_config"

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

  print ""
  print "Ghostty-tip dev install ready:"
  print "  install dir: $install_dir"
  print "  config:      $tip_config"
  print "  zdotdir:     $tip_zdotdir"
  print "  data home:   $tip_data_home"
  print "  state home:  $tip_state_home"
  print "  launcher:    $tip_launcher"
  print ""
  print "Launch with:"
  print "  $tip_launcher"
  print "or via Spotlight (LSEnvironment carries the isolated env)."
}

install_live_files
