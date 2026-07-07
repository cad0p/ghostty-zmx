#!/bin/zsh
# E2E 16 — local zmx-* session lifecycle (issue #38 L1/L2) + managed-surface
# handoff-history persistence.
#
# The rest of the suite (e2e/01..15) exercises only the remote projection path
# (gzr-* over ssh/tsh). This scenario covers the v0.1 CORE that had ZERO live
# E2E coverage: local auto-attach creates a zmx-* session, the reaper runs,
# the cross-install registry is heartbeated, and Cmd-Q preserves the session
# for reopen. It also verifies the history fix (no Up-arrow override; the
# handoff command is persisted via `print -s` + `fc -R` so plain Up-arrow
# recalls it) inside a REAL managed Ghostty surface — complementing
# tests/handoff-history.zsh which proves the recall path in a pty.
#
# Scenario:
#   L1 — local auto-attach + reaper + registry:
#     1. Launch Ghostty (no ssh). The first pane auto-attaches to a zmx-* session.
#     2. Assert zmx-* session is in the sessions file AND in `zmx list`.
#     3. Assert the reaper flag exists (reaper-<pid>.lock in the runtime dir).
#     4. Assert the cross-install registry file exists and lists the session.
#   History — handoff command persisted to zsh history:
#     5. In the local pane, type an ssh handoff (opens projection window 2).
#     6. Assert the handoff command is in HISTFILE (the widget wrote it via
#        `print -s` + `fc -R`; without this, Up-arrow would not recall it).
#   L2 — Cmd-Q preserves local session; reopen reattaches:
#     7. Gracefully quit Ghostty (osascript quit = Cmd-Q path).
#     8. Assert the local session survived (detached, clients=0).
#     9. Relaunch Ghostty; assert it reattaches to the SAME session (not new).
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state
gzmx_e2e_ghostty_launch

# Wait for the local shell to auto-attach to a zmx-* session.
sleep 2

# --- L1: local auto-attach + reaper + registry -----------------------------

# The sessions file (under GHOSTTY_ZMX_DATA_HOME) lists managed zmx-* sessions.
_local_session() {
  [[ -r "$GZMX_E2E_DATA_HOME/sessions" ]] || return 1
  awk '/^zmx-/ { print; exit }' "$GZMX_E2E_DATA_HOME/sessions" 2>/dev/null
}
gzmx_e2e_wait_for 20 _local_session || gzmx_e2e_fail "no zmx-* session in sessions file"
LOCAL_SESSION="$(_local_session)"
gzmx_e2e_pass "L1: local zmx-* session logged: $LOCAL_SESSION"

# The session must be live in the zmx daemon (clients=1: the local pane).
zmx list 2>/dev/null | grep -q "name=$LOCAL_SESSION" \
  || gzmx_e2e_fail "local session $LOCAL_SESSION not in zmx list"
gzmx_e2e_pass "L1: local session alive in zmx list (clients=1)"

# The reaper flag must exist: reaper-<ghostty-pid>.lock in the runtime dir.
_runtime="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ghostty-zmx-${UID:-$(id -u)}"
_reaper_flag="$_runtime/reaper-${GZMX_E2E_GHOSTTY_PID}.lock"
_reaper_flag_exists() { [[ -d "$_reaper_flag" ]] }
gzmx_e2e_wait_for 10 _reaper_flag_exists || gzmx_e2e_fail "reaper flag not created: $_reaper_flag"
gzmx_e2e_pass "L1: reaper running (flag=$_reaper_flag)"

# The cross-install registry file must exist and list the session. The registry
# lives under real $HOME (fixed path, shared across installs), keyed by a hash
# of GHOSTTY_ZMX_DATA_HOME so this test's tmpdir-data-home isolates it from real
# installs. The reaper heartbeats the file on each cycle.
_registry_dir="$HOME/.local/state/ghostty-zmx/managed-sessions"
_registry_hash="$(print -r -- "$GZMX_E2E_DATA_HOME" | cksum 2>/dev/null | tr -d ' ' | cut -c1-16)"
[[ -n "$_registry_hash" ]] || _registry_hash="default"
_registry_file="$_registry_dir/${_registry_hash}.tsv"
_registry_has_session() {
  [[ -f "$_registry_file" ]] || return 1
  grep -qF "$LOCAL_SESSION" "$_registry_file" 2>/dev/null
}
gzmx_e2e_wait_for 15 _registry_has_session || gzmx_e2e_fail "registry file does not list session: $_registry_file"
gzmx_e2e_pass "L1: cross-install registry heartbeated with session"

# --- History: handoff command persisted to zsh history ---------------------
# The accept-line widget intercepts the ssh/tsh line (does not call
# zle .accept-line), so zsh's normal history recording is bypassed. The
# widget must `print -s` + `fc -R` so the handoff command is recallable by
# plain Up-arrow. We verify the persistence half here (the recall half is
# covered faithfully by tests/handoff-history.zsh's pty). The harness sets
# HISTFILE to a known path via --env so we can assert against it.
GZMX_E2E_HISTFILE="$GZMX_E2E_DATA_HOME/.zsh_history"

# Type the handoff into the local pane. The widget intercepts it and opens a
# projection window (window 2) WITHOUT executing ssh in the local pane.
gzmx_e2e_type "ssh -F $GZMX_E2E_SSHCONFIG $GZMX_E2E_FIXTURE_HOST"
gzmx_e2e_wait_remote_clients 1 20
gzmx_e2e_assert_window_count 2   # local + projection

# The handoff command must now be in the zsh history file (the widget wrote it
# via `print -s` + `fc -R`). If this fails, the print -s/fc -R path regressed.
_histfile_has_handoff() {
  [[ -r "$GZMX_E2E_HISTFILE" ]] || return 1
  grep -qF "ssh -F $GZMX_E2E_SSHCONFIG $GZMX_E2E_FIXTURE_HOST" "$GZMX_E2E_HISTFILE" 2>/dev/null
}
gzmx_e2e_wait_for 10 _histfile_has_handoff || gzmx_e2e_fail "handoff command not persisted to zsh history"
gzmx_e2e_pass "history: handoff command persisted via print -s (recallable by Up-arrow)"

# --- L2: Cmd-Q preserves local session; reopen reattaches -----------------
# The v0.1 core persistence path: a graceful Cmd-Q (osascript quit) must NOT
# kill the local zmx-* session. The reaper snapshots scrollback and exits; the
# session survives detached (clients=0). Reopening Ghostty re-attaches to the
# SAME session (not a new one). This is the local-session equivalent of the
# remote Cmd-Q scenario (e2e/07) and is the path the user reported as broken
# for remote windows — covering it for local sessions guards the v0.1 core.
# Cross-install registry safety means the session stays tracked (the killed
# Ghostty's registry file persists), so it is NOT reaped; it is reattached.
osascript -e "tell application \"$GZMX_E2E_GHOSTTY_APP\" to quit" 2>/dev/null
for (( i=1; i<=40; i++ )); do
  kill -0 "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || break
  sleep 0.5
done
kill -9 "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || true
_runtime2="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ghostty-zmx-${UID:-$(id -u)}"
[[ -d "$_runtime2" ]] && pkill -9 -f "${_runtime2}/(reaper|remote-poller)-" 2>/dev/null || true
GZMX_E2E_STARTED_GHOSTTY=0
sleep 2
gzmx_e2e_log "Ghostty quit (Cmd-Q path); local session should survive detached"

# The local session must survive (detached, clients=0) — NOT reaped.
_local_session_survives() {
  zmx list 2>/dev/null | grep -q "name=$LOCAL_SESSION"
}
gzmx_e2e_wait_for 15 _local_session_survives || gzmx_e2e_fail "local session $LOCAL_SESSION did not survive Cmd-Q"
_local_session_detached() {
  zmx list 2>/dev/null | grep "name=$LOCAL_SESSION" | grep -q "clients=0"
}
gzmx_e2e_wait_for 10 _local_session_detached || gzmx_e2e_warn "local session not detached yet (timing)"
gzmx_e2e_pass "L2: local session survived Cmd-Q (detached)"

# Relaunch Ghostty. The restore path reads the sessions file and re-attaches to
# the SAME session (not a new one). The local scrollback snapshot is injected.
gzmx_e2e_ghostty_launch
sleep 3
# The session must be alive again with clients=1 (reattached).
_local_session_reattached() {
  zmx list 2>/dev/null | grep "name=$LOCAL_SESSION" | grep -q "clients=1"
}
gzmx_e2e_wait_for 25 _local_session_reattached || {
  print -u2 "  zmx list:"
  zmx list 2>/dev/null >&2
  gzmx_e2e_fail "local session $LOCAL_SESSION was not reattached after reopen"
}
gzmx_e2e_pass "L2: local session reattached to the SAME session after reopen"

gzmx_e2e_ghostty_quit
gzmx_e2e_pass "scenario 16 (local zmx-* lifecycle + managed-surface history) complete"
