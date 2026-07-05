#!/bin/zsh
# E2E 12 — remote split inherits the cwd of the SPECIFIC pane being split,
# not the first pane in the tab (multi-pane cwd disambiguation).
#
# Bug: in a tab with two projection panes A (cwd=~) and B (cwd=/tmp/.../proj),
# splitting pane B produced a new pane C whose remote session started at ~
# (pane A's cwd) instead of /tmp/.../proj (pane B's cwd). Root cause: the
# inherit loop matched the parent projection by window only and took the first
# matching row, which was the window's root pane (A), not the pane actually
# being split (B).
#
# Fix: ghostty_zmx_find_sibling_tty enumerates live terminals in the same
# tab as the new split (cur_tty) and returns the sibling's tty (the pane being
# split). The inherit loop then requires the parent projection row's tty to
# match that sibling, so it picks pane B (the true parent) even when pane A is
# also present in the tab.
#
# Scenario:
#   1. ssh handoff → projection pane A (cwd ~).
#   2. Split A → pane B. cd B to /tmp/.../proj-beta.
#   3. Split B → pane C. Pane C should inherit B's cwd (/tmp/.../proj-beta),
#      NOT A's cwd (~).
#   4. Assert pane C's remote cwd is /tmp/.../proj-beta.
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state
gzmx_e2e_ghostty_launch

sleep 2
gzmx_e2e_type "ssh -F $GZMX_E2E_SSHCONFIG $GZMX_E2E_FIXTURE_HOST"
gzmx_e2e_wait_remote_clients 1 20
gzmx_e2e_assert_window_count 2

# Pane A is the projection (front window after widget activation).
# Split A → pane B (native split, default shell, inherit hook fires).
sleep 2
gzmx_e2e_split_focused right
gzmx_e2e_wait_remote_clients 2 20
sleep 2

# In pane B (now focused after the split), cd to proj-beta. Poll for pane B's
# remote cwd to register as beta (readlink /proc/<pid>/cwd lags the cd).
local zmx_bin session_a session_b session_c line name pid cwd sessions names_before_c _beta_ready=0 _beta_i
zmx_bin="$(gzmx_e2e_fixture_zmx)"
gzmx_e2e_type "mkdir -p /tmp/gzmx-e2e-multipane-beta && cd /tmp/gzmx-e2e-multipane-beta && pwd && echo BETA_READY"
for (( _beta_i=1; _beta_i<=45; _beta_i++ )); do
  sleep 1
  sessions="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" "$zmx_bin list 2>/dev/null" 2>/dev/null)"
  session_a=""; session_b=""
  while IFS= read -r line; do
    name="$(print -r -- "$line" | sed -n 's/.*name=\(gzr-[A-Za-z0-9-]*\).*/\1/p')"
    pid="$(print -r -- "$line" | sed -n 's/.*pid=\([0-9]*\).*/\1/p')"
    [[ "$name" == "gzr-"* && "$pid" =~ ^[0-9]+$ ]] || continue
    cwd="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" "readlink /proc/$pid/cwd" 2>/dev/null)"
    if [[ "$cwd" == "/tmp/gzmx-e2e-multipane-beta" ]]; then
      session_b="$name"
    elif [[ -z "$session_a" ]]; then
      session_a="$name"
    fi
  done <<< "$sessions"
  [[ -n "$session_b" ]] && { _beta_ready=1; break; }
done
[[ "$_beta_ready" -eq 1 ]] || gzmx_e2e_fail "could not find pane B (cwd=/tmp/gzmx-e2e-multipane-beta) after 45s"
gzmx_e2e_log "sessions after split A→B: $(print -r -- "$sessions" | tr '\n' '|')"
gzmx_e2e_log "session A (cwd ~): ${session_a:-<none>}"
gzmx_e2e_log "session B (cwd beta): $session_b"
names_before_c="$(print -r -- "$sessions" | sed -n 's/.*name=\(gzr-[A-Za-z0-9-]*\).*/\1/p')"

# Split pane B → pane C. Pane B is currently focused (we typed into it).
gzmx_e2e_split_focused right
gzmx_e2e_wait_remote_clients 3 25
sleep 3

# Find pane C = the newest gzr-* session that is NOT A or B.
sessions="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" "$zmx_bin list 2>/dev/null" 2>/dev/null)"
gzmx_e2e_log "sessions after split B→C: $(print -r -- "$sessions" | tr '\n' '|')"
session_c=""
while IFS= read -r line; do
  name="$(print -r -- "$line" | sed -n 's/.*name=\(gzr-[A-Za-z0-9-]*\).*/\1/p')"
  print -r -- "$names_before_c" | grep -qxF -- "$name" && continue
  [[ -n "$name" ]] && { session_c="$name"; break }
done <<< "$sessions"
[[ -n "$session_c" ]] || gzmx_e2e_fail "could not find pane C (the split of B)"
gzmx_e2e_log "session C (split of B): $session_c"

# THE BUG: pane C should inherit pane B's cwd (/tmp/gzmx-e2e-multipane-beta),
# NOT pane A's cwd (~). Before the fix, the inherit loop picked the first
# projection row in the tab (pane A, cwd ~) as the parent, so pane C started
# at ~.
gzmx_e2e_assert_remote_cwd "$session_c" "/tmp/gzmx-e2e-multipane-beta"

gzmx_e2e_pass "scenario 12 (multi-pane split inherits the SPECIFIC pane's cwd) complete"
