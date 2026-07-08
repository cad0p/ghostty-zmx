#!/bin/zsh
# Unit tests for the projection reconnect loop decision matrix.
#
# Sources cli/projection-loop (with auto-run guarded out) and asserts the
# reconnect decision matrix from the design. The loop's decision logic is
# pure: transport exit code + remote session state + trap flag + owner
# liveness + projection-row state => reconnect or exit.
#
# Each case runs in a fresh `zsh -c` subshell (sourced from this script via a
# helper) so the loop's trap + exit() are isolated and $$ reliably identifies
# the process the trap is installed on. The transport stub sends HUP to $$
# to simulate a close signal during a run.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

pass=0; fail=0
_ok() { print "  ok: $1"; pass=$((pass+1)); }
_bad() { print -u2 "  FAIL: $1"; fail=$((fail+1)); }

# Worker script path (written once below).
_worker="$workdir/worker.zsh"
cat > "$_worker" <<'WORKER'
# Worker: runs one loop case in isolation. Env carries the case params.
export HOME="$GZMX_WORKDIR/home"
export GHOSTTY_ZMX_DATA_HOME="$GZMX_WORKDIR/data"
export GHOSTTY_ZMX_STATE_HOME="$GZMX_WORKDIR/state"
export GHOSTTY_ZMX_DEBUG=0
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME"
typeset _GZMX_PROJECTION_LOOP_NO_AUTO_RUN=1
typeset -ga _add_argv; _add_argv=(true)
typeset _remote_zmx="zmx"
host="test-host"; session="gzr-test-1-1-1-1"
source "$GZMX_REPO_DIR/cli/projection-loop"
_gzmx_wdebug() { :; }
_gzmx_detect_ghostty_pid() { print -r -- "$$"; }
_gzmx_ghostty_elapsed() { print -r -- "1000"; }
_gzmx_owner_alive() { [[ "${_GZMX_TEST_OWNER_ALIVE:-1}" == "1" ]]; }
_gzmx_projection_row_closing() { [[ "${_GZMX_TEST_ROW_CLOSING:-0}" == "1" ]]; }
_gzmx_snapshot_session() { :; }
_gzmx_reboot_restore_check() { :; }
_gzmx_session_state() { print -r -- "${_GZMX_TEST_SESSION_STATE:-survived}"; }
sleep() { [[ "${_GZMX_TEST_TRAP_DURING_SLEEP:-0}" == "1" ]] && kill -HUP $$ 2>/dev/null; }
echo 0 > "$GZMX_WORKDIR/counter"
_gzmx_test_transport() {
  local c
  c=$(cat "$GZMX_WORKDIR/counter" 2>/dev/null || echo 0); c=$((c + 1))
  echo "$c" > "$GZMX_WORKDIR/counter"
  [[ "${_GZMX_TEST_TRAP_DURING_RUN:-0}" == "1" ]] && kill -HUP $$ 2>/dev/null
  return "${_GZMX_TEST_TRANSPORT_RC:-0}"
}
_gzmx_run_projection_loop _gzmx_test_transport
# (exit code propagates as the worker's exit status)
WORKER

# Run a case via the worker. The worker's own exit status IS the loop's exit
# code (the loop calls exit, which propagates). The transport call count is
# read from the counter file.
_run_case() {
  local session_state="$1" rc="$2" max_attempts="${3:-0}" trap_during_run="${4:-0}" trap_during_sleep="${5:-0}" owner_alive="${6:-1}" row_closing="${7:-0}"
  rm -f "$workdir/counter"
  GZMX_REPO_DIR="$repo_dir" GZMX_WORKDIR="$workdir" \
  _GZMX_TEST_SESSION_STATE="$session_state" \
  _GZMX_TEST_TRANSPORT_RC="$rc" \
  GHOSTTY_ZMX_RECONNECT_MAX_ATTEMPTS="$max_attempts" \
  GHOSTTY_ZMX_RECONNECT_INITIAL_BACKOFF=1 \
  GHOSTTY_ZMX_RECONNECT_MAX_BACKOFF=1 \
  _GZMX_TEST_TRAP_DURING_RUN="$trap_during_run" \
  _GZMX_TEST_TRAP_DURING_SLEEP="$trap_during_sleep" \
  _GZMX_TEST_OWNER_ALIVE="$owner_alive" \
  _GZMX_TEST_ROW_CLOSING="$row_closing" \
  zsh "$_worker" 2>/dev/null
  echo $?  # the worker's exit status = the loop's exit code
}

_attempts() { cat "$workdir/counter" 2>/dev/null || echo 0; }

# ---------------------------------------------------------------------------
# Case 2: ssh rc 255 + survived => reconnect (attempt counter increments)
# ---------------------------------------------------------------------------
print "case 2: ssh rc 255 + survived => reconnect"
_rc=$(_run_case survived 255 2)
_a=$(_attempts)
# max_attempts=2: run(1) -> reconnect -> run(2) -> max reached => exit. 2 calls.
(( _a == 2 )) && _ok "reconnected (2 transport calls)" || _bad "expected 2 transport calls, got $_a"
(( _rc == 255 )) && _ok "exit code preserved (255)" || _bad "expected exit 255, got $_rc"

# ---------------------------------------------------------------------------
# Case 3: ssh rc 255 + gone => reconnect (reboot-restore path fires)
# ---------------------------------------------------------------------------
print ""
print "case 3: ssh rc 255 + gone => reconnect (reboot-restore path)"
_rc=$(_run_case gone 255 2)
_a=$(_attempts)
(( _a >= 2 )) && _ok "reconnected via reboot-restore path ($_a calls)" || _bad "expected >=2 calls, got $_a"

# ---------------------------------------------------------------------------
# Case 4: ssh rc 255 + live => exit (duplicate)
# ---------------------------------------------------------------------------
print ""
print "case 4: ssh rc 255 + live => exit (duplicate)"
_rc=$(_run_case live 255 0)
_a=$(_attempts)
(( _a == 1 )) && _ok "no reconnect (1 transport call)" || _bad "expected 1 call, got $_a"
(( _rc == 255 )) && _ok "exit code preserved (255)" || _bad "expected exit 255, got $_rc"

# ---------------------------------------------------------------------------
# Case 5: trap fired (during run) => exit 0 (trap wins)
# ---------------------------------------------------------------------------
print ""
print "case 5: trap fired during run => exit 0"
_rc=$(_run_case survived 255 0 1)
_a=$(_attempts)
(( _a == 1 )) && _ok "no reconnect after trap (1 call)" || _bad "expected 1 call, got $_a"
(( _rc == 0 )) && _ok "exit 0 (trap wins)" || _bad "expected exit 0, got $_rc"

# ---------------------------------------------------------------------------
# Case 6: owner dead => exit
# ---------------------------------------------------------------------------
print ""
print "case 6: owner dead => exit"
_rc=$(_run_case survived 255 0 0 0 0)
_a=$(_attempts)
(( _a == 0 )) && _ok "no transport run (owner dead at top-of-loop)" || _bad "expected 0 calls, got $_a"
(( _rc != 0 )) && _ok "non-zero exit (owner-dead)" || _bad "expected non-zero exit, got $_rc"

# ---------------------------------------------------------------------------
# Case 7: max-attempts reached => exit
# ---------------------------------------------------------------------------
print ""
print "case 7: max-attempts reached => exit"
_rc=$(_run_case survived 255 3)
_a=$(_attempts)
(( _a == 3 )) && _ok "3 transport calls then exit (max-attempts)" || _bad "expected 3 calls, got $_a"
(( _rc == 255 )) && _ok "exit code preserved (255)" || _bad "expected exit 255, got $_rc"

# ---------------------------------------------------------------------------
# Case 8: rc 1 + survived => reconnect (other non-zero)
# ---------------------------------------------------------------------------
print ""
print "case 8: rc 1 + survived => reconnect (other non-zero)"
_rc=$(_run_case survived 1 2)
_a=$(_attempts)
(( _a == 2 )) && _ok "reconnected on rc 1 (2 calls)" || _bad "expected 2 calls, got $_a"
(( _rc == 1 )) && _ok "exit code preserved (1)" || _bad "expected exit 1, got $_rc"

# ---------------------------------------------------------------------------
# Case 9: projection row closing => exit (cross-client close)
# ---------------------------------------------------------------------------
print ""
print "case 9: projection row closing => exit (cross-client close)"
_rc=$(_run_case survived 255 0 0 0 1 1)
_a=$(_attempts)
(( _a == 0 )) && _ok "no transport run (closing row at top-of-loop)" || _bad "expected 0 calls, got $_a"
(( _rc == 0 )) && _ok "exit 0 (cross-client close)" || _bad "expected exit 0, got $_rc"

# ---------------------------------------------------------------------------
# Case 10: trap during sleep => exit 0 (no new transport started)
# ---------------------------------------------------------------------------
print ""
print "case 10: trap during sleep => exit 0 (no new transport)"
# run(1) exits 255 + survived => reconnect => sleep sends HUP =>
# top-of-loop check on next iteration exits 0 without a new transport.
_rc=$(_run_case survived 255 0 0 1)
_a=$(_attempts)
(( _a == 1 )) && _ok "only 1 transport run (trap during sleep stopped reconnect)" || _bad "expected 1 call, got $_a"
(( _rc == 0 )) && _ok "exit 0 (trap during sleep)" || _bad "expected exit 0, got $_rc"

# ---------------------------------------------------------------------------
# Case 1: rc 0 + survived => reconnect (no rc-0 special-case)
# ssh doesn't exit on user 'exit' (zmx intercepts as detach), so rc 0 is not
# treated as "intentional leave" — the session-state check still drives it.
# ---------------------------------------------------------------------------
print ""
print "case 1: rc 0 + survived => reconnect (no rc-0 special-case)"
_rc=$(_run_case survived 0 2)
_a=$(_attempts)
(( _a == 2 )) && _ok "reconnected on rc 0 (2 calls)" || _bad "expected 2 calls, got $_a"

print ""
if [[ "$fail" -eq 0 ]]; then
  print "all projection-loop tests passed ($pass/$pass)"
  exit 0
else
  print -u2 "$fail test(s) failed"
  exit 1
fi
