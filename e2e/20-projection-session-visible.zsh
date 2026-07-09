#!/bin/zsh
# E2E 20 — Projection session is visible to the pane's interactive shell.
#
# Bug: the projection runs `ssh host 'zmx attach gzr-...'` as a NON-interactive
# command. On real Linux hosts, XDG_RUNTIME_DIR is set by pam_systemd for
# interactive login shells but NOT for non-interactive ssh commands. zmx's
# socket-dir resolution (ZMX_DIR > XDG_RUNTIME_DIR > TMPDIR) means:
#   - the projection creates the session in TMPDIR (/tmp/zmx-<uid>)
#   - the pane's interactive shell queries XDG_RUNTIME_DIR (/run/user/<uid>/zmx)
#   → mismatch: `zmx ls` in the pane does NOT list the gzr-* session it's
#   attached to, even though $ZMX_SESSION confirms the attach succeeded.
#
# This scenario reproduces the mismatch (the fixture simulates pam_systemd by
# setting XDG_RUNTIME_DIR in .zshrc) and asserts the pane can see its own session.
#
# This is the user-facing symptom: typing `zmx ls` in a remote projection pane
# shows unrelated/old sessions instead of the gzr-* session the pane is in.
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

# Capture the session name.
zmx_bin="$(gzmx_e2e_fixture_zmx)"
GZMX_E2E_SESSION="$(awk -F '\t' '/name=gzr-/ {sub(/.*name=gzr-/, "gzr-"); sub(/[ \t].*/, ""); print; exit}' \
  <(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list 2>/dev/null" 2>/dev/null))"
[[ -n "$GZMX_E2E_SESSION" ]] || gzmx_e2e_fail "could not read session name"
gzmx_e2e_log "session=$GZMX_E2E_SESSION"

# Type `zmx ls` INTO the projection pane and capture which sessions it lists.
# The pane's interactive shell has XDG_RUNTIME_DIR set (simulated pam_systemd),
# so zmx ls queries /run/user/<uid>/zmx — where the gzr session must be visible.
sleep 3  # let the remote shell settle
_projection_win=2
gzmx_e2e_type_in_window "$_projection_win" "zmx ls"
sleep 2

# Capture the pane's screen text via AppleScript and check the session is listed.
# `contents of tm` returns the terminal's text buffer.
_pane_text="$(osascript <<OSA 2>/dev/null
tell application "$GZMX_E2E_GHOSTTY_APP"
  set w to item $_projection_win of windows
  set tb to selected tab of w
  set tm to focused terminal of tb
  return (contents of tm)
end tell
OSA
)"

if [[ "$_pane_text" == *"$GZMX_E2E_SESSION"* ]]; then
  gzmx_e2e_pass "projection pane sees its own gzr session via 'zmx ls'"
else
  gzmx_e2e_fail "pane 'zmx ls' does not list $GZMX_E2E_SESSION (socket-dir mismatch: projection created in /tmp, pane queries \$XDG_RUNTIME_DIR)"
fi

# Also verify $ZMX_SESSION is set in the pane (the attach itself succeeded).
gzmx_e2e_type_in_window "$_projection_win" 'echo ZMX_SESSION=$ZMX_SESSION'
sleep 1
_zmx_var="$(osascript <<OSA 2>/dev/null
tell application "$GZMX_E2E_GHOSTTY_APP"
  set w to item $_projection_win of windows
  set tb to selected tab of w
  set tm to focused terminal of tb
  return (contents of tm)
end tell
OSA
)"
if [[ "$_zmx_var" == *"$GZMX_E2E_SESSION"* ]]; then
  gzmx_e2e_pass "pane \$ZMX_SESSION matches (attach succeeded)"
else
  gzmx_e2e_fail "pane \$ZMX_SESSION does not show $GZMX_E2E_SESSION"
fi

gzmx_e2e_pass "scenario 20 (projection session visible to pane) complete"
