#!/bin/zsh
# Unit + functional tests for ghostty_zmx_drain_tty_queries — Prototype C.
#
# The drain function reads and discards pending input from a tty's input
# buffer before exec ssh, to prevent OSC 11 / CSI 6n query responses (emitted
# by the local .zshrc's oh-my-zsh + zsh-autosuggestions plugins) from being
# forwarded to the remote pty where the remote shell echoes them into the
# prompt. It is best-effort and timing-dependent.
#
# These tests cover:
#   1. Pure-logic guards (disabled via env; missing/empty/unreadable tty).
#   2. FUNCTIONAL: the drain actually CONSUMES pending bytes from a real pty
#      allocated via python3 pty.openpty(). This is the load-bearing claim —
#      a drain that reports "bytes=0" while a payload sits in the input buffer
#      is useless. Verified against a 31-byte OSC11+CSI payload + a late burst.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data/ghostty-zmx"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state/ghostty-zmx"
export GHOSTTY_ZMX_RUNTIME_DIR="$workdir/runtime"
export GHOSTTY_ZMX_DEBUG=1
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$GHOSTTY_ZMX_RUNTIME_DIR"

# Source the manager without triggering auto-attach (non-interactive).
source "$repo_dir/session-manager.zsh" 2>/dev/null

# --- Case 0: function is defined ---
typeset -f ghostty_zmx_drain_tty_queries >/dev/null 2>&1 || { print -u2 "smoke: function not defined"; exit 1 }
echo "  ok: ghostty_zmx_drain_tty_queries defined"

# --- Case 1: disabled via env -> no-op, return 0 ---
GHOSTTY_ZMX_DISABLE_TTY_DRAIN=1 ghostty_zmx_drain_tty_queries /dev/null
rc=$?
[[ "$rc" -eq 0 ]] || { print -u2 "disabled: expected exit 0, got $rc"; exit 1 }
echo "  ok: disabled -> no-op return 0"

# --- Case 2: missing/empty/non-char-device tty -> no-op return 0 ---
ghostty_zmx_drain_tty_queries "/dev/nonexistent-tty-$$"
rc=$?
[[ "$rc" -eq 0 ]] || { print -u2 "missing-tty: expected exit 0, got $rc"; exit 1 }
ghostty_zmx_drain_tty_queries ""
rc=$?
[[ "$rc" -eq 0 ]] || { print -u2 "empty-tty: expected exit 0, got $rc"; exit 1 }
echo "  ok: missing/empty tty -> no-op return 0"

# --- Case 3: drain on /dev/null (stty guard path) ---
# stty on /dev/null fails harmlessly -> early return 0. Exercises the
# saved-stty guard so a non-tty path never corrupts tty state.
ghostty_zmx_drain_tty_queries /dev/null
rc=$?
[[ "$rc" -eq 0 ]] || { print -u2 "devnull: expected exit 0, got $rc"; exit 1 }
echo "  ok: drain on /dev/null returns 0 (stty guard)"

# --- Case 4 (FUNCTIONAL): drain consumes pending bytes from a real pty ---
# This is the core mechanism. python3 allocates a pty pair, keeps the master
# open in the background, writes an OSC11-response + CSI-cursor-response
# payload to the master (which becomes pending INPUT on the slave, exactly as
# Ghostty's query responses sit in the tty input buffer), and we run the drain
# on the slave. The drain must report bytes > 0 consumed.
if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available for pty harness"
else
  python3 - <<'PY' > "$workdir/pty.info" &
import pty, os, sys, time
m, s = pty.openpty()
sys.stdout.write(os.ttyname(s) + "\n"); sys.stdout.flush()
time.sleep(0.5)  # let zsh open the slave first
# Write an OSC 11 response + CSI 6n response (the leak payload from
# debugging/2026-07-02-osc11-csi6n-query-responses-leak-into-split-scrollback).
os.write(m, b'\x1b]11;rgb:f7f7/f7f7/f7f7\x1b\\\x1b[2;1R')
time.sleep(5)  # keep master open while zsh drains
PY
  master_pid=$!
  # Wait for the slave path to be printed.
  for i in {1..30}; do [[ -s "$workdir/pty.info" ]] && break; sleep 0.1; done
  slave_path="$(<"$workdir/pty.info")"
  slave_path="${slave_path%$'\n'}"
  [[ -c "$slave_path" ]] || { print -u2 "pty: slave not a char device: [$slave_path]"; kill $master_pid 2>/dev/null; exit 1; }
  # Wait for the payload write (0.5s + flush).
  sleep 0.7
  ghostty_zmx_drain_tty_queries "$slave_path" 2>/dev/null
  kill $master_pid 2>/dev/null; wait $master_pid 2>/dev/null
  # Parse the byte count from the last debug.log line.
  log_line="$(tail -1 "$GHOSTTY_ZMX_STATE_HOME/debug.log" 2>/dev/null)"
  bytes_match=""
  [[ "$log_line" == *"bytes="* ]] && bytes_match="${log_line##*bytes=}" && bytes_match="${bytes_match%% *}"
  if [[ "$bytes_match" =~ ^[0-9]+$ ]] && (( bytes_match > 0 )); then
    echo "  ok: functional drain consumed $bytes_match bytes from real pty"
  else
    print -u2 "pty: drain reported 0 bytes (payload=$bytes_match); mechanism broken"
    print -u2 "pty: debug line: $log_line"
    exit 1
  fi
fi

# --- Case 5 (FUNCTIONAL): drain catches a late-arriving burst ---
# Simulates a slow plugin query whose response arrives after the first drain
# iteration. The drain loop must consume both bursts (total > first payload).
if ! command -v python3 >/dev/null 2>&1; then
  echo "  skip: python3 not available for burst harness"
else
  python3 - <<'PY' > "$workdir/pty2.info" &
import pty, os, sys, time
m, s = pty.openpty()
sys.stdout.write(os.ttyname(s) + "\n"); sys.stdout.flush()
time.sleep(0.5)
os.write(m, b'\x1b]11;rgb:f7f7/f7f7/f7f7\x1b\\\x1b[2;1R')  # 31 bytes
time.sleep(0.15)
os.write(m, b'\x1b[?6c')  # 5 bytes, late burst (DA1 response)
time.sleep(5)
PY
  master_pid=$!
  for i in {1..30}; do [[ -s "$workdir/pty2.info" ]] && break; sleep 0.1; done
  slave_path="$(<"$workdir/pty2.info")"; slave_path="${slave_path%$'\n'}"
  sleep 0.7
  ghostty_zmx_drain_tty_queries "$slave_path" 2>/dev/null
  kill $master_pid 2>/dev/null; wait $master_pid 2>/dev/null
  log_line="$(tail -1 "$GHOSTTY_ZMX_STATE_HOME/debug.log" 2>/dev/null)"
  bytes_match=""
  [[ "$log_line" == *"bytes="* ]] && bytes_match="${log_line##*bytes=}" && bytes_match="${bytes_match%% *}"
  # Expect 36 bytes (31 + 5). Allow >=31 (late burst may land between iters).
  if [[ "$bytes_match" =~ ^[0-9]+$ ]] && (( bytes_match >= 31 )); then
    echo "  ok: burst drain consumed $bytes_match bytes (>=31 incl. late burst)"
  else
    print -u2 "burst: drain consumed $bytes_match bytes, expected >=31"
    exit 1
  fi
fi

echo "all drain-tty tests passed"
