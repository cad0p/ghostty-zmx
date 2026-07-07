#!/bin/zsh
# E2E 06 — unmanaged remote zmx sessions are not reaped by the poller/reaper.
#
# Safety invariant: ghostty-zmx must only manage sessions it created (gzr-*).
# An unmanaged session (any other name) on the same remote host must survive
# ghostty-zmx activity (poller cycles, pane close, Cmd-Q). This prevents the
# tool from clobbering a user's manually-created zmx sessions.
#
# Scenario:
#   1. Create an unmanaged zmx session on the fixture (`zmx run unmanaged-test true`).
#   2. Open a managed projection (ssh handoff) — poller starts.
#   3. Close the managed projection (close transaction).
#   4. Verify the unmanaged session is still alive.
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state
gzmx_e2e_ghostty_launch

# Create an unmanaged session on the fixture before any managed activity.
UNMANAGED="unmanaged-e2e-$$"
zmx_bin="$(gzmx_e2e_fixture_zmx)"
ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin run $UNMANAGED true 2>/dev/null" 2>/dev/null \
  || gzmx_e2e_fail "could not create unmanaged session $UNMANAGED"
gzmx_e2e_log "created unmanaged session: $UNMANAGED"

# Open a managed projection — starts the poller, which scans the remote layout.
sleep 2
gzmx_e2e_type "ssh -F $GZMX_E2E_SSHCONFIG $GZMX_E2E_FIXTURE_HOST"
gzmx_e2e_wait_remote_clients 1 20
gzmx_e2e_assert_window_count 2

# Let the poller run a few cycles so it would have a chance to clobber the
# unmanaged session if the bug existed.
gzmx_e2e_log "letting poller run for 5s..."
sleep 5

# Verify the unmanaged session survived the poller activity.
_unmanaged_alive() {
  local out
  out="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list 2>/dev/null" 2>/dev/null)"
  [[ "$out" == *"$UNMANAGED"* ]]
}
gzmx_e2e_wait_for 10 _unmanaged_alive || gzmx_e2e_fail "unmanaged session $UNMANAGED was reaped by poller"
gzmx_e2e_pass "unmanaged session survived poller activity"

# Close the managed projection (close transaction).
gzmx_e2e_activate_window 2
sleep 1
osascript <<OSA 2>/dev/null || true
tell application "$GZMX_E2E_GHOSTTY_APP"
  set w to item 2 of windows
  activate window w
end tell
tell application "System Events"
  keystroke "w" using command down
end tell
OSA
gzmx_e2e_log "closed projection window; waiting for close transaction..."
sleep 8

# Verify the unmanaged session is STILL alive after the close transaction.
_unmanaged_alive || gzmx_e2e_fail "unmanaged session $UNMANAGED was killed during close transaction"
gzmx_e2e_pass "unmanaged session survived close transaction"

# Cleanup the unmanaged session so it doesn't leak across runs.
ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin kill $UNMANAGED 2>/dev/null" 2>/dev/null || true

gzmx_e2e_pass "scenario 06 (unmanaged sessions not reaped) complete"
