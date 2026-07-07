#!/bin/zsh
# E2E 17 — tsh transport: Cmd-Q preserves the remote session AND the server
# remote-layout row, so reopen re-projects.
#
# Regression for the tsh-specific restore-after-Cmd-Q bug. e2e/07 and e2e/14
# cover the Cmd-Q+reopen path but use plain `ssh -F` against the Docker
# fixture. The tsh path was not covered end-to-end for restore. The wrapper's
# remote-layout `add` call builds a no-pty transport argv; for tsh it MUST NOT
# append `-T` (tsh does not support OpenSSH's -T). A bug in the wrapper's
# _is_tsh detection (comparing argv[1] to bare "tsh" instead of stripping the
# path) caused -T to be appended to `tsh ssh`, the `add` failed silently, the
# server remote-layout row was never written, and Cmd-Q+reopen found nothing
# to re-project — the remote window was lost despite the remote session
# surviving. This scenario reproduces that failure mode.
#
# Scenario:
#   1. Use the mock-tsh fixture (delegates to the sshd fixture).
#   2. Open a projection via `tsh ssh <fixture-host>`.
#   3. Assert the SERVER remote-layout has a `present` row for the session.
#      (This is the assertion that fails when the wrapper's `add` is broken:
#       the projection window opens and attaches, but no server row is written.)
#   4. Cmd-Q Ghostty (osascript quit = preservation path).
#   5. Assert the remote session survived (clients=0, alive).
#   6. Assert the server remote-layout row is STILL `present` (not deleted).
#   7. Relaunch Ghostty; assert the projection reopens and reattaches to the
#      SAME session (not a new one).
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state
gzmx_e2e_use_mock_tsh
gzmx_e2e_ghostty_launch

# Wait for the local shell to be ready, then type the tsh command.
sleep 2
gzmx_e2e_type "tsh ssh $GZMX_E2E_FIXTURE_HOST"
gzmx_e2e_wait_remote_clients 1 20
gzmx_e2e_assert_window_count 2   # local + projection

# Capture the session name.
GZMX_E2E_SESSION="$(awk -F '\t' '/name=gzr-/ {sub(/.*name=gzr-/, "gzr-"); sub(/[ \t].*/, ""); print; exit}' \
  <(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$(gzmx_e2e_fixture_zmx) list 2>/dev/null" 2>/dev/null))"
[[ -n "$GZMX_E2E_SESSION" ]] || gzmx_e2e_fail "could not read session name"
gzmx_e2e_log "session=$GZMX_E2E_SESSION"

# --- THE KEY ASSERTION: server remote-layout must have a present row --------
# The wrapper writes this row via `ghostty-zmx-remote-layout add ... present`
# over the (no-pty) transport. For tsh, a bug in _is_tsh detection appended -T
# to the tsh command, the add failed silently, and no row was written — so
# Cmd-Q+reopen found nothing to re-project. Asserting the row exists here
# catches that regression at the point of failure (before the Cmd-Q cycle).
_server_row_has_present() {
  local row
  row="$(gzmx_e2e_remote_layout_row "$GZMX_E2E_SESSION")"
  [[ "$row" == *"present"* ]]
}
gzmx_e2e_wait_for 10 _server_row_has_present || {
  print -u2 "  server remote-layout row for $GZMX_E2E_SESSION:"
  ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    '~/.config/ghostty-zmx/ghostty-zmx-remote-layout read' >&2 2>/dev/null || true
  gzmx_e2e_fail "server remote-layout has no present row for $GZMX_E2E_SESSION (wrapper add failed)"
}
gzmx_e2e_pass "server remote-layout row is 'present' after tsh handoff"

# Gracefully quit Ghostty via osascript `quit` (Cmd-Q path, not kill).
gzmx_e2e_log "quitting Ghostty gracefully (Cmd-Q path)..."
osascript -e "tell application \"$GZMX_E2E_GHOSTTY_APP\" to quit" 2>/dev/null
i=1
for (( i=1; i<=40; i++ )); do
  kill -0 "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || break
  sleep 0.5
done
kill -9 "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || true
_runtime="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ghostty-zmx-${UID:-$(id -u)}"
[[ -d "$_runtime" ]] && pkill -9 -f "${_runtime}/(reaper|remote-poller)-" 2>/dev/null || true
GZMX_E2E_STARTED_GHOSTTY=0
sleep 2
gzmx_e2e_log "Ghostty quit complete"

# Verify the remote session survived (clients may be 0 now, but session alive).
zmx_bin="$(gzmx_e2e_fixture_zmx)"
_remote_session_alive() {
  local out
  out="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list 2>/dev/null" 2>/dev/null)"
  [[ "$out" == *"$GZMX_E2E_SESSION"* ]]
}
gzmx_e2e_wait_for 15 _remote_session_alive || gzmx_e2e_fail "remote session $GZMX_E2E_SESSION did not survive Cmd-Q"
gzmx_e2e_pass "remote session survived Cmd-Q"

# Verify the server layout row is still `present` (not deleted by the poller).
_row="$(gzmx_e2e_remote_layout_row "$GZMX_E2E_SESSION")"
[[ "$_row" == *"present"* ]] || gzmx_e2e_fail "server row not present after Cmd-Q (row=$_row)"
gzmx_e2e_pass "server layout row is 'present' after Cmd-Q"

# Relaunch Ghostty (fresh process). The poller should re-project the session.
GZMX_E2E_STARTED_GHOSTTY=0
gzmx_e2e_ghostty_launch
gzmx_e2e_log "Ghostty relaunched pid=$GZMX_E2E_GHOSTTY_PID"

# Wait for the poller to re-project the surviving session.
gzmx_e2e_wait_remote_clients 1 30
gzmx_e2e_assert_window_count 2

# Verify it reattached to the SAME session (not a new one).
GZMX_E2E_SESSION2="$(awk -F '\t' '/name=gzr-/ {sub(/.*name=gzr-/, "gzr-"); sub(/[ \t].*/, ""); print; exit}' \
  <(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list 2>/dev/null" 2>/dev/null))"
[[ "$GZMX_E2E_SESSION2" == "$GZMX_E2E_SESSION" ]] \
  || gzmx_e2e_fail "reattached to a different session: expected $GZMX_E2E_SESSION, got $GZMX_E2E_SESSION2"
gzmx_e2e_pass "reattached to the same session after reopen"

gzmx_e2e_pass "scenario 17 (tsh Cmd-Q preserves server layout + reopen re-projects) complete"
