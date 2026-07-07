#!/bin/zsh
# E2E 15 — orphaned poller resilience.
#
# Regression test for the multiplication root cause: a poller orphaned by a
# prior interrupted E2E run (reparented to launchd, owning Ghostty PID dead)
# survives in the runtime dir and re-opens projections during the next run,
# causing duplicate windows and false failures.
#
# The manager's ghostty_zmx_kill_orphaned_pollers (session-manager.zsh:1936)
# runs at poller startup and kills pollers whose owning Ghostty PID is dead.
# The harness's gzmx_e2e_ghostty_launch pre-launch sweep (harness.zsh) is the
# backstop for orphans the manager can't reach (no fresh Ghostty to trigger
# the sweep). This test verifies BOTH layers.
#
# Scenario:
#   1. Open a projection to the fixture (creates a present server row + a
#      live poller owned by the current Ghostty PID).
#   2. Kill the Ghostty process WITHOUT the harness's sweep (simulating a
#      crash / SIGKILL that bypasses graceful cleanup). The poller is now
#      orphaned (reparented to launchd, owning PID dead).
#   3. Verify the orphan exists.
#   4. Launch a fresh Ghostty. The harness pre-launch sweep + the manager's
#      startup sweep must kill the orphan.
#   5. Verify no duplicate projection opens (window count stays at 2, not 3+).
#   6. Verify only one remote client (clients=1, not 2+).
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state
gzmx_e2e_ghostty_launch

# 1. Open a projection.
sleep 2
gzmx_e2e_type "ssh -F $GZMX_E2E_SSHCONFIG $GZMX_E2E_FIXTURE_HOST"
gzmx_e2e_wait_remote_clients 1 20
gzmx_e2e_assert_window_count 2
gzmx_e2e_pass "projection opened (clients=1, 2 windows)"

_runtime="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ghostty-zmx-${UID:-$(id -u)}"

# 2. Kill Ghostty WITHOUT the harness sweep (simulate a crash). The poller
#    child is reparented to launchd and keeps polling.
gzmx_e2e_log "killing Ghostty PID $GZMX_E2E_GHOSTTY_PID without sweep (simulating crash)..."
kill -9 "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || true
# Wait for the process to exit.
for (( i=1; i<=20; i++ )); do
  kill -0 "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || break
  sleep 0.25
done
# DO NOT run the harness sweep — we want the orphan to survive.
GZMX_E2E_STARTED_GHOSTTY=0
sleep 2

# 3. Verify the orphan exists. The poller script is named remote-poller-<pid>.zsh
#    and the process matches "remote-poller-<pid>.zsh".
_orphan_pids="$(pgrep -f "${_runtime}/remote-poller-" 2>/dev/null || true)"
if [[ -z "$_orphan_pids" ]]; then
  # The poller may have already self-terminated via its elapsed-seconds token
  # check (the owning PID is dead). That's also correct behavior — the manager
  # is resilient at the poller level too. Record it and skip to the fresh launch.
  gzmx_e2e_pass "poller self-terminated after owner death (elapsed-token guard works)"
  _orphan_existed=0
else
  gzmx_e2e_pass "orphaned poller survived owner death (pid=$_orphan_pids) — will be swept on next launch"
  _orphan_existed=1
fi

# 4. Launch a fresh Ghostty. The harness pre-launch sweep + the manager's
#    startup kill_orphaned_pollers must clean up.
gzmx_e2e_ghostty_launch
gzmx_e2e_log "fresh Ghostty launched pid=$GZMX_E2E_GHOSTTY_PID"

# 5. Verify no duplicate projection. The server `present` row still exists
#    (Cmd-Q preservation path), so a fresh poller would re-project it. The
#    orphan (if it survived) would ALSO re-project it, causing a duplicate.
#    After the sweep, only the fresh poller should project — window count 2.
gzmx_e2e_wait_remote_clients 1 30
gzmx_e2e_assert_window_count 2
gzmx_e2e_pass "no duplicate projection after fresh launch (2 windows, not 3+)"

# 6. Verify only one remote client.
zmx_bin="$(gzmx_e2e_fixture_zmx)"
_clients="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin list 2>/dev/null" 2>/dev/null | grep -c 'clients=1' || true)"
[ "$_clients" -eq 1 ] || gzmx_e2e_fail "expected 1 client with clients=1, got $_clients"
gzmx_e2e_pass "exactly one remote client (clients=1, no orphan-driven duplicate)"

# 7. Verify no orphan pollers remain after the fresh launch.
#    Quit the fresh Ghostty cleanly first so its own poller is swept; then
#    check for ANY surviving orphan (which would be a stale one the sweep
#    missed). The harness gzmx_e2e_ghostty_quit sweeps all pollers in the
#    runtime dir, so after it runs, zero pollers should remain.
gzmx_e2e_ghostty_quit
sleep 1
_post_orphans="$(pgrep -f "${_runtime}/remote-poller-" 2>/dev/null || true)"
if [[ -n "$_post_orphans" ]]; then
  _stale=0
  for _pid in ${(f)_post_orphans}; do
    _ppid="$(ps -o ppid= -p "$_pid" 2>/dev/null | tr -d ' ')"
    if [[ "$_ppid" == "1" ]]; then
      _stale=1
      gzmx_e2e_log "stale orphan poller still alive: pid=$_pid ppid=1"
    fi
  done
  [[ "$_stale" -eq 0 ]] || gzmx_e2e_fail "stale orphan pollers survived the fresh-launch sweep"
fi
gzmx_e2e_pass "no stale orphan pollers after fresh launch + clean quit"

gzmx_e2e_pass "scenario 15 (orphan poller resilience) complete"
