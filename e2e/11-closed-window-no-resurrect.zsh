#!/bin/zsh
# E2E 11 — a closed projection window must NOT resurrect after Cmd-Q + reopen.
#
# Regression coverage for the close-then-Cmd-Q resurrection race (a known
# v0.1 focus-identity bug; v0.2's tty-based identity should fix it). Scenario:
#   1. Open a projection to the fixture (window 2).
#   2. Close the projection window via Cmd+W (intentional close).
#      The close transaction runs: server row present -> closing -> zmx kill
#      -> deleted; the local projection row is removed; window count -> 1.
#   3. Gracefully quit Ghostty (osascript `quit` = Cmd-Q path).
#   4. Relaunch Ghostty (fresh process).
#   5. Assert the closed projection does NOT reopen:
#        - window count stays 1 (only the local pane)
#        - remote zmx session stays dead
#        - server layout row stays `deleted` (not resurrected to `present`)
#        - local projection row stays absent
#   6. As a positive control, open a FRESH projection and verify it works —
#      proving the poller/restore is healthy and the no-resurrect result is
#      specific to the closed session, not a broken harness.
#
# This complements scenario 07 (Cmd-Q PRESERVES a live session for reopen)
# and scenario 05 (close runs the close transaction) by covering the
# combination: a session that was intentionally closed must stay closed
# across a Cmd-Q + reopen cycle.
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

# Capture the session name (the one we are about to close).
GZMX_E2E_SESSION="$(awk -F '\t' '/name=gzr-/ {sub(/.*name=gzr-/, "gzr-"); sub(/[ \t].*/, ""); print; exit}' \
  <(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$(gzmx_e2e_fixture_zmx) list 2>/dev/null" 2>/dev/null))"
[[ -n "$GZMX_E2E_SESSION" ]] || gzmx_e2e_fail "could not read session name"
gzmx_e2e_log "session=$GZMX_E2E_SESSION (about to close)"

# 2. Close the projection window (window 2) via Cmd+W.
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

# Wait for the close transaction to finish (session killed, row deleted).
zmx_bin="$(gzmx_e2e_fixture_zmx)"
_session_gone() {
  local out
  out="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list 2>/dev/null" 2>/dev/null)"
  [[ "$out" != *"$GZMX_E2E_SESSION"* ]]
}
gzmx_e2e_wait_for 30 _session_gone || gzmx_e2e_fail "remote session $GZMX_E2E_SESSION still alive after close"
gzmx_e2e_pass "close transaction killed the remote session"

_row_deleted() {
  [[ "$(gzmx_e2e_remote_layout_row "$GZMX_E2E_SESSION")" == *"deleted"* ]]
}
gzmx_e2e_wait_for 10 _row_deleted || gzmx_e2e_fail "server row not deleted after close"
gzmx_e2e_pass "server layout row is 'deleted' after close"

gzmx_e2e_assert_window_count 1
gzmx_e2e_pass "projection window closed (window count back to 1)"

# 3. Gracefully quit Ghostty (Cmd-Q path), same as scenario 07.
gzmx_e2e_log "quitting Ghostty gracefully (Cmd-Q path)..."
osascript -e "tell application \"$GZMX_E2E_GHOSTTY_APP\" to quit" 2>/dev/null
i=1
for (( i=1; i<=40; i++ )); do
  kill -0 "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || break
  sleep 0.5
done
kill -9 "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || true
pkill -9 -f "ghostty-zmx-501/(reaper|remote-poller)-${GZMX_E2E_GHOSTTY_PID}" 2>/dev/null || true
GZMX_E2E_STARTED_GHOSTTY=0
sleep 2
gzmx_e2e_log "Ghostty quit complete"

# 4. Relaunch Ghostty (fresh process). The poller/restore runs.
GZMX_E2E_STARTED_GHOSTTY=0
gzmx_e2e_ghostty_launch
gzmx_e2e_log "Ghostty relaunched pid=$GZMX_E2E_GHOSTTY_PID"

# Give the poller a few cycles to (correctly) NOT re-project the deleted row.
# The poller reads server state; a `deleted` row must not be projected. If the
# close-then-Cmd-Q resurrection race regressed, the poller would re-open a
# projection for the closed session here.
sleep 5

# 5. Assert the closed projection did NOT resurrect.
gzmx_e2e_assert_window_count 1
gzmx_e2e_pass "closed projection did NOT resurrect after Cmd-Q + reopen (window count still 1)"

# The remote session must still be dead.
_resurrected() {
  local out
  out="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list 2>/dev/null" 2>/dev/null)"
  [[ "$out" == *"$GZMX_E2E_SESSION"* ]]
}
if gzmx_e2e_wait_for 3 _resurrected 2>/dev/null; then
  gzmx_e2e_fail "closed session $GZMX_E2E_SESSION resurrected on the remote after reopen"
fi
gzmx_e2e_pass "remote session stays dead after reopen"

# The server row must still be `deleted` (not resurrected to `present`).
_row_state_now="$(gzmx_e2e_remote_layout_row "$GZMX_E2E_SESSION")"
[[ "$_row_state_now" == *"deleted"* || -z "$_row_state_now" ]] \
  || gzmx_e2e_fail "server row resurrected to non-deleted state: $_row_state_now"
gzmx_e2e_pass "server layout row stays deleted/absent after reopen"

# The local projection row must still be absent.
_local_row="$(awk -F '\t' -v s="$GZMX_E2E_SESSION" '$3 == s' "$GZMX_E2E_DATA_HOME/remote-projections" 2>/dev/null)"
[[ -z "$_local_row" ]] || gzmx_e2e_fail "local projection row resurrected: $_local_row"
gzmx_e2e_pass "local projection row stays absent after reopen"

# 6. Positive control: a fresh projection still works (proves the harness and
# poller are healthy — the no-resurrect above is specific to the closed session).
gzmx_e2e_type "ssh -F $GZMX_E2E_SSHCONFIG $GZMX_E2E_FIXTURE_HOST"
gzmx_e2e_wait_remote_clients 1 20
gzmx_e2e_assert_window_count 2
GZMX_E2E_SESSION2="$(awk -F '\t' '/name=gzr-/ {sub(/.*name=gzr-/, "gzr-"); sub(/[ \t].*/, ""); print; exit}' \
  <(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list 2>/dev/null" 2>/dev/null))"
[[ -n "$GZMX_E2E_SESSION2" && "$GZMX_E2E_SESSION2" != "$GZMX_E2E_SESSION" ]] \
  || gzmx_e2e_fail "fresh projection did not create a new session (got: ${GZMX_E2E_SESSION2:-none})"
gzmx_e2e_pass "positive control: fresh projection opens a new session ($GZMX_E2E_SESSION2)"

gzmx_e2e_pass "scenario 11 (closed window does not resurrect after Cmd-Q + reopen) complete"
