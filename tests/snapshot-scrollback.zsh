#!/bin/zsh
set -eu

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state"
export XDG_RUNTIME_DIR="$workdir/runtime"
export GHOSTTY_ZMX_SCROLLBACK_LINES=3
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$XDG_RUNTIME_DIR" "$workdir/bin"

cat > "$workdir/bin/zmx" <<'STUB'
#!/bin/zsh
set -eu
cmd="$1"; shift
case "$cmd" in
  history)
    [[ "${ZMX_HISTORY_FAIL:-0}" == 1 ]] && exit 8
    print -- one
    print -- two
    print -- three
    print -- four
    print -- five
    ;;
  list)
    [[ "${ZMX_LIST_FAIL:-0}" == 1 ]] && exit 9
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
print -r -- zmx-other > "$ZMX_EXISTS_FILE"
export ZMX_RUN_LOG="$workdir/run.log"
export ZMX_PRINT_LOG="$workdir/print.log"

export GHOSTTY_ZMX_KEEP_HELPERS=1

source "$repo_dir/session-manager.zsh"

reaper_body="$(awk '
  $0 == "  cat >> \"$script\" <<'"'"'EOS'"'"'" { in_body=1; next }
  $0 == "EOS" && in_body { exit }
  in_body { print }
' "$repo_dir/session-manager.zsh")"
print -r -- "$reaper_body" > "$workdir/generated-reaper.zsh"
zsh -n "$workdir/generated-reaper.zsh" || { print -u2 "generated reaper script has invalid zsh syntax"; exit 1; }
reaper_elapsed_helper="$(awk '
  $0 == "parse_elapsed_seconds() {" { in_helper=1 }
  $0 == "elapsed_seconds() {" && in_helper { exit }
  in_helper { print }
' "$workdir/generated-reaper.zsh")"
print -r -- "$reaper_elapsed_helper" > "$workdir/generated-reaper-elapsed.zsh"
source "$workdir/generated-reaper-elapsed.zsh"
[[ "$(parse_elapsed_seconds '01:27')" == 87 ]] || { print -u2 "generated reaper did not parse MM:SS elapsed time"; exit 1; }
[[ "$(parse_elapsed_seconds '00:01:27')" == 87 ]] || { print -u2 "generated reaper did not parse HH:MM:SS elapsed time"; exit 1; }
[[ "$(parse_elapsed_seconds '1-00:01:27')" == 86487 ]] || { print -u2 "generated reaper did not parse D-HH:MM:SS elapsed time"; exit 1; }
if parse_elapsed_seconds 'bad' >/dev/null 2>&1; then
  print -u2 "generated reaper accepted invalid elapsed time"
  exit 1
fi

[[ "$(_ghostty_zmx_parse_elapsed_seconds '01:27')" == 87 ]] || { print -u2 "main helper did not parse MM:SS elapsed time"; exit 1; }
[[ "$(_ghostty_zmx_parse_elapsed_seconds '00:01:27')" == 87 ]] || { print -u2 "main helper did not parse HH:MM:SS elapsed time"; exit 1; }
[[ "$(_ghostty_zmx_parse_elapsed_seconds '1-00:01:27')" == 86487 ]] || { print -u2 "main helper did not parse D-HH:MM:SS elapsed time"; exit 1; }
if _ghostty_zmx_parse_elapsed_seconds 'bad' >/dev/null 2>&1; then
  print -u2 "main helper accepted invalid elapsed time"
  exit 1
fi

[[ "$GHOSTTY_ZMX_SCROLLBACK_LINES" == 3 ]] || { print -u2 "scrollback limit was not preserved"; exit 1; }
GHOSTTY_ZMX_SCROLLBACK_LINES=bad
GHOSTTY_ZMX_DEBUG=1
export GHOSTTY_ZMX_KEEP_HELPERS=1
source "$repo_dir/session-manager.zsh"
[[ "$GHOSTTY_ZMX_SCROLLBACK_LINES" == 1000 ]] || { print -u2 "invalid scrollback limit did not default"; exit 1; }
grep -q 'invalid scrollback line count value=bad defaulting=1000' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 "missing invalid scrollback fallback log"; exit 1; }
export GHOSTTY_ZMX_SCROLLBACK_LINES=3

session="zmx-abc123-def456-1234abcd"
_ghostty_zmx_snapshot_history "$session"
expected=$'three\nfour\nfive'
actual="$(cat "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt")"
[[ "$actual" == "$expected" ]] || { print -u2 "snapshot truncation mismatch: $actual"; exit 1; }

print -- keep > "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt"
ZMX_HISTORY_FAIL=1 _ghostty_zmx_snapshot_history "$session" || true
unset ZMX_HISTORY_FAIL
[[ "$(cat "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt")" == keep ]] || { print -u2 "failed zmx history overwrote snapshot"; exit 1; }

grep -q 'scrollback snapshot failed session=' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 "missing history failure log"; exit 1; }

print -- three > "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt"
print -- four >> "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt"
print -- five >> "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt"
GHOSTTY_ZMX_DEBUG=1 ZMX_PRINT_FAIL=0 _ghostty_zmx_restore_saved_scrollback "$session"
first_line="$(sed -n '1p' "$ZMX_PRINT_LOG")"
[[ "$first_line" == '[ghostty-zmx restored saved scrollback from a previous boot; process state was not restored]' ]] || { print -u2 "missing restore banner"; exit 1; }
[[ "$(sed -n '2p' "$ZMX_PRINT_LOG")" == three ]] || { print -u2 "snapshot content not printed after banner"; exit 1; }
[[ "$(cat "$ZMX_RUN_LOG")" == "$session" ]] || { print -u2 "fresh session was not created before print"; exit 1; }

rm -f "$ZMX_PRINT_LOG" "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt"
print -- keep > "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt"
GHOSTTY_ZMX_DEBUG=1 ZMX_LIST_FAIL=1 _ghostty_zmx_restore_saved_scrollback "$session"
unset ZMX_LIST_FAIL
[[ ! -e "$ZMX_PRINT_LOG" ]] || { print -u2 "zmx list failure should skip restore print"; exit 1; }
[[ "$(cat "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt")" == keep ]] || { print -u2 "zmx list failure changed snapshot"; exit 1; }
grep -q 'zmx list --short failed session=' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 "missing zmx list failure log"; exit 1; }

rm -f "$ZMX_PRINT_LOG" "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt"
_ghostty_zmx_restore_saved_scrollback "$session"
[[ ! -e "$ZMX_PRINT_LOG" ]] || { print -u2 "missing snapshot should not print"; exit 1; }

print -- secret-one > "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt"
GHOSTTY_ZMX_DEBUG=1 ZMX_PRINT_FAIL=1 _ghostty_zmx_restore_saved_scrollback "$session" || true
grep -q 'zmx print failed' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 "missing print failure log"; exit 1; }
! grep -q 'secret-one' "$GHOSTTY_ZMX_STATE_HOME/debug.log" || { print -u2 "debug log leaked saved history"; exit 1; }
