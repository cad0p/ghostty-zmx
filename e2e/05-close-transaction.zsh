#!/bin/zsh
# E2E 05 — closing a projection pane runs the remote close transaction.
#
# Closing the projection window (Ghostty pane close) must:
#   - transition the server remote-layout row to `deleted`
#   - kill the remote zmx session (clients=0, session gone)
#   - remove the local projection row
#
# This is release-critical: a leaked remote session after pane close is a
# resource leak and breaks the "pane close == session kill" contract.
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state
gzmx_e2e_ghostty_launch

# Open a projection.
sleep 2
gzmx_e2e_type "ssh -F $GZMX_E2E_SSHCONFIG $GZMX_E2E_FIXTURE_HOST"
gzmx_e2e_wait_remote_clients 1 20
gzmx_e2e_assert_window_count 2

# Record the session name for later assertions.
GZMX_E2E_SESSION="$(awk -F '\t' '/name=gzr-/ {sub(/.*name=gzr-/, "gzr-"); sub(/[ \t].*/, ""); print; exit}' \
  <(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$(gzmx_e2e_fixture_zmx) list 2>/dev/null" 2>/dev/null))"
[[ -n "$GZMX_E2E_SESSION" ]] || gzmx_e2e_fail "could not read session name"
gzmx_e2e_log "session=$GZMX_E2E_SESSION"

# Close the projection window (window 2) via Cmd+W sent to it.
# Activate the projection window first, then send Cmd+W.
gzmx_e2e_activate_window 2
sleep 1
# Cmd+W closes the focused surface. With confirm-close-surface=false (harness),
# a single-surface window closes immediately.
osascript <<OSA 2>/dev/null || true
tell application "$GZMX_E2E_GHOSTTY_APP"
  set w to item 2 of windows
  activate window w
end tell
tell application "System Events"
  keystroke "w" using command down
end tell
OSA

# Wait for the remote session to be killed (close transaction over ssh).
# The reaper runs the close-txn: present -> closing -> zmx kill -> deleted.
gzmx_e2e_log "waiting for close transaction (up to 30s)..."
_session_gone() {
  local out
  out="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$(gzmx_e2e_fixture_zmx) list 2>/dev/null" 2>/dev/null)"
  [[ "$out" != *"$GZMX_E2E_SESSION"* ]]
}
gzmx_e2e_wait_for 30 _session_gone || gzmx_e2e_fail "remote session $GZMX_E2E_SESSION still alive after close"

# Assert the server layout row is `deleted` (tombstone, kept 1h for compaction).
_row_state() {
  local row
  row="$(gzmx_e2e_remote_layout_row "$GZMX_E2E_SESSION")"
  [[ "$row" == *"deleted"* ]]
}
gzmx_e2e_wait_for 10 _row_state || gzmx_e2e_fail "server row not deleted after close (row=$(gzmx_e2e_remote_layout_row "$GZMX_E2E_SESSION"))"
gzmx_e2e_pass "server layout row is 'deleted' after close"

# Assert the local projection row is gone.
_local_row_gone() {
  [[ -z "$(awk -F '\t' -v s="$GZMX_E2E_SESSION" '$3 == s' "$GZMX_E2E_DATA_HOME/remote-projections" 2>/dev/null)" ]]
}
gzmx_e2e_wait_for 10 _local_row_gone || gzmx_e2e_fail "local projection row still present after close"

# Window count should drop back to 1 (just the local pane).
gzmx_e2e_assert_window_count 1

gzmx_e2e_pass "scenario 05 (close transaction) complete"
