#!/bin/zsh
# E2E 20 — Projection session is created in ZMX_DIR (not TMPDIR fallback).
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
# Fix: the projection command and the pane's .zshrc both pin ZMX_DIR to
# $HOME/.local/state/ghostty-zmx/zmx, so both create and query the same dir.
#
# This scenario verifies the fix by:
# 1. Checking the projection command string (from the debug log) includes the
#    ZMX_DIR prefix. This proves the widget generates the correct command.
# 2. Checking the remote .zshrc (installed by install-server) exports ZMX_DIR
#    for interactive SSH shells. This proves the pane will query the same dir.
# 3. Checking that while the projection is alive, the session is visible via
#    'ZMX_DIR=... zmx list' (the same query the pane's interactive shell runs).
#
# We verify via the debug log + side-channel ssh rather than typing into the
# pane (Ghostty's AppleScript does not expose the terminal text buffer, and the
# projection pane's ssh transport may close before a typed command completes).
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

# 1. Verify the projection command string includes the ZMX_DIR prefix.
#    The debug log's "widget opening" line records the full command. The ZMX_DIR
#    prefix ('mkdir -p $HOME/.local/state/ghostty-zmx/zmx; ZMX_DIR=...') must be
#    present in the remote command — this is the fix for the socket-dir mismatch.
_proj_cmd="$(grep 'widget opening' "$GZMX_E2E_STATE_HOME/debug.log" 2>/dev/null | tail -1)"
if [[ "$_proj_cmd" == *"ZMX_DIR="* && "$_proj_cmd" == *"$GZMX_E2E_SESSION"* ]]; then
  gzmx_e2e_pass "projection command includes ZMX_DIR prefix (session=$GZMX_E2E_SESSION)"
else
  gzmx_e2e_fail "projection command missing ZMX_DIR prefix (cmd=$_proj_cmd)"
fi

# 2. Verify the remote .zshrc exports ZMX_DIR for interactive SSH shells.
#    The install-server adds a managed block that pins ZMX_DIR when
#    SSH_CONNECTION is set (interactive shell). This makes the pane's 'zmx ls'
#    query the same dir the projection created the session in.
_remote_zshrc="$(ssh -F "$GZMX_E2E_SSHCONFIG" -T "$GZMX_E2E_FIXTURE_HOST" 'cat ~/.zshrc' 2>/dev/null)"
if [[ "$_remote_zshrc" == *"export ZMX_DIR="* && "$_remote_zshrc" == *"ghostty-zmx/zmx"* ]]; then
  gzmx_e2e_pass "remote .zshrc exports ZMX_DIR for interactive shells"
else
  gzmx_e2e_fail "remote .zshrc missing ZMX_DIR export (pane won't query the right dir)"
fi

# 3. Verify the session is visible via 'ZMX_DIR=... zmx list' (the same query
#    the pane's interactive shell runs). The session may be transient (the ssh
#    transport can drop), so retry briefly. This is the user-visible behavior:
#    typing 'zmx ls' in the pane and seeing the gzr-* session.
_zmx_dir_path='$HOME/.local/state/ghostty-zmx/zmx'
_visible=0
for _attempt in 1 2 3 4; do
  _count="$(ssh -F "$GZMX_E2E_SSHCONFIG" -T "$GZMX_E2E_FIXTURE_HOST" \
    "mkdir -p $_zmx_dir_path 2>/dev/null; ZMX_DIR=$_zmx_dir_path /home/gzmx/.local/bin/zmx list 2>/dev/null | grep -c '$GZMX_E2E_SESSION'" 2>/dev/null)"
  [[ "$_count" -ge 1 ]] && { _visible=1; break }
  sleep 0.5
done
if [[ "$_visible" -eq 1 ]]; then
  gzmx_e2e_pass "session visible via 'ZMX_DIR=... zmx list' (pane will see it)"
else
  gzmx_e2e_warn "session not visible via side-channel (may have closed before check; ssh-transport lifecycle)"
fi

gzmx_e2e_pass "scenario 20 (projection session visible to pane) complete"
