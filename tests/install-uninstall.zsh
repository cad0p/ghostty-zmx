#!/bin/zsh
set -eu

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
stale_restore="/tmp/zmx-restore-ghostty-zmx-test-$$"
stale_restoring="/tmp/zmx-restoring-ghostty-zmx-test-$$"
stale_reaper="/tmp/zmx-reaper-ghostty-zmx-test-$$"
trap 'rm -rf "$workdir" "$stale_restore" "$stale_restoring" "$stale_reaper"' EXIT

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

home_accept="$workdir/home-accept"
config_accept="$workdir/config-accept/config.ghostty"
data_accept="$workdir/data-accept/ghostty-zmx"
mkdir -p "$home_accept" "${config_accept:h}" "$data_accept"
printf 'y\n' | run_install "$home_accept" "$config_accept" "$data_accept" > "$workdir/interactive-install.out"
grep -qxF '[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"' "$home_accept/.zshrc" || { print -u2 "interactive install source line missing"; exit 1; }
grep -q '^# BEGIN ghostty-zmx$' "$config_accept" || { print -u2 "interactive install managed block missing"; exit 1; }
grep -q 'Managed Ghostty block to add:' "$workdir/interactive-install.out" || { print -u2 "interactive install plan missing managed block"; exit 1; }

home_unterminated="$workdir/home-unterminated"
config_unterminated="$workdir/config-unterminated/config.ghostty"
data_unterminated="$workdir/data-unterminated/ghostty-zmx"
mkdir -p "$home_unterminated" "${config_unterminated:h}"
cat > "$home_unterminated/.zshrc" <<'ZSHRC'
# zmx session management
old experimental content
ZSHRC
if run_install "$home_unterminated" "$config_unterminated" "$data_unterminated" --yes > "$workdir/unterminated-install.out" 2>&1; then
  print -u2 "unterminated experimental block was accepted"
  exit 1
fi
grep -q 'unterminated experimental zmx block' "$workdir/unterminated-install.out" || { print -u2 "unterminated block error missing"; exit 1; }
[[ ! -e "$home_unterminated/.config/ghostty-zmx" ]] || { print -u2 "unterminated block install wrote files"; exit 1; }
grep -qxF '# zmx session management' "$home_unterminated/.zshrc" || { print -u2 "unterminated block fixture changed"; exit 1; }

touch "$stale_restore" "$stale_restoring" "$stale_reaper"

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
[[ ! -e "$stale_restore" && ! -e "$stale_restoring" && ! -e "$stale_reaper" ]] || { print -u2 "stale experimental runtime flags remained"; exit 1; }
grep -qxF '[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"' "$home/.zshrc" || { print -u2 "source line missing"; exit 1; }
! grep -q 'env = ZMX_AUTO_ATTACH=1' "$config" || { print -u2 "old env line remained"; exit 1; }
! grep -q 'confirm-close-surface = false' "$config" || { print -u2 "experimental confirm-close remained"; exit 1; }
grep -q 'window-save-state = always' "$config" || { print -u2 "conflict setting not preserved"; exit 1; }
grep -q 'Warning: .*window-save-state' "$workdir/install.out" || { print -u2 "conflict warning missing"; exit 1; }
[[ "$(wc -l < "$data/sessions" | tr -d ' ')" == 1 ]] || { print -u2 "invalid migrated sessions were not filtered"; exit 1; }

run_install "$home" "$config" "$data" --yes > /dev/null
[[ "$(grep -cF 'session-manager.zsh' "$home/.zshrc")" == 1 ]] || { print -u2 "source line not idempotent"; exit 1; }
[[ "$(grep -c '^# BEGIN ghostty-zmx$' "$config")" == 1 ]] || { print -u2 "managed block not idempotent"; exit 1; }

home_existing="$workdir/home-existing"
config_existing="$workdir/config-existing/config.ghostty"
data_existing="$workdir/share-existing/ghostty-zmx"
old_data_existing="$home_existing/.local/share/zmx"
mkdir -p "$home_existing" "${config_existing:h}" "$old_data_existing" "$data_existing"
print -r -- zmx-existing-11112222-33334444-aaaaaaaa > "$data_existing/sessions"
print -r -- zmx-old-55556666-77778888-bbbbbbbb > "$old_data_existing/sessions"
run_install "$home_existing" "$config_existing" "$data_existing" --yes > /dev/null
grep -qxF 'zmx-existing-11112222-33334444-aaaaaaaa' "$data_existing/sessions" || { print -u2 "existing sessions file was overwritten"; exit 1; }
[[ "$(wc -l < "$data_existing/sessions" | tr -d ' ')" == 1 ]] || { print -u2 "existing sessions file gained migrated entries"; exit 1; }

run_uninstall "$home" "$config" "$data" "$state" --yes > "$workdir/uninstall.out"
[[ -d "$home/.config/ghostty-zmx" ]] || { print -u2 "--yes removed install dir"; exit 1; }
[[ -d "$data" ]] || { print -u2 "--yes removed data"; exit 1; }
[[ -d "$state" ]] || { print -u2 "--yes removed state"; exit 1; }
grep -q -- '--remove-data' "$workdir/uninstall.out" || { print -u2 "non-destructive uninstall guidance missing"; exit 1; }

home_prompt="$workdir/home-prompt"
config_prompt="$workdir/config-prompt/config.ghostty"
data_prompt="$workdir/share-prompt/ghostty-zmx"
state_prompt="$workdir/state-prompt/ghostty-zmx"
mkdir -p "$home_prompt" "${config_prompt:h}" "$data_prompt" "$state_prompt"
cat > "$home_prompt/.zshrc" <<'ZSHRC'
[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"
ZSHRC
cat > "$config_prompt" <<'CFG'
# BEGIN ghostty-zmx
env = GHOSTTY_ZMX_AUTO_ATTACH=1
# END ghostty-zmx
CFG
printf 'n\nn\n' | run_uninstall "$home_prompt" "$config_prompt" "$data_prompt" "$state_prompt" > "$workdir/uninstall-decline.out"
grep -qxF '[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"' "$home_prompt/.zshrc" || { print -u2 "interactive decline removed source line"; exit 1; }
grep -q '^# BEGIN ghostty-zmx$' "$config_prompt" || { print -u2 "interactive decline removed Ghostty block"; exit 1; }
printf 'y\ny\n' | run_uninstall "$home_prompt" "$config_prompt" "$data_prompt" "$state_prompt" > "$workdir/uninstall-accept.out"
! grep -q 'session-manager.zsh' "$home_prompt/.zshrc" || { print -u2 "interactive accept left source line"; exit 1; }
! grep -q '^# BEGIN ghostty-zmx$' "$config_prompt" || { print -u2 "interactive accept left Ghostty block"; exit 1; }
[[ -d "$data_prompt" && -d "$state_prompt" ]] || { print -u2 "interactive accept removed data/state without flags"; exit 1; }

runtime_root="$workdir/runtime-root"
runtime_dir="$runtime_root/ghostty-zmx-${UID:-$(id -u)}"
mkdir -p "$runtime_dir"
touch "$runtime_dir/reaper-test.zsh"
XDG_RUNTIME_DIR="$runtime_root" run_uninstall "$home_prompt" "$config_prompt" "$data_prompt" "$state_prompt" --yes > "$workdir/runtime-uninstall.out"
[[ ! -d "$runtime_dir" ]] || { print -u2 "current runtime directory was not removed"; exit 1; }

unsafe_runtime_root="$workdir/unsafe-runtime-root"
mkdir -p "$unsafe_runtime_root"
ln -s "$home_prompt" "$unsafe_runtime_root/ghostty-zmx-${UID:-$(id -u)}"
if XDG_RUNTIME_DIR="$unsafe_runtime_root" run_uninstall "$home_prompt" "$config_prompt" "$data_prompt" "$state_prompt" --yes > /dev/null 2>&1; then
  print -u2 "unsafe runtime symlink deletion was allowed"
  exit 1
fi
[[ -d "$home_prompt" ]] || { print -u2 "unsafe runtime symlink target was deleted"; exit 1; }

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
