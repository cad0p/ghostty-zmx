#!/bin/zsh
# Unit tests for the projection reconnect loop decision matrix.
#
# Sources cli/projection-loop (with auto-run guarded out) and asserts the
# reconnect decision matrix from the design. The loop's decision logic is
# pure: transport exit code + remote session state + owner liveness +
# projection-row state => reconnect or exit. The trap flag (set by HUP/TERM/INT)
# does NOT drive an exit decision: a real network drop sends SIGHUP to the
# process group when the ssh child dies, firing the trap; the owner stays
# alive, so the loop must reconnect. The owner-dead check is the real
# intentional-close signal (Cmd-Q/Cmd-W kills the owner).
#
# Each case runs in a fresh `zsh -c` subshell (sourced from this script via a
# helper) so the loop's trap + exit() are isolated and $$ reliably identifies
# the process the trap is installed on. The transport stub sends HUP to $$
# to simulate a close signal during a run; the owner-alive stub controls
# whether the loop treats the trap as a real close (owner dead) or a
# network drop (owner alive).

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
_gzmx_owner_alive() {
  # If _GZMX_TEST_OWNER_DEAD_AFTER_RUN is set, the owner is alive until the
  # transport has run at least once, then dead (simulates Cmd-W: owner dies
  # during the transport run, after the top-of-loop check passed).
  if [[ "${_GZMX_TEST_OWNER_DEAD_AFTER_RUN:-0}" == "1" ]]; then
    local _c
    _c=$(cat "$GZMX_WORKDIR/counter" 2>/dev/null || echo 0)
    (( _c >= 1 )) && return 1 || return 0
  fi
  [[ "${_GZMX_TEST_OWNER_ALIVE:-1}" == "1" ]]
}
_gzmx_projection_row_closing() {
  # If _GZMX_TEST_ROW_CLOSING_AFTER_RUN is set, return not-closing until the
  # transport has run at least once, then return closing (simulates a
  # cross-client close during the transport run).
  if [[ "${_GZMX_TEST_ROW_CLOSING_AFTER_RUN:-0}" == "1" ]]; then
    local _c
    _c=$(cat "$GZMX_WORKDIR/counter" 2>/dev/null || echo 0)
    (( _c >= 1 )) && return 0 || return 1
  fi
  [[ "${_GZMX_TEST_ROW_CLOSING:-0}" == "1" ]]
}
_gzmx_snapshot_session() { :; }
_gzmx_reboot_restore_check() {
  local c
  c=$(cat "$GZMX_WORKDIR/reboot_counter" 2>/dev/null || echo 0); c=$((c + 1))
  echo "$c" > "$GZMX_WORKDIR/reboot_counter"
}
_gzmx_session_state() { print -r -- "${_GZMX_TEST_SESSION_STATE:-survived}"; }
sleep() { [[ "${_GZMX_TEST_TRAP_DURING_SLEEP:-0}" == "1" ]] && kill -HUP $$ 2>/dev/null; }
echo 0 > "$GZMX_WORKDIR/counter"
echo 0 > "$GZMX_WORKDIR/reboot_counter"
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
  local session_state="$1" rc="$2" max_attempts="${3:-0}" trap_during_run="${4:-0}" trap_during_sleep="${5:-0}" owner_alive="${6:-1}" row_closing="${7:-0}" row_closing_after_run="${8:-0}" owner_dead_after_run="${9:-0}"
  rm -f "$workdir/counter" "$workdir/reboot_counter"
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
  _GZMX_TEST_ROW_CLOSING_AFTER_RUN="$row_closing_after_run" \
  _GZMX_TEST_OWNER_DEAD_AFTER_RUN="$owner_dead_after_run" \
  script -q /dev/null zsh "$_worker" >/dev/null 2>&1
  echo $?  # the worker's exit status = the loop's exit code
}

_attempts() { cat "$workdir/counter" 2>/dev/null || echo 0; }
_reboot_calls() { cat "$workdir/reboot_counter" 2>/dev/null || echo 0; }

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
# Case 3b: ssh rc 255 + unknown (ssh check failed) => reconnect WITHOUT
# reboot-restore on subsequent iterations (don't clobber a possibly-live
# session on a transient failure). The first iteration's reboot-restore is
# the cold-start path (runs before any transport); the skip applies to the
# next iteration.
# ---------------------------------------------------------------------------
print ""
print "case 3b: ssh rc 255 + unknown => reconnect without reboot-restore"
_rc=$(_run_case unknown 255 2)
_a=$(_attempts)
_rb=$(_reboot_calls)
(( _a >= 2 )) && _ok "reconnected ($_a calls)" || _bad "expected >=2 calls, got $_a"
# 1 reboot-restore call = cold start only; NOT 2 (would mean it ran after unknown)
(( _rb == 1 )) && _ok "reboot-restore only on cold start (1 call)" || _bad "expected 1 reboot-restore call, got $_rb"

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
# Case 5: trap fired during run + owner alive => reconnect (not exit)
# A real network drop sends SIGHUP to the process group when the ssh child
# dies, firing the trap. The owner (Ghostty) stays alive, so the loop must
# reconnect rather than exit on the trap flag alone. Bounded by max_attempts
# so the test terminates.
# ---------------------------------------------------------------------------
print ""
print "case 5: trap fired during run + owner alive => reconnect"
_rc=$(_run_case survived 255 2 1)
_a=$(_attempts)
(( _a == 2 )) && _ok "reconnected after trap (2 calls)" || _bad "expected 2 calls, got $_a"
(( _rc == 255 )) && _ok "exit code preserved (255)" || _bad "expected exit 255, got $_rc"

# ---------------------------------------------------------------------------
# Case 5b: trap fired during run + owner dead => exit (owner-dead wins)
# The trap fires (e.g. Cmd-W sends SIGHUP) AND the owner is dead — the loop
# exits via the owner-dead check, not the trap flag. This is the real
# intentional-close path: Cmd-W kills Ghostty (owner dead) and sends SIGHUP
# (trap fires); the owner-dead check is what drives the exit.
# ---------------------------------------------------------------------------
print ""
print "case 5b: trap fired during run + owner dead => exit (owner-dead)"
# owner alive at top-of-loop, dead after the transport runs (9th arg).
_rc=$(_run_case survived 255 0 1 0 1 0 0 1)
_a=$(_attempts)
(( _a == 1 )) && _ok "1 transport run (owner died during run)" || _bad "expected 1 call, got $_a"
(( _rc != 0 )) && _ok "non-zero exit (owner-dead)" || _bad "expected non-zero exit, got $_rc"

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
# Case 9b: cross-client close during transport run => exit 0 (post-exit
# closing-row check fires before session-state)
# ---------------------------------------------------------------------------
print ""
print "case 9b: closing-row during run => exit 0 (post-exit check)"
# row=present at startup, transport exits 255, row=closing after run => exit 0
_rc=$(_run_case survived 255 0 0 0 1 0 1)
_a=$(_attempts)
(( _a == 1 )) && _ok "1 transport run (exited via post-exit closing-row)" || _bad "expected 1 call, got $_a"
(( _rc == 0 )) && _ok "exit 0 (post-exit closing-row)" || _bad "expected exit 0, got $_rc"

# ---------------------------------------------------------------------------
# Case 10: trap during sleep + owner alive => reconnect (not exit)
# A trap during the backoff sleep (e.g. SIGHUP from a dying ssh child on a
# network drop) sets the close flag, which shortens the sleep, but the loop
# must still reconnect because the owner is alive. Bounded by max_attempts.
# ---------------------------------------------------------------------------
print ""
print "case 10: trap during sleep + owner alive => reconnect"
# run(1) exits 255 + survived => reconnect => sleep sends HUP (flag set) =>
# sleep returns early => top-of-loop owner-alive check passes => run(2) =>
# max reached => exit.
_rc=$(_run_case survived 255 2 0 1)
_a=$(_attempts)
(( _a == 2 )) && _ok "reconnected after trap during sleep (2 calls)" || _bad "expected 2 calls, got $_a"
(( _rc == 255 )) && _ok "exit code preserved (255)" || _bad "expected exit 255, got $_rc"

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

# ---------------------------------------------------------------------------
# Session-state parse tests: feed real tab-delimited zmx list output through
# the un-stubbed _gzmx_session_state. A separate worker stubs _add_argv (the
# transport argv) to emit the fixture string instead of running ssh.
# ---------------------------------------------------------------------------
print ""
print "session-state parse: tab-delimited zmx list output"

_state_worker="$workdir/state-worker.zsh"
cat > "$_state_worker" <<'STATEWORKER'
export HOME="$GZMX_WORKDIR/home"
export GHOSTTY_ZMX_DATA_HOME="$GZMX_WORKDIR/data"
export GHOSTTY_ZMX_STATE_HOME="$GZMX_WORKDIR/state"
export GHOSTTY_ZMX_DEBUG=0
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME"
typeset _GZMX_PROJECTION_LOOP_NO_AUTO_RUN=1
host="test-host"; session="gzr-test-1-1-1-1"
source "$GZMX_REPO_DIR/cli/projection-loop"
_gzmx_wdebug() { :; }
# Stub the transport argv: a script that emits the fixture zmx list output
# (and returns the simulated ssh rc) instead of running real ssh.
_emit="$GZMX_WORKDIR/emit-list"
cat > "$_emit" <<'EMIT'
print -r -- "$GZMX_TEST_ZMX_LIST"
return "${GZMX_TEST_SSH_RC:-0}"
EMIT
chmod +x "$_emit" 2>/dev/null || true
typeset -ga _add_argv; _add_argv=(zsh "$_emit")
typeset -ga _gzmx_side_argv; _gzmx_side_argv=(zsh "$_emit")
_gzmx_session_state "$host" "$session" "zmx"
STATEWORKER

_run_state() {
  local zmx_list="$1" ssh_rc="${2:-0}"
  GZMX_REPO_DIR="$repo_dir" GZMX_WORKDIR="$workdir" \
  GZMX_TEST_ZMX_LIST="$zmx_list" \
  GZMX_TEST_SSH_RC="$ssh_rc" \
  zsh "$_state_worker" 2>/dev/null
}

# clients=0 => survived (network drop, session alive)
_s=$(_run_state $'name=gzr-test-1-1-1-1\tpid=123\tclients=0\tcreated=1\tstart_dir=/h')
[[ "$_s" == "survived" ]] && _ok "clients=0 => survived" || _bad "expected survived, got $_s"

# clients=1 => live (spurious duplicate)
_s=$(_run_state $'name=gzr-test-1-1-1-1\tpid=123\tclients=1\tcreated=1\tstart_dir=/h')
[[ "$_s" == "live" ]] && _ok "clients=1 => live" || _bad "expected live, got $_s"

# session missing => gone
_s=$(_run_state $'name=gzr-other\tpid=456\tclients=0\tcreated=1\tstart_dir=/h')
[[ "$_s" == "gone" ]] && _ok "session missing => gone" || _bad "expected gone, got $_s"

# active-session marker prefix (→) is stripped before matching
_s=$(_run_state $'\u2192 name=gzr-test-1-1-1-1\tpid=123\tclients=0\tcreated=1\tstart_dir=/h')
[[ "$_s" == "survived" ]] && _ok "active-session marker (→) stripped" || _bad "expected survived with → prefix, got $_s"

# start_dir containing 'clients=' does not skew the parse (column-based)
_s=$(_run_state $'name=gzr-test-1-1-1-1\tpid=123\tclients=0\tcreated=1\tstart_dir=/home/user/clients=foo')
[[ "$_s" == "survived" ]] && _ok "start_dir with clients= does not skew parse" || _bad "expected survived, got $_s"

# ssh round-trip failed (non-zero rc) => unknown (don't clobber a live session)
_s=$(_run_state "" 1)
[[ "$_s" == "unknown" ]] && _ok "ssh failed (rc=1) => unknown" || _bad "expected unknown, got $_s"

# ssh succeeded but empty output => unknown
_s=$(_run_state "" 0)
[[ "$_s" == "unknown" ]] && _ok "ssh ok but empty output => unknown" || _bad "expected unknown, got $_s"

# ---------------------------------------------------------------------------
# Interruptible sleep: _gzmx_interruptible_sleep exits early when the close
# flag is set mid-sleep (a trap fired). Verify it returns before the full
# duration when _gzmx_closing is flipped during the sleep.
# ---------------------------------------------------------------------------
print ""
print "interruptible sleep: exits early on close flag"
_sleep_worker="$workdir/sleep-worker.zsh"
cat > "$_sleep_worker" <<'SLEEPWORKER'
export HOME="$GZMX_WORKDIR/home"
export GHOSTTY_ZMX_DATA_HOME="$GZMX_WORKDIR/data"
export GHOSTTY_ZMX_STATE_HOME="$GZMX_WORKDIR/state"
zmodload zsh/datetime
typeset _GZMX_PROJECTION_LOOP_NO_AUTO_RUN=1
source "$GZMX_REPO_DIR/cli/projection-loop"
typeset -g _gzmx_closing=0
# Send HUP to ourselves after 0.3s — the trap sets _gzmx_closing=1.
trap '_gzmx_closing=1' HUP
( sleep 0.3; kill -HUP $$ ) &
_start=$EPOCHREALTIME
_gzmx_interruptible_sleep 5
_end=$EPOCHREALTIME
print -r -- "$(( _end - _start ))" > "$GZMX_WORKDIR/sleep_elapsed"
SLEEPWORKER

GZMX_REPO_DIR="$repo_dir" GZMX_WORKDIR="$workdir" zsh "$_sleep_worker" 2>/dev/null
_elapsed=$(cat "$workdir/sleep_elapsed" 2>/dev/null || echo 0)
# Should be ~0.3s (flag flip), not ~5s (full sleep). Allow up to 1.5s margin
# for CI scheduling.
(( _elapsed < 1.5 )) && _ok "sleep exited early (${_elapsed}s, not 5s)" || _bad "sleep took ${_elapsed}s (expected < 1.5s)"

# ---------------------------------------------------------------------------
# Kill switch (GHOSTTY_ZMX_RECONNECT=0): the cold-start-only path runs the
# reboot-restore check once, then execs the transport. Verifies the kill
# switch preserves the reboot-restore step that existed before the loop was
# introduced (design locked decision #8).
# ---------------------------------------------------------------------------
print ""
print "kill switch: reboot-restore runs before exec when loop is disabled"
_kill_worker="$workdir/kill-worker.zsh"
cat > "$_kill_worker" <<'KILLWORKER'
export HOME="$GZMX_WORKDIR/home"
export GHOSTTY_ZMX_DATA_HOME="$GZMX_WORKDIR/data"
export GHOSTTY_ZMX_STATE_HOME="$GZMX_WORKDIR/state"
export GHOSTTY_ZMX_DEBUG=0
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME"
# Stub the transport argv: a script that writes a marker when called (proving
# the reboot-restore check ran its side-channel ssh) and exits 0 so the
# check reports "session exists" and skips injection.
_marker="$GZMX_WORKDIR/side_channel_ran"
cat > "$GZMX_WORKDIR/side-channel-stub" <<'STUB'
print -r -- "ran" > "$GZMX_SIDE_MARKER"
exit 0
STUB
chmod +x "$GZMX_WORKDIR/side-channel-stub" 2>/dev/null || true
typeset -ga _add_argv; _add_argv=(zsh "$GZMX_WORKDIR/side-channel-stub")
typeset _remote_zmx="zmx"
host="test-host"; session="gzr-test-1-1-1-1"
# Create a scrollback snapshot so _gzmx_reboot_restore_check proceeds past
# its `[[ -s "$hist_file" ]] || return 0` guard and runs the side-channel
# ssh check (which our stub captures).
_hist_dir="$GHOSTTY_ZMX_STATE_HOME/history/$host"
mkdir -p "$_hist_dir"
print -r -- "saved scrollback line" > "$_hist_dir/${session}.txt"
# The transport: a script that exits 42 so we can confirm exec ran it.
_transport="$GZMX_WORKDIR/transport"
cat > "$_transport" <<'TRANSPORT'
exit 42
TRANSPORT
chmod +x "$_transport" 2>/dev/null || true
typeset _GZMX_PROJECTION_COLD_START_ONLY=1
# Capture the transport argv so the auto-run can exec it.
set -- "$_transport"
source "$GZMX_REPO_DIR/cli/projection-loop"
KILLWORKER

rm -f "$workdir/reboot_ran" "$workdir/side_channel_ran"
GZMX_REPO_DIR="$repo_dir" GZMX_WORKDIR="$workdir" \
  GZMX_SIDE_MARKER="$workdir/side_channel_ran" \
  script -q /dev/null zsh "$_kill_worker" >/dev/null 2>&1
_krc=$?
_rb=$(cat "$workdir/side_channel_ran" 2>/dev/null || echo "")
[[ "$_rb" == "ran" ]] && _ok "reboot-restore ran before exec" || _bad "reboot-restore did not run (got '$_rb')"
(( _krc == 42 )) && _ok "transport exec'd (exit 42)" || _bad "expected exec to run transport (exit 42), got $_krc"

print ""
if [[ "$fail" -eq 0 ]]; then
  print "all projection-loop tests passed ($pass/$pass)"
  exit 0
else
  print -u2 "$fail test(s) failed"
  exit 1
fi
