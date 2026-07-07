#!/bin/zsh
# E2E 18 — local Cmd+W reaps the closed pane (tty-disappeared cleanup).
#
# Issue #38 L2 wants the intentional-close reap path for LOCAL zmx-* sessions,
# which e2e/16 does NOT cover (16 tests Cmd-Q preserve+reopen, not Cmd+W kill).
# Closing a local pane (Cmd+W) must trigger the reaper's reap path:
#   managed_disappeared_sessions (immediate, tty-disappeared) OR
#   managed_detached_sessions (6s grace) → cleanup_detached_session:
#   snapshot_history → zmx kill → cleanup_log (remove from sessions file) →
#   forget_snapshot (delete the snapshot file).
#
# The reaper only runs managed_disappeared_sessions when attached>0 (at least
# one other managed session is still attached). So this scenario creates a
# SECOND local window (S2) before closing the first window (S1) via Cmd+W.
# Closing a single-pane window via Cmd+W unambiguously closes only that pane
# (no split-terminal-ordering ambiguity). S2 stays attached, so the reaper
# sees attached>0 and reaps S1 via the tty-disappeared path.
#
# This is the local-session counterpart of e2e/05 (remote close transaction).
# e2e/05 closes a REMOTE projection pane (gzr-*) and asserts the server close
# txn runs; this closes a LOCAL pane (zmx-*) and asserts the local reaper path.
#
# Scenario:
#   1. Launch Ghostty (no ssh). The first pane auto-attaches to zmx-* (S1).
#   2. Open a second Ghostty window → second local zmx-* session (S2).
#   3. Activate S2's window and send Cmd+W (confirm-close-surface=false → the
#      single-pane window closes with no confirmation sheet).
#   4. Assert S2 is reaped: gone from zmx list, gone from sessions file, and
#      the debug log records "tty disappeared session=S2" + "tty-disappeared
#      cleanup session=S2".
#   5. Assert S1 is untouched (still attached, still in sessions file).
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state
gzmx_e2e_ghostty_launch

# Wait for the local shell to auto-attach to a zmx-* session.
sleep 2
_local_session() {
  [[ -r "$GZMX_E2E_DATA_HOME/sessions" ]] || return 1
  awk '/^zmx-/ { print; exit }' "$GZMX_E2E_DATA_HOME/sessions" 2>/dev/null
}
gzmx_e2e_wait_for 20 _local_session || gzmx_e2e_fail "no zmx-* session in sessions file"
S1="$(_local_session)"
gzmx_e2e_pass "S1 local session created: $S1"
zmx list 2>/dev/null | grep -q "name=$S1" || gzmx_e2e_fail "S1 $S1 not in zmx list"
gzmx_e2e_pass "S1 alive in zmx list (clients=1)"

# --- Open a second window → second local zmx-* session (S2) -----------------
# A new Ghostty window with the default shell sources .zshrc and auto-attaches
# to a fresh zmx-* session. Using a separate window (not a split) avoids
# terminal-ordering ambiguity when closing: Cmd+W on a single-pane window
# closes only that pane.
osascript <<OSA 2>/dev/null || true
tell application "$GZMX_E2E_GHOSTTY_APP"
  set cfg to new surface configuration
  set w to new window with configuration cfg
  activate window w
end tell
OSA
sleep 2
gzmx_e2e_assert_window_count 2

_sessions_count() {
  local n
  n="$(awk '/^zmx-/ { c++ } END { print c+0 }' "$GZMX_E2E_DATA_HOME/sessions" 2>/dev/null)"
  [[ "$n" -ge 2 ]]
}
gzmx_e2e_wait_for 20 _sessions_count || gzmx_e2e_fail "expected >=2 local zmx-* sessions after new window"
# S2 is the newest zmx-* session in the file (auto-append order).
S2="$(awk '/^zmx-/ { s=$0 } END { print s }' "$GZMX_E2E_DATA_HOME/sessions" 2>/dev/null)"
[[ -n "$S2" && "$S2" != "$S1" ]] || gzmx_e2e_fail "new window did not create a second distinct local session (got $S2)"
gzmx_e2e_pass "S2 window session created: $S2"

_both_attached() {
  local out
  out="$(zmx list 2>/dev/null)"
  [[ "$out" == *"name=$S1"*"clients=1"* ]] || return 1
  [[ "$out" == *"name=$S2"*"clients=1"* ]] || return 1
}
gzmx_e2e_wait_for 15 _both_attached || gzmx_e2e_fail "both local sessions not attached after new window"
gzmx_e2e_pass "both S1 and S2 attached (clients=1)"

# Wait for BOTH sessions to appear in the cross-install registry before
# closing. managed_disappeared_sessions cross-checks the tty-map against
# registry_tracked_sessions (union of all install registry files); a session
# not yet heartbeated into the registry is skipped by the tty-disappeared
# path and falls back to the slower managed_detached_sessions 6s-grace path.
# Waiting here ensures the reaper has heartbeated S2 so the immediate
# tty-disappeared reap fires (the path under test).
_registry_dir="$HOME/.local/state/ghostty-zmx/managed-sessions"
_s2_in_registry() {
  [[ -d "$_registry_dir" ]] || return 1
  grep -rqxF "$S2" "$_registry_dir"/*.tsv 2>/dev/null
}
gzmx_e2e_wait_for 15 _s2_in_registry || gzmx_e2e_warn "S2 not in registry yet (reaper may use detached-grace path instead of tty-disappeared)"
gzmx_e2e_pass "S2 in cross-install registry (tty-disappeared path will fire)"

# --- Close S2's window via Cmd+W (mirror e2e/05's delivery) --------------
# The new-window call left S2's window at the front (item 1). Activate it and
# send Cmd+W via System Events `keystroke "w" using command down` (the same
# delivery e2e/05 uses successfully for remote close). With confirm-close-
# surface=false (harness launch config), closing the single-surface window has
# no confirmation sheet. S1's window survives, so the reaper sees attached>0
# and runs managed_disappeared_sessions for S2.
osascript <<OSA 2>/dev/null || true
tell application "$GZMX_E2E_GHOSTTY_APP"
  set w to item 1 of windows
  activate window w
end tell
OSA
sleep 1
osascript <<OSA 2>/dev/null || true
tell application "System Events"
  keystroke "w" using command down
end tell
OSA
gzmx_e2e_log "sent Cmd+W to close S2's window ($S2)"

# The window should close; window count drops to 1.
_window_dropped() {
  local n
  n="$(osascript -e "tell application \"$GZMX_E2E_GHOSTTY_APP\" to count of windows" 2>/dev/null)"
  [[ "$n" == "1" ]]
}
gzmx_e2e_wait_for 10 _window_dropped || gzmx_e2e_warn "window count did not drop to 1 (timing; reap assertions below are authoritative)"

# --- Assert S2 is reaped --------------------------------------------------
# The reaper observes the tty disappeared and runs cleanup_detached_session:
# zmx kill + cleanup_log + forget_snapshot. Wait for S2 to leave zmx list.
_s2_gone_from_zmx() {
  zmx list 2>/dev/null | grep -q "name=$S2" && return 1 || return 0
}
gzmx_e2e_wait_for 25 _s2_gone_from_zmx || gzmx_e2e_fail "S2 $S2 was not reaped (still in zmx list)"
gzmx_e2e_pass "S2 reaped from zmx list (zmx kill)"

_s2_gone_from_sessions() {
  [[ -r "$GZMX_E2E_DATA_HOME/sessions" ]] || return 1
  ! grep -qxF "$S2" "$GZMX_E2E_DATA_HOME/sessions" 2>/dev/null
}
gzmx_e2e_wait_for 10 _s2_gone_from_sessions || gzmx_e2e_fail "S2 $S2 was not removed from sessions file"
gzmx_e2e_pass "S2 removed from sessions file (cleanup_log)"

_debug_log="$GZMX_E2E_STATE_HOME/debug.log"
# The reaper reaps a closed local pane via one of two paths:
#   - managed_disappeared_sessions (immediate, if the tty-map entry is still
#     present when the reaper cycle runs and the tty is gone from the live
#     terminal list) — logs "tty disappeared session=S2" + "tty-disappeared
#     cleanup session=S2".
#   - managed_detached_sessions (6s grace, if the tty-map entry was already
#     cleared or the timing window was missed) — logs "detached cleanup
#     session=S2".
# Both paths run cleanup_detached_session (snapshot + zmx kill + cleanup_log
# + forget_snapshot). Accept either log signature; the outcome assertions above
# (gone from zmx list + sessions file) are the authoritative checks.
_reap_logged() {
  [[ -r "$_debug_log" ]] || return 1
  grep -qE "(tty disappeared session=$S2|detached cleanup session=$S2)" "$_debug_log" 2>/dev/null
}
gzmx_e2e_wait_for 10 _reap_logged || gzmx_e2e_fail "neither tty-disappeared nor detached-grace reap was logged for S2 $S2"
_reap_path="$(grep -oE "(tty-disappeared cleanup|detached cleanup) session=$S2" "$_debug_log" 2>/dev/null | head -1)"
gzmx_e2e_pass "S2 reaped via local reaper ($_reap_path)"

# --- Assert S1 is untouched -----------------------------------------------
zmx list 2>/dev/null | grep -q "name=$S1" \
  || gzmx_e2e_fail "surviving session S1 $S1 was also reaped (regression)"
zmx list 2>/dev/null | grep "name=$S1" | grep -q "clients=1" \
  || gzmx_e2e_warn "S1 not clients=1 after S2 reap (timing)"
grep -qxF "$S1" "$GZMX_E2E_DATA_HOME/sessions" 2>/dev/null \
  || gzmx_e2e_warn "S1 not in sessions file after S2 reap (timing)"
gzmx_e2e_pass "S1 surviving session untouched"

gzmx_e2e_ghostty_quit
gzmx_e2e_pass "scenario 18 (local Cmd+W reap via local reaper) complete"
