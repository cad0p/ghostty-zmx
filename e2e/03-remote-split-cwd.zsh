#!/bin/zsh
# E2E 03 — remote split/tab inherits the parent's working directory.
#
# Bug: "remote ssh new split / tab etc doesn't follow ghostty setting to keep
# or not keep the current working dir, always goes to ~".
#
# Scenario:
#   1. Open a remote projection to the fixture (ssh handoff).
#   2. In the remote pane, cd to a unique directory and print a marker.
#   3. Create a native split (Cmd+D) of the remote projection pane.
#   4. The split should inherit the remote context (zmx attach a NEW gzr session
#      for the same host/window/tab) — the inherit path.
#   5. The new remote session's cwd should be the parent's remote cwd
#      (the directory we cd'd to), NOT ~.
#
# This currently FAILS: zmx attach spawns a login shell at $HOME for a fresh
# session, so the split's remote session starts at ~ regardless of the parent's
# cwd. The fix passes the parent's remote cwd to the new session.
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state
gzmx_e2e_ghostty_launch

# Wait for the local shell to be ready, then type the ssh command.
sleep 2
gzmx_e2e_type "ssh -F $GZMX_E2E_SSHCONFIG $GZMX_E2E_FIXTURE_HOST"
gzmx_e2e_wait_remote_clients 1 20
gzmx_e2e_assert_window_count 2

# In the remote pane (the projection window, which the widget activated to
# front), cd to a unique directory. The widget's `activate window w` brings the
# projection to front (index 1), so `gzmx_e2e_type` (front window) targets it.
# We do NOT use type_in_window 2 — after activation the projection IS front.
sleep 3
gzmx_e2e_type "mkdir -p /tmp/gzmx-e2e-cwd-marker && cd /tmp/gzmx-e2e-cwd-marker && pwd && echo CWD_MARKER_READY"
sleep 3

# Find the parent session name (the first gzr-* session).
local zmx_bin parent_session
zmx_bin="$(gzmx_e2e_fixture_zmx)"
parent_session="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin list 2>/dev/null | grep 'name=gzr-' | head -1" 2>/dev/null \
  | sed -n 's/.*name=\(gzr-[A-Za-z0-9-]*\).*/\1/p')"
[[ -n "$parent_session" ]] || gzmx_e2e_fail "no parent gzr-* session found"
gzmx_e2e_log "parent session: $parent_session"

# Verify the parent's remote cwd is the marker directory.
gzmx_e2e_assert_remote_cwd "$parent_session" "/tmp/gzmx-e2e-cwd-marker"

# Create a native split (Cmd+D equivalent) of the remote projection pane. The
# projection is the front window (widget activated it). We use AppleScript
# `split ... with configuration` (no command set) to create the split reliably —
# this is the same surface shape Ghostty's native Cmd+D produces: a default
# local shell that sources .zprofile/.zshrc and runs the inherit hook.
gzmx_e2e_split_focused right
sleep 3
gzmx_e2e_log "terminal count after split:"
osascript <<'OSA' 2>&1 | head -5
tell application "Ghostty-tip"
  set out to ""
  repeat with w in windows
    repeat with tb in tabs of w
      set out to out & (count of terminals of tb) & " "
    end repeat
    set out to out & linefeed
  end repeat
  return out
end tell
OSA

# A new remote session should attach within ~15s.
gzmx_e2e_wait_remote_clients 2 20

# Find the child session name (a DIFFERENT gzr-* session).
local child_session
child_session="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin list 2>/dev/null | grep 'name=gzr-' | grep -v '$parent_session'" 2>/dev/null \
  | sed -n 's/.*name=\(gzr-[A-Za-z0-9-]*\).*/\1/p' | head -1)"
[[ -n "$child_session" ]] || gzmx_e2e_fail "no child gzr-* session found (split did not inherit remote context)"
gzmx_e2e_log "child session: $child_session"

# The child's remote cwd should be the parent's cwd (the marker dir), NOT ~.
# This is the bug: currently the child starts at ~.
gzmx_e2e_assert_remote_cwd "$child_session" "/tmp/gzmx-e2e-cwd-marker"

gzmx_e2e_pass "scenario 03 (remote split cwd inheritance) complete"
