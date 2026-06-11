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
set -eu
cmd="${1:-}"; shift || true
case "$cmd" in
  attach)
    print -r -- "$1" >> "$ZMX_ATTACH_LOG"
    ;;
  list)
    ;;
  run)
    ;;
  print)
    cat >/dev/null
    ;;
  *)
    exit 0
    ;;
esac
STUB
chmod +x "$workdir/bin/zmx"
export ZMX_ATTACH_LOG="$workdir/zmx-attach.log"

cat > "$workdir/bin/osascript" <<'STUB'
#!/bin/zsh
if [[ "${1:-}" == "-e" ]]; then
  [[ "$*" == *'get version'* ]] && exit 0
fi
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
cat > "$workdir/bin/ps" <<'STUB'
#!/bin/zsh
if [[ "$*" == *'comm='* ]]; then
  print -r -- ghostty
elif [[ "$*" == *'ppid='* ]]; then
  print -r -- 1
elif [[ "$*" == *'etime='* ]]; then
  print -r -- '00:00:01'
elif [[ "$*" == *'lstart='* ]]; then
  print -r -- 'Mon Jun  8 12:00:00 2026'
fi
STUB
chmod +x "$workdir/bin/ps"
export PATH="$workdir/bin:$PATH"

cat > "$GHOSTTY_ZMX_DATA_HOME/sessions" <<'SESS'
zmx-11111111-22222222-aaaaaaaa
zmx-11111111-33333333-bbbbbbbb
zmx-44444444-22222222-cccccccc
SESS

export GHOSTTY_ZMX_KEEP_HELPERS=1

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

cat > "$workdir/bin/osascript" <<'STUB'
#!/bin/zsh
if [[ "${1:-}" == "-e" ]]; then
  [[ "$*" == *'get version'* ]] && exit 0
fi
script="$(cat)"
if [[ "$script" == *'front window'* ]]; then
  print -r -- 'window:aaaaaaaaaaaaaaaa tab-group-ghostty-zmx-test/tab-bbbbbbbb term:1234abcd'
  exit 0
fi
if [[ "$script" == *'new tab'* ]]; then
  exit 1
fi
exit 0
STUB
chmod +x "$workdir/bin/osascript"
rm -f "$GHOSTTY_ZMX_DATA_HOME/id-map" "$GHOSTTY_ZMX_DATA_HOME/restore-first" "$GHOSTTY_ZMX_DATA_HOME/restore-queue"
GHOSTTY_ZMX_DEBUG=1
: > "$GHOSTTY_ZMX_STATE_HOME/debug.log"
cat > "$GHOSTTY_ZMX_DATA_HOME/sessions" <<'SESS'
zmx-11111111-22222222-aaaaaaaa
zmx-11111111-33333333-bbbbbbbb
SESS
if _ghostty_zmx_restore; then
  print -u2 'restore succeeded despite failed surface creation'
  exit 1
fi
[[ "$(cat "$GHOSTTY_ZMX_DATA_HOME/restore-queue")" == '' ]] || { print -u2 'failed surface session remained queued'; exit 1; }
grep -q 'restore failed step=new-tab' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 'restore surface failure was not logged'; exit 1; }
grep -q 'restore failed status=incomplete' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 'incomplete restore status was not logged'; exit 1; }

cat > "$workdir/bin/osascript" <<'STUB'
#!/bin/zsh
if [[ "${1:-}" == "-e" ]]; then
  [[ "$*" == *'get version'* ]] && exit 0
fi
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

rm -f "$ZMX_ATTACH_LOG" "$GHOSTTY_ZMX_DATA_HOME/sessions" "$GHOSTTY_ZMX_DATA_HOME/restore-first" "$GHOSTTY_ZMX_DATA_HOME/restore-queue" "$GHOSTTY_ZMX_DATA_HOME/id-map"
rm -rf "$XDG_RUNTIME_DIR/ghostty-zmx-${UID:-$(id -u)}"
GHOSTTY_ZMX_DEBUG=1 GHOSTTY_ZMX_AUTO_ATTACH=1 env -u ZMX_SESSION -u TMUX zsh -fic "source ${(q)repo_dir}/session-manager.zsh"
restore_lock_count="$(print -r -- "$XDG_RUNTIME_DIR"/ghostty-zmx-${UID:-$(id -u)}/restore-*.lock(N) | wc -w | tr -d ' ')"
[[ "$restore_lock_count" == 0 ]] || { print -u2 'restore driver lock was not released after first shell startup'; exit 1; }
[[ -f "$ZMX_ATTACH_LOG" && "$(cat "$ZMX_ATTACH_LOG")" == 'zmx-aaaaaaaaaaaaaaaa-bbbbbbbb-1234abcd' ]] || { print -u2 'generated first-launch session was not attached'; exit 1; }
grep -qxF 'zmx-aaaaaaaaaaaaaaaa-bbbbbbbb-1234abcd' "$GHOSTTY_ZMX_DATA_HOME/sessions" || { print -u2 'generated first-launch session was not logged'; exit 1; }
grep -q 'restore-driver released' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 'restore driver release was not logged'; exit 1; }
grep -q 'current position result=aaaaaaaaaaaaaaaa bbbbbbbb 1234abcd' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 'current position was not logged'; exit 1; }
grep -q 'session generated session=zmx-aaaaaaaaaaaaaaaa-bbbbbbbb-1234abcd' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 'generated session was not logged'; exit 1; }
[[ ! -e "$GHOSTTY_ZMX_DATA_HOME/restore-first" ]] || { print -u2 'restore-first file was not consumed'; exit 1; }
restoring_lock_count="$(print -r -- "$XDG_RUNTIME_DIR"/ghostty-zmx-${UID:-$(id -u)}/restoring-*.lock(N) | wc -w | tr -d ' ')"
[[ "$restoring_lock_count" == 0 ]] || { print -u2 'restore-active lock was created without sessions'; exit 1; }

rm -rf "$XDG_RUNTIME_DIR/ghostty-zmx-${UID:-$(id -u)}"
: > "$GHOSTTY_ZMX_STATE_HOME/debug.log"
rm -f "$GHOSTTY_ZMX_DATA_HOME/id-map" "$GHOSTTY_ZMX_DATA_HOME/restore-first" "$GHOSTTY_ZMX_DATA_HOME/restore-queue"
cat > "$GHOSTTY_ZMX_DATA_HOME/sessions" <<'SESS'
zmx-11111111-22222222-aaaaaaaa
SESS
: > "$ZMX_ATTACH_LOG"
GHOSTTY_ZMX_DEBUG=1 GHOSTTY_ZMX_AUTO_ATTACH=1 env -u ZMX_SESSION -u TMUX zsh -fic "
  source ${(q)repo_dir}/session-manager.zsh
  unset ZMX_SESSION
  source ${(q)repo_dir}/session-manager.zsh
"
restore_elections="$(grep -c 'restore-driver elected ghostty_pid=' "$GHOSTTY_ZMX_STATE_HOME/debug.log")"
[[ "$restore_elections" == 1 ]] || { print -u2 "restore driver was elected $restore_elections times for one Ghostty process"; exit 1; }
grep -q 'restore-driver skipped reason=already-attempted' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 'repeated restore attempt was not skipped'; exit 1; }
[[ "$(tail -n 1 "$ZMX_ATTACH_LOG")" == 'zmx-11111111-22222222-1234abcd' ]] || { print -u2 'later shell did not generate and attach a fresh surface session'; exit 1; }
attach_count="$(grep -cxF 'zmx-11111111-22222222-aaaaaaaa' "$ZMX_ATTACH_LOG")"
[[ "$attach_count" == 1 ]] || { print -u2 'existing restore-first session was attached more than once'; exit 1; }
grep -q 'session generated session=zmx-11111111-22222222-1234abcd' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 'later fresh session generation was not logged'; exit 1; }

GHOSTTY_ZMX_DEBUG=1 GHOSTTY_ZMX_AUTO_ATTACH=1 env -u ZMX_SESSION -u TMUX zsh -fc "source ${(q)repo_dir}/session-manager.zsh"
grep -q 'auto-attach skipped reason=non-interactive' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 'non-interactive guard skip was not logged'; exit 1; }
