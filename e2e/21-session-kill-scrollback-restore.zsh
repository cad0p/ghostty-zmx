#!/bin/zsh
# E2E 21 — Server-side session kill triggers scrollback restore, not silent reconnect.
#
# The reconnect loop (PR #43) is for CLIENT-side disconnects (ssh/network drop):
# the remote session survives (clients=0), the loop reattaches. But a SERVER-side
# session kill is a different event — the session is GONE. The correct behavior
# is reboot-scrollback restore: create a fresh session, inject the saved scrollback
# with the "[ghostty-zmx restored saved scrollback...]" banner.
#
# Bug: when the remote zmx session is killed, the loop's session-state check may
# return `unknown` (instead of `gone`) if the side-channel `zmx list` can't see
# the session — which happens with the socket-dir mismatch (bug from scenario 20:
# the side-channel ssh also lacks XDG_RUNTIME_DIR, queries /tmp, but the session
# may be elsewhere). `unknown` → "reconnect without reboot-restore" → the saved
# scrollback is NOT injected, and the fresh session starts empty.
#
# This scenario kills the remote zmx session and asserts the banner appears in
# the reattached session's history (proving reboot-restore ran).
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

zmx_bin="$(gzmx_e2e_fixture_zmx)"
GZMX_E2E_SESSION="$(awk -F '\t' '/name=gzr-/ {sub(/.*name=gzr-/, "gzr-"); sub(/[ \t].*/, ""); print; exit}' \
  <(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list 2>/dev/null" 2>/dev/null))"
[[ -n "$GZMX_E2E_SESSION" ]] || gzmx_e2e_fail "could not read session name"
gzmx_e2e_log "session=$GZMX_E2E_SESSION"

# Inject a unique marker into the remote scrollback BEFORE the kill.
MARKER="GZMX_E2E_SESSIONKILL_$$"
ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin send $GZMX_E2E_SESSION 'echo $MARKER'" 2>/dev/null
sleep 1
ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin send $GZMX_E2E_SESSION $'\r'" 2>/dev/null
sleep 1
gzmx_e2e_assert_remote_history_contains "$GZMX_E2E_SESSION" "$MARKER"
gzmx_e2e_pass "marker injected before session kill"

# Take a snapshot of the scrollback BEFORE the kill, so reboot-restore has
# something to inject. Force the wrapper's snapshot path by waiting for a poll
# cycle (the poller snapshots on detach, but we can force it by killing the
# ssh client first... no — that's the client-disconnect path). Instead, rely on
# the Cmd-Q snapshot path: we need the scrollback saved. The wrapper's loop
# snapshots on reconnect attempts (pre-snapshot). For this test, trigger a
# client disconnect first (kill ssh) so the loop snapshots, THEN kill the
# remote session, so the saved scrollback exists for reboot-restore.
_wrapper_pid="$(awk -F '\t' -v h="$GZMX_E2E_FIXTURE_HOST" -v s="$GZMX_E2E_SESSION" '$1==h && $3==s { print $5; exit }' "$GZMX_E2E_DATA_HOME/remote-projections" 2>/dev/null)"
_ssh_child="$(pgrep -P "$_wrapper_pid" 2>/dev/null | head -1)"
if [[ "$_ssh_child" =~ ^[0-9]+$ ]]; then
  gzmx_e2e_log "triggering client disconnect (kill ssh pid=$_ssh_child) to snapshot scrollback..."
  kill -TERM "$_ssh_child" 2>/dev/null
  gzmx_e2e_wait_remote_clients 1 30  # loop reconnects + snapshots
  gzmx_e2e_pass "client disconnect + reconnect (scrollback snapshotted)"
fi

# Now KILL the remote zmx session (server-side kill, not client disconnect).
gzmx_e2e_log "killing remote session $GZMX_E2E_SESSION (server-side)..."
ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin kill $GZMX_E2E_SESSION" 2>/dev/null
sleep 2

# The loop should detect the session is gone and reboot-restore:
# create a fresh session + inject the saved scrollback + banner.
# Wait for the reconnect + restore.
gzmx_e2e_log "waiting for reboot-restore (up to 30s)..."
_restored=0
_hist=""
for (( i=0; i<30; i++ )); do
  # Check the remote session's history for the reboot-restore banner.
  # Use ConnectTimeout so the ssh call fails fast (don't hang the loop).
  _hist="$(ssh -o ConnectTimeout=5 -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin history $GZMX_E2E_SESSION 2>/dev/null" 2>/dev/null)" || true
  if [[ "$_hist" == *"restored saved scrollback"* ]]; then
    _restored=1
    break
  fi
  sleep 1
done

if [[ $_restored -eq 1 ]]; then
  gzmx_e2e_pass "reboot-restore banner injected after server-side session kill"
else
  gzmx_e2e_fail "no reboot-restore banner after session kill (loop reconnected silently without restoring scrollback)"
fi

# Also verify the original marker survived (via the injected snapshot).
if [[ "$_hist" == *"$MARKER"* ]]; then
  gzmx_e2e_pass "original marker restored via scrollback injection"
else
  gzmx_e2e_warn "original marker not in restored scrollback (best-effort)"
fi

gzmx_e2e_pass "scenario 21 (server-side session kill → scrollback restore) complete"
