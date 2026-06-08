#!/bin/zsh
set -eu

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

stubbin="$workdir/bin"
mkdir -p "$stubbin"
for cmd in zmx osascript zsh; do
  cat > "$stubbin/$cmd" <<'STUB'
#!/bin/zsh
exit 0
STUB
  chmod +x "$stubbin/$cmd"
done
export PATH="$stubbin:$PATH"

run_install() {
  HOME="$1" GHOSTTY_ZMX_GHOSTTY_CONFIG="$2" GHOSTTY_ZMX_DATA_HOME="$3" "$repo_dir/install.sh" "${@:4}"
}

run_uninstall() {
  HOME="$1" GHOSTTY_ZMX_GHOSTTY_CONFIG="$2" GHOSTTY_ZMX_DATA_HOME="$3" GHOSTTY_ZMX_STATE_HOME="$4" "$repo_dir/uninstall.sh" "${@:5}"
}

home_decline="$workdir/home-decline"
config_decline="$workdir/config-decline/config.ghostty"
data_decline="$workdir/data-decline/ghostty-zmx"
mkdir -p "$home_decline" "${config_decline:h}"
printf 'n\n' | run_install "$home_decline" "$config_decline" "$data_decline" >/dev/null
[[ ! -e "$home_decline/.config/ghostty-zmx/session-manager.zsh" ]] || { print -u2 "declined install changed files"; exit 1; }

home="$workdir/home"
config="$workdir/config/config.ghostty"
data="$workdir/share/ghostty-zmx"
old_data="$home/.local/share/zmx"
state="$workdir/state/ghostty-zmx"
mkdir -p "$home" "${config:h}" "$old_data" "$data" "$state"
cat > "$home/.zshrc" <<'ZSHRC'
# zmx session management
old experimental content
# end zmx session management
ZSHRC
cat > "$config" <<'CFG'
env = ZMX_AUTO_ATTACH=1
confirm-close-surface = false
window-save-state = always
CFG
cat > "$old_data/sessions" <<'SESS'
zmx-abc-def-1234abcd
../bad
zmx-ghi-jkl-abcdef12
SESS
rm -rf "$data"

run_install "$home" "$config" "$data" --yes > "$workdir/install.out"
grep -qxF '[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"' "$home/.zshrc" || { print -u2 "source line missing"; exit 1; }
! grep -q 'env = ZMX_AUTO_ATTACH=1' "$config" || { print -u2 "old env line remained"; exit 1; }
! grep -q 'confirm-close-surface = false' "$config" || { print -u2 "experimental confirm-close remained"; exit 1; }
grep -q 'window-save-state = always' "$config" || { print -u2 "conflict setting not preserved"; exit 1; }
grep -q 'Warning: .*window-save-state' "$workdir/install.out" || { print -u2 "conflict warning missing"; exit 1; }
[[ "$(wc -l < "$data/sessions" | tr -d ' ')" == 1 ]] || { print -u2 "invalid migrated sessions were not filtered"; exit 1; }

run_install "$home" "$config" "$data" --yes > /dev/null
[[ "$(grep -cF 'session-manager.zsh' "$home/.zshrc")" == 1 ]] || { print -u2 "source line not idempotent"; exit 1; }
[[ "$(grep -c '^# BEGIN ghostty-zmx$' "$config")" == 1 ]] || { print -u2 "managed block not idempotent"; exit 1; }

run_uninstall "$home" "$config" "$data" "$state" --yes > "$workdir/uninstall.out"
[[ -d "$home/.config/ghostty-zmx" ]] || { print -u2 "--yes removed install dir"; exit 1; }
[[ -d "$data" ]] || { print -u2 "--yes removed data"; exit 1; }
[[ -d "$state" ]] || { print -u2 "--yes removed state"; exit 1; }
grep -q -- '--remove-data' "$workdir/uninstall.out" || { print -u2 "non-destructive uninstall guidance missing"; exit 1; }

run_uninstall "$home" "$config" "$data" "$state" --yes --remove-install-dir --remove-data --remove-state > /dev/null
[[ ! -d "$home/.config/ghostty-zmx" ]] || { print -u2 "explicit install dir deletion failed"; exit 1; }
[[ ! -d "$data" ]] || { print -u2 "explicit data deletion failed"; exit 1; }
[[ ! -d "$state" ]] || { print -u2 "explicit state deletion failed"; exit 1; }

unsafe_home="$workdir/unsafe-home"
mkdir -p "$unsafe_home"
if run_uninstall "$unsafe_home" "$workdir/unsafe-config" "$unsafe_home" "$workdir/unsafe-state/ghostty-zmx" --yes --remove-data >/dev/null 2>&1; then
  print -u2 "unsafe data deletion was allowed"
  exit 1
fi
