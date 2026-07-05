#!/usr/bin/env zsh
# Prepare an isolated Ghostty-tip app bundle for E2E.
#
# This never installs Homebrew's ghostty@tip cask because that cask conflicts
# with stable Ghostty and targets /Applications/Ghostty.app. Instead it copies
# a downloaded tip DMG's Ghostty.app to /Applications/Ghostty-tip.app, rewrites
# only the copied bundle identity to Ghostty-tip, ad-hoc signs it, and registers
# it with LaunchServices so AppleScript can address "Ghostty-tip".
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
local mount_dir=""

usage() {
  cat <<'EOF'
Usage: e2e/setup-ghostty-tip.zsh

Environment:
  GZMX_E2E_GHOSTTY_TIP_APP       Target app, default /Applications/Ghostty-tip.app
  GZMX_E2E_GHOSTTY_TIP_DMG       Existing Ghostty tip DMG to copy from
  GZMX_E2E_GHOSTTY_TIP_URL       Download URL for Ghostty tip DMG
  GZMX_E2E_GHOSTTY_TIP_SHA256    Optional SHA-256 for the DMG
  GZMX_E2E_GHOSTTY_TIP_REPLACE=1 Replace existing target app before copying

If the target app already exists and no DMG/URL is provided, the script only
ensures the copied app has the isolated Ghostty-tip identity and signature.
EOF
}

[[ "${1:-}" != "-h" && "${1:-}" != "--help" ]] || { usage; exit 0; }

[[ "$target" == */Ghostty-tip.app ]] || {
  print -u2 "Refusing target that is not named Ghostty-tip.app: $target"
  exit 1
}
[[ "$target" != "/Applications/Ghostty.app" ]] || {
  print -u2 "Refusing to touch stable Ghostty: $target"
  exit 1
}

cleanup() {
  [[ -n "$mount_dir" && -d "$mount_dir" ]] && hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM HUP

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
codesign --force --deep --sign - "$target" >/dev/null

local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ -x "$lsregister" ]] && "$lsregister" -f "$target" >/dev/null 2>&1 || true

print "Ghostty-tip E2E app ready:"
print "  app:       $target"
print "  name:      $(plutil -extract CFBundleName raw "$target/Contents/Info.plist")"
print "  bundle id: $(plutil -extract CFBundleIdentifier raw "$target/Contents/Info.plist")"
