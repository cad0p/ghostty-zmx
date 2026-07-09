#!/bin/zsh
# E2E 08 — Remote reboot scrollback restore.
#
# If a remote zmx session is lost (remote host rebooted, zmx daemon gone) and
# a local scrollback snapshot exists, ghostty-zmx must inject the saved
# scrollback into a fresh remote session before attaching.
#
# Scenario:
#   1. Open a projection to the fixture.
#   2. Inject a unique marker into the remote scrollback (via zmx send).
#   3. Cmd-Q (graceful quit → reaper snapshots remote scrollback).
#   4. Verify the snapshot file exists and contains the marker.
#   5. Simulate remote reboot: kill the remote zmx session (server row stays present).
#   6. Reopen Ghostty → poller re-projects → wrapper detects missing session,
#      creates fresh + injects banner + saved scrollback.
#   7. Verify the fresh session's zmx history contains both the banner and marker.
#   8. Verify clients=1 (reattached to the fresh session).
# Phase 2: kill the remote session WHILE the projection loop is live (no Cmd-Q).
#   The loop's session-state check must return 'gone' (not 'unknown') and
#   trigger reboot-restore. Catches the regression where a socket-dir mismatch
#   in the side-channel ssh makes the loop return 'unknown' and skip restore.
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

# Capture the session name.
zmx_bin="$(gzmx_e2e_fixture_zmx)"
GZMX_E2E_SESSION="$(awk -F '\t' '/name=gzr-/ {sub(/.*name=gzr-/, "gzr-"); sub(/[ \t].*/, ""); print; exit}' \
  <(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list 2>/dev/null" 2>/dev/null))"
[[ -n "$GZMX_E2E_SESSION" ]] || gzmx_e2e_fail "could not read session name"
gzmx_e2e_log "session=$GZMX_E2E_SESSION"

# 2. Inject a unique marker into the remote scrollback via zmx send (reliable,
#    bypasses the ssh-transport timing issues of typing into the projection).
MARKER="GZMX_E2E_REBOOT_$$"
ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin send $GZMX_E2E_SESSION 'echo $MARKER'" 2>/dev/null
sleep 2
# Send Enter to execute the echo command.
ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin send $GZMX_E2E_SESSION $'\r'" 2>/dev/null
sleep 2

# Verify the marker reached the remote scrollback.
gzmx_e2e_assert_remote_history_contains "$GZMX_E2E_SESSION" "$MARKER"
gzmx_e2e_pass "marker injected into remote scrollback"

# 3. Gracefully quit Ghostty (Cmd-Q path). The poller (reparented to launchd,
#    detached tty) survives the Ghostty process exit; its loop detects the pid
#    is gone and calls ghostty_zmx_snapshot_remote_sessions() before breaking.
#    We must NOT pkill the poller — it needs to run the snapshot. Wait for the
#    snapshot file to appear (the poller writes it after detecting the exit).
gzmx_e2e_log "quitting Ghostty gracefully (Cmd-Q path)..."
osascript -e "tell application \"$GZMX_E2E_GHOSTTY_APP\" to quit" 2>/dev/null
i=1
for (( i=1; i<=40; i++ )); do
  kill -0 "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || break
  sleep 0.5
done
GZMX_E2E_STARTED_GHOSTTY=0
gzmx_e2e_log "Ghostty process exited; waiting for poller to snapshot..."
# Wait for the snapshot file to appear (poller writes it on ghostty-exit).
SNAP="$GZMX_E2E_STATE_HOME/history/$GZMX_E2E_FIXTURE_HOST/${GZMX_E2E_SESSION}.txt"
_snapshot_appeared=0
for (( i=1; i<=30; i++ )); do
  [[ -s "$SNAP" ]] && { _snapshot_appeared=1; break; }
  sleep 1
done
# Now safe to sweep the poller (it has finished its job).
pkill -9 -f "ghostty-zmx-501/(reaper|remote-poller)-${GZMX_E2E_GHOSTTY_PID}" 2>/dev/null || true
gzmx_e2e_log "Ghostty quit complete (snapshot appeared=$_snapshot_appeared)"

# 4. Verify the snapshot file exists and contains the marker.
SNAP="$GZMX_E2E_STATE_HOME/history/$GZMX_E2E_FIXTURE_HOST/${GZMX_E2E_SESSION}.txt"
[[ -s "$SNAP" ]] || gzmx_e2e_fail "snapshot file not created: $SNAP"
grep -q "$MARKER" "$SNAP" \
  || gzmx_e2e_fail "snapshot file does not contain marker: $SNAP"
gzmx_e2e_pass "snapshot file created with marker: $SNAP"

# 5. Simulate remote reboot: kill the remote zmx session (server row stays present).
ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin kill $GZMX_E2E_SESSION" 2>/dev/null
sleep 1
# Verify the session is gone on the remote.
_remote_session_gone() {
  local out
  out="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list --short 2>/dev/null" 2>/dev/null)"
  [[ "$out" != *"$GZMX_E2E_SESSION"* ]]
}
gzmx_e2e_wait_for 10 _remote_session_gone || gzmx_e2e_fail "remote session did not die after zmx kill"
gzmx_e2e_pass "remote session killed (simulated reboot)"

# Verify the server layout row is still `present` (the kill didn't touch it).
_row="$(gzmx_e2e_remote_layout_row "$GZMX_E2E_SESSION")"
[[ "$_row" == *"present"* ]] || gzmx_e2e_fail "server row not present after reboot sim (row=$_row)"
gzmx_e2e_pass "server layout row still 'present' after reboot sim"

# 6. Reopen Ghostty → poller re-projects → wrapper detects missing session,
#    creates fresh + injects banner + saved scrollback.
GZMX_E2E_STARTED_GHOSTTY=0
gzmx_e2e_ghostty_launch
gzmx_e2e_log "Ghostty relaunched pid=$GZMX_E2E_GHOSTTY_PID"

# Wait for the projection to reopen and reattach to the fresh session.
gzmx_e2e_wait_remote_clients 1 30
gzmx_e2e_assert_window_count 2

# 7. Verify the fresh session's zmx history contains both the banner and marker.
#    The wrapper creates a fresh session with the SAME name (from the server
#    layout row), then injects the saved scrollback via base64 + zmx print.
_reboot_banner="[ghostty-zmx restored saved scrollback from a previous boot; process state was not restored]"
_banner_found=0
_marker_found=0
_retries=0
while [[ $_retries -lt 15 ]]; do
  _hist="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin history $GZMX_E2E_SESSION 2>/dev/null" 2>/dev/null)"
  [[ "$_hist" == *"restored saved scrollback"* ]] && _banner_found=1
  [[ "$_hist" == *"$MARKER"* ]] && _marker_found=1
  [[ $_banner_found -eq 1 && $_marker_found -eq 1 ]] && break
  _retries=$((_retries + 1))
  sleep 1
done
[[ $_banner_found -eq 1 ]] \
  || gzmx_e2e_fail "reboot-restore banner not in fresh session history"
gzmx_e2e_pass "reboot-restore banner injected into fresh session"
[[ $_marker_found -eq 1 ]] \
  || gzmx_e2e_fail "marker not injected into fresh session history"
gzmx_e2e_pass "saved scrollback (marker) injected into fresh session"

# 8. Verify the projection re-attached (clients=1).
gzmx_e2e_assert_remote_clients 1
gzmx_e2e_pass "projection re-attached to fresh session (clients=1)"

# Verify the wrapper logged the reboot-restore path.
grep -q "reboot-restore session missing" "$GZMX_E2E_STATE_HOME/debug.log" 2>/dev/null \
  && gzmx_e2e_pass "wrapper logged reboot-restore injection" \
  || gzmx_e2e_warn "reboot-restore log line not found (best-effort)"

# --- Phase 2: session kill WHILE the projection loop is live (no Cmd-Q) ---
# The loop's session-state check must return 'gone' (ssh OK, session missing)
# and trigger reboot-restore — NOT 'unknown' (which skips restore and
# reconnects silently). On real hosts (pcad-dev) a socket-dir mismatch in
# the side-channel ssh made it return 'unknown'; this phase catches that
# regression by killing the session while the loop is attached.
# Re-inject a fresh marker (the phase-1 restore created a fresh session).
MARKER2="GZMX_E2E_LIVEKILL_$$"
ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin send $GZMX_E2E_SESSION 'echo $MARKER2'" 2>/dev/null
sleep 1
ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin send $GZMX_E2E_SESSION $'\r'" 2>/dev/null
sleep 1
gzmx_e2e_assert_remote_history_contains "$GZMX_E2E_SESSION" "$MARKER2"
gzmx_e2e_pass "phase-2 marker injected before live session kill"

# Trigger a client disconnect so the loop snapshots the scrollback (gives
# reboot-restore something to inject after the kill).
_wrapper_pid="$(awk -F '\t' -v h="$GZMX_E2E_FIXTURE_HOST" -v s="$GZMX_E2E_SESSION" '$1==h && $3==s { print $5; exit }' "$GZMX_E2E_DATA_HOME/remote-projections" 2>/dev/null)"
_ssh_child="$(pgrep -P "$_wrapper_pid" 2>/dev/null | head -1)"
if [[ "$_ssh_child" =~ ^[0-9]+$ ]]; then
  gzmx_e2e_log "triggering client disconnect (kill ssh pid=$_ssh_child) to snapshot scrollback..."
  kill -TERM "$_ssh_child" 2>/dev/null
  gzmx_e2e_wait_remote_clients 1 30
  gzmx_e2e_pass "client disconnect + reconnect (scrollback snapshotted)"
fi

# Now KILL the remote session while the loop is live (server-side kill, not
# client disconnect). The loop should detect 'gone' and reboot-restore.
gzmx_e2e_log "killing remote session $GZMX_E2E_SESSION (server-side, loop live)..."
ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin kill $GZMX_E2E_SESSION" 2>/dev/null
sleep 2

# Wait for the loop to detect the kill and reboot-restore.
gzmx_e2e_log "waiting for live-kill reboot-restore (up to 30s)..."
_live_banner=0
_hist2=""
for (( i=0; i<30; i++ )); do
  _hist2="$(ssh -o ConnectTimeout=5 -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin history $GZMX_E2E_SESSION 2>/dev/null" 2>/dev/null)" || true
  if [[ "$_hist2" == *"restored saved scrollback"* ]]; then
    _live_banner=1
    break
  fi
  sleep 1
done
[[ $_live_banner -eq 1 ]] \
  && gzmx_e2e_pass "reboot-restore ran after live session kill (loop detected 'gone', not 'unknown')" \
  || gzmx_e2e_fail "no reboot-restore after live session kill (loop returned 'unknown', skipped restore)"

[[ "$_hist2" == *"$MARKER2"* ]] \
  && gzmx_e2e_pass "phase-2 marker restored via live-kill scrollback injection" \
  || gzmx_e2e_warn "phase-2 marker not in restored scrollback (best-effort)"

gzmx_e2e_pass "scenario 08 (remote reboot scrollback restore) complete"
