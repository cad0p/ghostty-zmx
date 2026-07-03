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

if HOME='' "$repo_dir/install.sh" --yes > "$workdir/install-no-home.out" 2>&1; then
  print -u2 "install succeeded with empty HOME"
  exit 1
fi
grep -q 'HOME is not set' "$workdir/install-no-home.out" || { print -u2 "install missing HOME error not clear"; exit 1; }
if HOME='' "$repo_dir/uninstall.sh" --yes > "$workdir/uninstall-no-home.out" 2>&1; then
  print -u2 "uninstall succeeded with empty HOME"
  exit 1
fi
grep -q 'HOME is not set' "$workdir/uninstall-no-home.out" || { print -u2 "uninstall missing HOME error not clear"; exit 1; }

run_install() {
  HOME="$1" GHOSTTY_ZMX_INTERNAL_TEST_GHOSTTY_CONFIG="$2" GHOSTTY_ZMX_DATA_HOME="$3" "$repo_dir/install.sh" "${@:4}"
}

run_uninstall() {
  HOME="$1" GHOSTTY_ZMX_INTERNAL_TEST_GHOSTTY_CONFIG="$2" GHOSTTY_ZMX_DATA_HOME="$3" GHOSTTY_ZMX_STATE_HOME="$4" "$repo_dir/uninstall.sh" "${@:5}"
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
grep -qxF '[[ -r "$HOME/.config/ghostty-zmx/session-manager-early.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager-early.zsh"' "$home_accept/.zprofile" || { print -u2 "interactive install early source line missing"; exit 1; }
grep -q '^# BEGIN ghostty-zmx$' "$config_accept" || { print -u2 "interactive install managed block missing"; exit 1; }
grep -q 'Managed Ghostty block to add:' "$workdir/interactive-install.out" || { print -u2 "interactive install plan missing managed block"; exit 1; }

home_unterminated="$workdir/home-unterminated"
config_unterminated="$workdir/config-unterminated/config.ghostty"
data_unterminated="$workdir/data-unterminated/ghostty-zmx"
mkdir -p "$home_unterminated" "${config_unterminated:h}" "$data_unterminated"
run_install "$home_unterminated" "$config_unterminated" "$data_unterminated" --yes > "$workdir/unterminated-install.out"
grep -qxF '[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"' "$home_unterminated/.zshrc" || { print -u2 "plain install source line missing"; exit 1; }
grep -qxF '[[ -r "$HOME/.config/ghostty-zmx/session-manager-early.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager-early.zsh"' "$home_unterminated/.zprofile" || { print -u2 "plain install early source line missing"; exit 1; }

home_symlink_install="$workdir/home-symlink-install"
install_target="$workdir/install-target/ghostty-zmx"
config_symlink_install="$workdir/config-symlink-install/config.ghostty"
data_symlink_install="$workdir/share-symlink-install/ghostty-zmx"
mkdir -p "$home_symlink_install/.config" "$install_target" "${config_symlink_install:h}" "$data_symlink_install"
ln -s "$install_target" "$home_symlink_install/.config/ghostty-zmx"
if run_install "$home_symlink_install" "$config_symlink_install" "$data_symlink_install" --yes > "$workdir/symlink-install.out" 2>&1; then
  print -u2 "symlinked install directory was accepted"
  exit 1
fi
grep -q 'Refusing to install into symlinked install directory' "$workdir/symlink-install.out" || { print -u2 "symlinked install directory refusal missing"; exit 1; }
[[ ! -e "$install_target/session-manager.zsh" ]] || { print -u2 "symlinked install target was written"; exit 1; }

home_file_install="$workdir/home-file-install"
config_file_install="$workdir/config-file-install/config.ghostty"
data_file_install="$workdir/share-file-install/ghostty-zmx"
mkdir -p "$home_file_install/.config" "${config_file_install:h}" "$data_file_install"
touch "$home_file_install/.config/ghostty-zmx"
if run_install "$home_file_install" "$config_file_install" "$data_file_install" --yes > "$workdir/file-install.out" 2>&1; then
  print -u2 "regular-file install path was accepted"
  exit 1
fi
grep -q 'Refusing to install into non-directory install path' "$workdir/file-install.out" || { print -u2 "regular-file install path refusal missing"; exit 1; }
[[ ! -e "$home_file_install/.zshrc" && ! -e "$home_file_install/.zprofile" ]] || { print -u2 "regular-file install path modified shell startup files"; exit 1; }

home="$workdir/home"
config="$workdir/config/config.ghostty"
data="$workdir/share/ghostty-zmx"
state="$workdir/state/ghostty-zmx"
mkdir -p "$home" "${config:h}" "$data" "$state"
cat > "$config" <<'CFG'
env = GHOSTTY_ZMX_AUTO_ATTACH=1
confirm-close-surface = false
window-save-state = always
quit-after-last-window-closed = true
CFG

run_install "$home" "$config" "$data" --yes > "$workdir/install.out"
grep -qxF '[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"' "$home/.zshrc" || { print -u2 "source line missing"; exit 1; }
grep -qxF '[[ -r "$HOME/.config/ghostty-zmx/session-manager-early.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager-early.zsh"' "$home/.zprofile" || { print -u2 "early source line missing"; exit 1; }
[[ -f "$home/.config/ghostty-zmx/session-manager-lib.zsh" ]] || { print -u2 "shared lib missing"; exit 1; }
[[ -f "$home/.config/ghostty-zmx/session-manager-early.zsh" ]] || { print -u2 "early manager missing"; exit 1; }
zsh -n "$home/.config/ghostty-zmx/session-manager-lib.zsh" || { print -u2 "shared lib fails syntax check"; exit 1; }
zsh -n "$home/.config/ghostty-zmx/session-manager-early.zsh" || { print -u2 "early manager fails syntax check"; exit 1; }
# v0.2: wrapper, server installer, and vendored terminfo must be installed.
[[ -x "$home/.config/ghostty-zmx/ghostty-zmx" ]] || { print -u2 "wrapper missing or not executable"; exit 1; }
[[ -x "$home/.config/ghostty-zmx/install-server.sh" ]] || { print -u2 "server installer missing or not executable"; exit 1; }
# v0.2: frozen v0.1 fallback manager must be installed (early-sourced on 1.3.x).
[[ -f "$home/.config/ghostty-zmx/session-manager-v0.1.zsh" ]] || { print -u2 "v0.1 fallback manager missing"; exit 1; }
zsh -n "$home/.config/ghostty-zmx/session-manager-v0.1.zsh" || { print -u2 "v0.1 fallback manager fails syntax check"; exit 1; }
[[ -f "$home/.config/ghostty-zmx/terminfo/xterm-ghostty.terminfo" ]] || { print -u2 "vendored terminfo missing"; exit 1; }
grep -q '^xterm-ghostty|ghostty|Ghostty,' "$home/.config/ghostty-zmx/terminfo/xterm-ghostty.terminfo" || { print -u2 "vendored terminfo malformed"; exit 1; }
grep -qxF 'env = GHOSTTY_ZMX_AUTO_ATTACH=1' "$config" || { print -u2 "user auto-attach env was removed"; exit 1; }
grep -qxF 'confirm-close-surface = false' "$config" || { print -u2 "user confirm-close-surface was removed"; exit 1; }
grep -q 'window-save-state = always' "$config" || { print -u2 "conflict setting not preserved"; exit 1; }
grep -q 'quit-after-last-window-closed = true' "$config" || { print -u2 "quit-after-last-window-closed fixture was removed"; exit 1; }
grep -q 'auto-attach env setting' "$workdir/install.out" || { print -u2 "auto-attach env conflict warning missing"; exit 1; }
grep -q 'Warning: .*window-save-state' "$workdir/install.out" || { print -u2 "conflict warning missing"; exit 1; }
grep -q 'Warning: .*confirm-close-surface' "$workdir/install.out" || { print -u2 "confirm-close-surface warning missing"; exit 1; }
grep -q 'quit-after-last-window-closed = true is unsupported' "$workdir/install.out" || { print -u2 "quit-after-last-window-closed warning missing"; exit 1; }

server_home="$workdir/server-home"
server_stubbin="$workdir/server-bin"
mkdir -p "$server_home" "$server_stubbin"
cat > "$server_stubbin/infocmp" <<'STUB'
#!/bin/zsh
exit 0
STUB
chmod +x "$server_stubbin/infocmp"
HOME="$server_home" PATH="$server_stubbin:$PATH" "$repo_dir/install-server.sh" --yes > "$workdir/server-install.out"
[[ -f "$server_home/.config/ghostty-zmx/session-manager.zsh" ]] || { print -u2 "server install manager missing"; exit 1; }
[[ -f "$server_home/.config/ghostty-zmx/session-manager-lib.zsh" ]] || { print -u2 "server install shared lib missing"; exit 1; }
zsh -n "$server_home/.config/ghostty-zmx/session-manager.zsh" || { print -u2 "server manager fails syntax check"; exit 1; }
zsh -n "$server_home/.config/ghostty-zmx/session-manager-lib.zsh" || { print -u2 "server shared lib fails syntax check"; exit 1; }
grep -qxF '[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"' "$server_home/.zshrc" || { print -u2 "server install source line missing"; exit 1; }
grep -q 'session-manager-lib.zsh' "$workdir/server-install.out" || { print -u2 "server install did not report shared lib"; exit 1; }
# Regression (round 15): managed remote-env block must be safe under `set -u`
# when TERM_PROGRAM is unset (common on ssh/tsh sessions).
env -u TERM_PROGRAM HOME="$server_home" SSH_CONNECTION=1 zsh -fc 'set -u; source "$HOME/.zshrc"; [[ "${TERM_PROGRAM:-}" == ghostty && "${COLORTERM:-}" == truecolor ]]' || { print -u2 "server remote-env block is not nounset-safe"; exit 1; }

# Regression (round 14): install-server.sh must refuse a regular-file install
# path before mutating shell startup files, mirroring the round-3 install.sh
# fix. A regular file at ~/.config/ghostty-zmx would cause `mkdir -p .../terminfo`
# to fail silently and later `install -m` calls to exit — after ~/.zshrc had
# already been extended with the source line + remote-env block, leaving a
# guarded-but-dangling reference forever.
server_home_file="$workdir/server-home-file"
server_stubbin_file="$workdir/server-bin-file"
mkdir -p "$server_home_file/.config" "$server_stubbin_file"
touch "$server_home_file/.config/ghostty-zmx"
cat > "$server_stubbin_file/infocmp" <<'STUB'
#!/bin/zsh
exit 0
STUB
chmod +x "$server_stubbin_file/infocmp"
if HOME="$server_home_file" PATH="$server_stubbin_file:$PATH" "$repo_dir/install-server.sh" --yes > "$workdir/server-file-install.out" 2>&1; then
  print -u2 "server installer accepted regular-file install path"
  exit 1
fi
grep -q 'Refusing to install into non-directory install path' "$workdir/server-file-install.out" || { print -u2 "server installer missing non-directory refusal"; exit 1; }
[[ ! -e "$server_home_file/.zshrc" ]] || { print -u2 "server installer wrote .zshrc despite non-directory install path"; exit 1; }

home_user_conflict="$workdir/home-user-conflict"
config_user_conflict="$workdir/config-user-conflict/config.ghostty"
data_user_conflict="$workdir/share-user-conflict/ghostty-zmx"
mkdir -p "$home_user_conflict" "${config_user_conflict:h}" "$data_user_conflict"
cat > "$config_user_conflict" <<'CFG'
window-save-state = always
confirm-close-surface = false
quit-after-last-window-closed = true
CFG
run_install "$home_user_conflict" "$config_user_conflict" "$data_user_conflict" --yes > "$workdir/user-conflict-install.out"
grep -qxF 'confirm-close-surface = false' "$config_user_conflict" || { print -u2 "user-controlled confirm-close-surface was removed"; exit 1; }
grep -qxF 'quit-after-last-window-closed = true' "$config_user_conflict" || { print -u2 "quit-after-last-window-closed fixture was removed"; exit 1; }
grep -q 'Warning: .*confirm-close-surface' "$workdir/user-conflict-install.out" || { print -u2 "user confirm-close-surface warning missing"; exit 1; }
grep -q 'quit-after-last-window-closed = true is unsupported' "$workdir/user-conflict-install.out" || { print -u2 "quit-after-last-window-closed warning missing"; exit 1; }

run_install "$home" "$config" "$data" --yes > /dev/null
[[ "$(grep -cF 'session-manager.zsh' "$home/.zshrc")" == 1 ]] || { print -u2 "source line not idempotent"; exit 1; }
[[ "$(grep -cF 'session-manager-early.zsh' "$home/.zprofile")" == 1 ]] || { print -u2 "early source line not idempotent"; exit 1; }
[[ "$(grep -c '^# BEGIN ghostty-zmx$' "$config")" == 1 ]] || { print -u2 "managed block not idempotent"; exit 1; }

home_blank_cycle="$workdir/home-blank-cycle"
config_blank_cycle="$workdir/config-blank-cycle/config.ghostty"
data_blank_cycle="$workdir/share-blank-cycle/ghostty-zmx"
state_blank_cycle="$workdir/state-blank-cycle/ghostty-zmx"
mkdir -p "$home_blank_cycle" "${config_blank_cycle:h}" "$data_blank_cycle" "$state_blank_cycle"
print -r -- 'export USER_PROFILE=1' > "$home_blank_cycle/.zprofile"
run_install "$home_blank_cycle" "$config_blank_cycle" "$data_blank_cycle" --yes > /dev/null
run_uninstall "$home_blank_cycle" "$config_blank_cycle" "$data_blank_cycle" "$state_blank_cycle" --yes > /dev/null
run_install "$home_blank_cycle" "$config_blank_cycle" "$data_blank_cycle" --yes > /dev/null
run_uninstall "$home_blank_cycle" "$config_blank_cycle" "$data_blank_cycle" "$state_blank_cycle" --yes > /dev/null
[[ "$(grep -c '^$' "$home_blank_cycle/.zprofile" 2>/dev/null || echo 0)" -le 1 ]] || { print -u2 "install/uninstall cycles accumulated blank lines in .zprofile"; exit 1; }

home_existing="$workdir/home-existing"
config_existing="$workdir/config-existing/config.ghostty"
data_existing="$workdir/share-existing/ghostty-zmx"
mkdir -p "$home_existing" "${config_existing:h}" "$data_existing"
print -r -- zmx-existing-11112222-33334444-aaaaaaaa > "$data_existing/sessions"
run_install "$home_existing" "$config_existing" "$data_existing" --yes > /dev/null
grep -qxF 'zmx-existing-11112222-33334444-aaaaaaaa' "$data_existing/sessions" || { print -u2 "existing sessions file was overwritten"; exit 1; }
[[ "$(wc -l < "$data_existing/sessions" | tr -d ' ')" == 1 ]] || { print -u2 "existing sessions file changed"; exit 1; }

run_uninstall "$home" "$config" "$data" "$state" --yes > "$workdir/uninstall.out"
[[ ! -e "$home/.config/ghostty-zmx/session-manager-lib.zsh" ]] || { print -u2 "--yes left shared lib installed"; exit 1; }
[[ ! -e "$home/.config/ghostty-zmx/session-manager-early.zsh" ]] || { print -u2 "--yes left early manager installed"; exit 1; }
! grep -q 'session-manager-early.zsh' "$home/.zprofile" 2>/dev/null || { print -u2 "--yes left early source line"; exit 1; }
[[ -d "$data" ]] || { print -u2 "--yes removed data"; exit 1; }
[[ -d "$state" ]] || { print -u2 "--yes removed state"; exit 1; }
grep -q -- '--remove-data' "$workdir/uninstall.out" || { print -u2 "non-destructive uninstall guidance missing"; exit 1; }

home_prompt="$workdir/home-prompt"
config_prompt="$workdir/config-prompt/config.ghostty"
data_prompt="$workdir/share-prompt/ghostty-zmx"
state_prompt="$workdir/state-prompt/ghostty-zmx"
mkdir -p "$home_prompt" "${config_prompt:h}" "$data_prompt" "$state_prompt"
cat > "$home_prompt/.zshrc" <<'ZSHRC'
# ghostty-zmx
[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"
ZSHRC
cat > "$home_prompt/.zprofile" <<'ZPROFILE'
# ghostty-zmx
[[ -r "$HOME/.config/ghostty-zmx/session-manager-early.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager-early.zsh"
ZPROFILE
cat > "$config_prompt" <<'CFG'
# BEGIN ghostty-zmx
env = GHOSTTY_ZMX_AUTO_ATTACH=1
# END ghostty-zmx
CFG
printf 'n\nn\n' | run_uninstall "$home_prompt" "$config_prompt" "$data_prompt" "$state_prompt" > "$workdir/uninstall-decline.out"
grep -qxF '[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"' "$home_prompt/.zshrc" || { print -u2 "interactive decline removed source line"; exit 1; }
grep -qxF '[[ -r "$HOME/.config/ghostty-zmx/session-manager-early.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager-early.zsh"' "$home_prompt/.zprofile" || { print -u2 "interactive decline removed early source line"; exit 1; }
grep -qxF '# ghostty-zmx' "$home_prompt/.zshrc" || { print -u2 "interactive decline removed installer comment"; exit 1; }
grep -q '^# BEGIN ghostty-zmx$' "$config_prompt" || { print -u2 "interactive decline removed Ghostty block"; exit 1; }
printf 'y\ny\n' | run_uninstall "$home_prompt" "$config_prompt" "$data_prompt" "$state_prompt" > "$workdir/uninstall-accept.out"
! grep -q 'session-manager.zsh' "$home_prompt/.zshrc" || { print -u2 "interactive accept left source line"; exit 1; }
! grep -q 'session-manager-early.zsh' "$home_prompt/.zprofile" || { print -u2 "interactive accept left early source line"; exit 1; }
! grep -q '^# ghostty-zmx$' "$home_prompt/.zshrc" || { print -u2 "interactive accept left installer comment"; exit 1; }
! grep -q '^# BEGIN ghostty-zmx$' "$config_prompt" || { print -u2 "interactive accept left Ghostty block"; exit 1; }
[[ -d "$data_prompt" && -d "$state_prompt" ]] || { print -u2 "interactive accept removed data/state without flags"; exit 1; }

runtime_root="$workdir/runtime-root"
runtime_dir="$runtime_root/ghostty-zmx-${UID:-$(id -u)}"
mkdir -p "$runtime_dir"
touch "$runtime_dir/reaper-test.zsh"
flat_runtime_decoy="$runtime_root/ghostty-zmx-reaper-decoy-$$"
mkdir -p "$flat_runtime_decoy"
touch "$flat_runtime_decoy/nested"
XDG_RUNTIME_DIR="$runtime_root" run_uninstall "$home_prompt" "$config_prompt" "$data_prompt" "$state_prompt" --yes > "$workdir/runtime-uninstall.out"
[[ ! -d "$runtime_dir" ]] || { print -u2 "current runtime directory was not removed"; exit 1; }
[[ -e "$flat_runtime_decoy/nested" ]] || { print -u2 "flat runtime decoy was removed"; exit 1; }

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

unsafe_install_target="$workdir/unsafe-install-target/ghostty-zmx"
unsafe_install_home="$workdir/unsafe-install-home"
unsafe_install_config="$workdir/unsafe-install-config/config.ghostty"
unsafe_install_data="$workdir/unsafe-install-data/ghostty-zmx"
mkdir -p "$unsafe_install_target" "$unsafe_install_home/.config" "${unsafe_install_config:h}" "$unsafe_install_data"
ln -s "$unsafe_install_target" "$unsafe_install_home/.config/ghostty-zmx"
if run_uninstall "$unsafe_install_home" "$unsafe_install_config" "$unsafe_install_data" "$workdir/unsafe-install-state/ghostty-zmx" --yes --remove-install-dir >/dev/null 2>&1; then
  print -u2 "unsafe install symlink deletion was allowed"
  exit 1
fi
[[ -d "$unsafe_install_target" ]] || { print -u2 "unsafe install symlink target was deleted"; exit 1; }

unsafe_data_target="$workdir/unsafe-data-target/ghostty-zmx"
unsafe_data_home="$workdir/unsafe-data-home"
unsafe_data_config="$workdir/unsafe-data-config/config.ghostty"
mkdir -p "$unsafe_data_target" "$unsafe_data_home/.local/share" "${unsafe_data_config:h}"
ln -s "$unsafe_data_target" "$unsafe_data_home/.local/share/ghostty-zmx"
if run_uninstall "$unsafe_data_home" "$unsafe_data_config" "$unsafe_data_home/.local/share/ghostty-zmx" "$workdir/unsafe-data-state/ghostty-zmx" --yes --remove-data >/dev/null 2>&1; then
  print -u2 "unsafe data symlink deletion was allowed"
  exit 1
fi
[[ -d "$unsafe_data_target" ]] || { print -u2 "unsafe data symlink target was deleted"; exit 1; }

unsafe_home="$workdir/unsafe-home"
mkdir -p "$unsafe_home"
if run_uninstall "$unsafe_home" "$workdir/unsafe-config" "$unsafe_home" "$workdir/unsafe-state/ghostty-zmx" --yes --remove-data >/dev/null 2>&1; then
  print -u2 "unsafe data deletion was allowed"
  exit 1
fi

