#!/bin/zsh
set -eu

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data/ghostty-zmx"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state/ghostty-zmx"
export XDG_RUNTIME_DIR="$workdir/runtime"
export GHOSTTY_ZMX_RESTORE_STEP_DELAY=0
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$XDG_RUNTIME_DIR" "$workdir/bin"

cat > "$workdir/bin/zmx" <<'STUB'
#!/bin/zsh
exit 0
STUB
chmod +x "$workdir/bin/zmx"

cat > "$workdir/bin/osascript" <<'STUB'
#!/bin/zsh
script="$(cat)"
if [[ "$script" == *'front window'* ]]; then
  print -r -- 'window:aaaaaaaaaaaaaaaa tab-group-ghostty-zmx-test/tab-bbbbbbbb term:1234abcd'
  exit 0
fi
if [[ "$script" == *'new window'* ]]; then
  print -r -- 'window:cccccccccccccccc tab-group-ghostty-zmx-test/tab-dddddddd'
  exit 0
fi
if [[ "$script" == *'new tab'* ]]; then
  print -r -- 'window:aaaaaaaaaaaaaaaa tab-group-ghostty-zmx-test/tab-eeeeeeee'
  exit 0
fi
exit 0
STUB
chmod +x "$workdir/bin/osascript"
export PATH="$workdir/bin:$PATH"

cat > "$GHOSTTY_ZMX_DATA_HOME/sessions" <<'SESS'
zmx-11111111-22222222-aaaaaaaa
zmx-11111111-33333333-bbbbbbbb
zmx-44444444-22222222-cccccccc
SESS

source "$repo_dir/session-manager.zsh"
ghosttyPID=123
_ghostty_zmx_restore

[[ "$(cat "$GHOSTTY_ZMX_DATA_HOME/restore-first")" == 'zmx-11111111-22222222-aaaaaaaa' ]] || { print -u2 'restore first session mismatch'; exit 1; }
[[ "$(cat "$GHOSTTY_ZMX_DATA_HOME/restore-queue")" == $'zmx-11111111-33333333-bbbbbbbb\nzmx-44444444-22222222-cccccccc' ]] || { print -u2 'restore queue order mismatch'; exit 1; }
grep -qxF 'W aaaaaaaaaaaaaaaa 11111111' "$GHOSTTY_ZMX_DATA_HOME/id-map" || { print -u2 'missing first window id-map entry'; exit 1; }
grep -qxF 'T aaaaaaaaaaaaaaaa bbbbbbbb 11111111 22222222' "$GHOSTTY_ZMX_DATA_HOME/id-map" || { print -u2 'missing first tab id-map entry'; exit 1; }
grep -qxF 'T aaaaaaaaaaaaaaaa eeeeeeee 11111111 33333333' "$GHOSTTY_ZMX_DATA_HOME/id-map" || { print -u2 'missing second tab id-map entry'; exit 1; }
grep -qxF 'W cccccccccccccccc 44444444' "$GHOSTTY_ZMX_DATA_HOME/id-map" || { print -u2 'missing second window id-map entry'; exit 1; }
grep -qxF 'T cccccccccccccccc dddddddd 44444444 22222222' "$GHOSTTY_ZMX_DATA_HOME/id-map" || { print -u2 'missing second window tab id-map entry'; exit 1; }
