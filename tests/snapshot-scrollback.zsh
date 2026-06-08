#!/bin/zsh
set -eu

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state"
export GHOSTTY_ZMX_SCROLLBACK_LINES=3
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$workdir/bin"

cat > "$workdir/bin/zmx" <<'STUB'
#!/bin/zsh
set -eu
cmd="$1"; shift
case "$cmd" in
  history)
    print -- one
    print -- two
    print -- three
    print -- four
    print -- five
    ;;
  list)
    if [[ "${1:-}" == "--short" ]]; then
      [[ -f "$ZMX_EXISTS_FILE" ]] && cat "$ZMX_EXISTS_FILE"
    fi
    ;;
  run)
    [[ "${ZMX_RUN_FAIL:-0}" == 1 ]] && exit 7
    print -r -- "$1" >> "$ZMX_RUN_LOG"
    ;;
  print)
    cat > "$ZMX_PRINT_LOG"
    [[ "${ZMX_PRINT_FAIL:-0}" == 1 ]] && exit 9
    ;;
  *) exit 64 ;;
esac
STUB
chmod +x "$workdir/bin/zmx"
export PATH="$workdir/bin:$PATH"
export ZMX_EXISTS_FILE="$workdir/exists"
export ZMX_RUN_LOG="$workdir/run.log"
export ZMX_PRINT_LOG="$workdir/print.log"

source "$repo_dir/session-manager.zsh"

session="zmx-abc123-def456-1234abcd"
_ghostty_zmx_snapshot_history "$session"
expected=$'three\nfour\nfive'
actual="$(cat "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt")"
[[ "$actual" == "$expected" ]] || { print -u2 "snapshot truncation mismatch: $actual"; exit 1; }

GHOSTTY_ZMX_DEBUG=1 ZMX_PRINT_FAIL=0 _ghostty_zmx_restore_saved_scrollback "$session"
first_line="$(sed -n '1p' "$ZMX_PRINT_LOG")"
[[ "$first_line" == '[ghostty-zmx restored saved scrollback from a previous boot; process state was not restored]' ]] || { print -u2 "missing restore banner"; exit 1; }
[[ "$(sed -n '2p' "$ZMX_PRINT_LOG")" == three ]] || { print -u2 "snapshot content not printed after banner"; exit 1; }
[[ "$(cat "$ZMX_RUN_LOG")" == "$session" ]] || { print -u2 "fresh session was not created before print"; exit 1; }

rm -f "$ZMX_PRINT_LOG" "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt"
_ghostty_zmx_restore_saved_scrollback "$session"
[[ ! -e "$ZMX_PRINT_LOG" ]] || { print -u2 "missing snapshot should not print"; exit 1; }

print -- secret-one > "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt"
GHOSTTY_ZMX_DEBUG=1 ZMX_PRINT_FAIL=1 _ghostty_zmx_restore_saved_scrollback "$session" || true
grep -q 'zmx print failed' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 "missing print failure log"; exit 1; }
! grep -q 'secret-one' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 "debug log leaked saved history"; exit 1; }
