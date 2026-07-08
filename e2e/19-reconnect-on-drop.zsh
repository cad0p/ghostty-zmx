#!/bin/zsh
# E2E 19 — Reconnect on network drop.
#
# When the ssh client process for a remote projection pane is killed (network
# drop), the reconnect loop in cli/projection-loop must reattach to the
# surviving remote zmx session (clients=0 -> clients=1) with the same session
# name and intact scrollback, instead of leaving the pane at Ghostty's
# 'Press any key to close' prompt.
#
# Scenario:
#   1. Open a projection to the fixture. Verify clients=1, 2 windows.
#   2. Inject a unique marker into the remote scrollback (via zmx send).
#   3. Kill the ssh client process (pkill -f "ssh.*<session>") to simulate a
#      network drop.
#   4. Assert the pane reconnects within backoff: window count stays 2,
#      clients=1 again, same session name.
#   5. Assert the marker is still in the scrollback.
#
# The harness sets GHOSTTY_ZMX_RECONNECT_MAX_ATTEMPTS=3 (bounded) so the loop
# exits if the fixture is down (prevents CI hangs).
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state
gzmx_e2e_ghostty_launch

# 1. Open a projection to the fixture.
sleep 2
gzmx_e2e_type "ssh -F $GZMX_E2E_SSHCONFIG $GZMX_E2E_FIXTURE_HOST"
gzmx_e2e_wait_remote_clients 1 20
gzmx_e2e_assert_window_count 2

# Capture the session name (used to identify the ssh process to kill + assert
# the same session reattaches).
zmx_bin="$(gzmx_e2e_fixture_zmx)"
GZMX_E2E_SESSION="$(awk -F '\t' '/name=gzr-/ {sub(/.*name=gzr-/, "gzr-"); sub(/[ \t].*/, ""); print; exit}' \
  <(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list 2>/dev/null" 2>/dev/null))"
[[ -n "$GZMX_E2E_SESSION" ]] || gzmx_e2e_fail "could not read session name"
gzmx_e2e_log "session=$GZMX_E2E_SESSION"

# 2. Inject a unique marker into the remote scrollback via zmx send (reliable,
#    bypasses ssh-transport timing issues of typing into the projection).
MARKER="GZMX_E2E_RECONNECT_$$"
ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin send $GZMX_E2E_SESSION 'echo $MARKER'" 2>/dev/null
sleep 1
ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin send $GZMX_E2E_SESSION $'\r'" 2>/dev/null
sleep 1
gzmx_e2e_assert_remote_history_contains "$GZMX_E2E_SESSION" "$MARKER"
gzmx_e2e_pass "marker injected into remote scrollback before drop"

# 3. Simulate a network drop: kill the ssh client process attached to the
#    session. The projection wrapper's ssh runs with 'zmx attach <session>' in
#    its args, so pkill -f "ssh.*<session>" targets it. The reconnect loop
#    sees the ssh exit (255), checks the session state (survived, clients=0),
#    and reattaches within backoff.
gzmx_e2e_log "simulating network drop (killing ssh client for $GZMX_E2E_SESSION)..."
# Avoid matching our own harness ssh calls: match the attach command shape.
pkill -f "ssh.*zmx attach $GZMX_E2E_SESSION" 2>/dev/null || \
  pkill -f "ssh.*$GZMX_E2E_SESSION" 2>/dev/null || true

# 4. Assert the pane reconnects within backoff: window count stays 2 (the pane
#    did not close), clients returns to 1 (reattached), same session name.
gzmx_e2e_log "waiting for reconnect (up to 30s)..."
gzmx_e2e_wait_remote_clients 1 30
gzmx_e2e_assert_window_count 2

# Verify the reattached session has the SAME name (reattach, not a fresh one).
_reattached_session="$(awk -F '\t' '/name=gzr-/ {sub(/.*name=gzr-/, "gzr-"); sub(/[ \t].*/, ""); print; exit}' \
  <(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list 2>/dev/null" 2>/dev/null))"
[[ "$_reattached_session" == "$GZMX_E2E_SESSION" ]] \
  || gzmx_e2e_fail "reattached to a different session: expected $GZMX_E2E_SESSION, got $_reattached_session"
gzmx_e2e_pass "reattached to same session name ($_reattached_session)"

# 5. Assert the marker is still in the scrollback after reconnect.
gzmx_e2e_assert_remote_history_contains "$GZMX_E2E_SESSION" "$MARKER"
gzmx_e2e_pass "scrollback intact after reconnect"

# Verify the loop logged the reconnect (best-effort; the debug log line is
# not asserted as release-critical).
grep -q "projection: reconnecting" "$GZMX_E2E_STATE_HOME/debug.log" 2>/dev/null \
  && gzmx_e2e_pass "wrapper logged reconnect attempt" \
  || gzmx_e2e_warn "reconnect log line not found (best-effort)"

gzmx_e2e_pass "scenario 19 (reconnect on network drop) complete"
