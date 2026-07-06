#!/bin/zsh
# E2E 14 - Cmd-Q preserves and restores a multi-tab remote projection layout.
#
# Regression: two remote tabs survived Cmd-Q as server `present` rows, but
# reopen restored the second tab as a split in the first tab. The single-pane
# Cmd-Q E2E did not catch that layout-shape bug.
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state
gzmx_e2e_ghostty_launch

_gzr_sessions_sorted() {
  local zmx_bin
  zmx_bin="$(gzmx_e2e_fixture_zmx)"
  ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list 2>/dev/null" 2>/dev/null |
    sed -n 's/.*name=\(gzr-[A-Za-z0-9-]*\).*/\1/p' |
    sort
}

# Open a projection, then create a native tab in that projection window. The
# startup hooks should inherit the remote context and attach a second gzr-*.
sleep 2
gzmx_e2e_type "ssh -F $GZMX_E2E_SSHCONFIG $GZMX_E2E_FIXTURE_HOST"
gzmx_e2e_wait_remote_clients 1 20
gzmx_e2e_assert_window_count 2

projection_win="$(awk -F '\t' -v h="$GZMX_E2E_FIXTURE_HOST" '$1 == h && $6 == "attached" { print $8; exit }' "$GZMX_E2E_DATA_HOME/remote-projections" 2>/dev/null)"
[[ -n "$projection_win" && "$projection_win" != "-" ]] || gzmx_e2e_fail "could not read projection window id from remote-projections"
gzmx_e2e_log "projection window id suffix: $projection_win"

sleep 2
gzmx_e2e_new_tab_in_window_id_suffix "$projection_win"
gzmx_e2e_wait_remote_clients 2 25
gzmx_e2e_assert_window_count 2
gzmx_e2e_assert_window_id_with_tabs_and_terminals "$projection_win" 2 1

sessions_before="$(_gzr_sessions_sorted)"
session_count="$(print -r -- "$sessions_before" | grep -c '^gzr-' || true)"
[[ "$session_count" == "2" ]] || gzmx_e2e_fail "expected 2 remote tab sessions before Cmd-Q, got $session_count: $sessions_before"
gzmx_e2e_log "sessions before Cmd-Q: $(print -r -- "$sessions_before" | tr '\n' ' ')"

# Gracefully quit Ghostty via osascript `quit` (Cmd-Q path).
gzmx_e2e_log "quitting Ghostty gracefully (Cmd-Q path)..."
osascript -e "tell application \"$GZMX_E2E_GHOSTTY_APP\" to quit" 2>/dev/null
for (( i=1; i<=40; i++ )); do
  kill -0 "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || break
  sleep 0.5
done
kill -9 "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || true
pkill -9 -f "ghostty-zmx-501/(reaper|remote-poller)-${GZMX_E2E_GHOSTTY_PID}" 2>/dev/null || true
GZMX_E2E_STARTED_GHOSTTY=0
sleep 2
gzmx_e2e_log "Ghostty quit complete"

# The remote sessions and server layout rows must survive as present.
zmx_bin="$(gzmx_e2e_fixture_zmx)"
while IFS= read -r session; do
  [[ -n "$session" ]] || continue
  ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    "$zmx_bin list 2>/dev/null" 2>/dev/null | grep -qF "name=$session" \
    || gzmx_e2e_fail "remote session $session did not survive Cmd-Q"
  row="$(gzmx_e2e_remote_layout_row "$session")"
  [[ "$row" == *"present"* ]] || gzmx_e2e_fail "server row not present after Cmd-Q for $session (row=$row)"
done <<< "$sessions_before"
gzmx_e2e_pass "both remote tab sessions survived Cmd-Q as present rows"

# Relaunch. Restore should recreate one projection window with two tabs, not
# one projection window with a split.
GZMX_E2E_STARTED_GHOSTTY=0
gzmx_e2e_ghostty_launch
gzmx_e2e_log "Ghostty relaunched pid=$GZMX_E2E_GHOSTTY_PID"

gzmx_e2e_wait_remote_clients 2 35
gzmx_e2e_assert_window_count 2
gzmx_e2e_assert_window_with_tabs_and_terminals 2 1

sessions_after="$(_gzr_sessions_sorted)"
[[ "$sessions_after" == "$sessions_before" ]] \
  || gzmx_e2e_fail "reattached to different sessions: before=[$sessions_before] after=[$sessions_after]"
gzmx_e2e_pass "reattached to the same two remote tab sessions after reopen"

gzmx_e2e_pass "scenario 14 (Cmd-Q multi-tab remote restore shape) complete"
