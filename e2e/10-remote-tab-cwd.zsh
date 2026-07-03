#!/bin/zsh
# E2E 10 — remote cwd query uses /proc/<pid>/cwd (live cwd, not start_dir).
#
# The inherit path (ghostty_zmx_inherit_remote_context_if_any) queries the
# parent remote session's current cwd so a new split/tab starts in the same
# directory (matches Ghostty's split-inherit-working-directory /
# tab-inherit-working-directory for remote panes).
#
# The original implementation used `zmx run <parent> pwd`, but `zmx run`
# output over `ssh -T` is the remote-shell echo / zmx binary path, not the
# PTY pwd output — unreliable and wrong (it matched the zmx binary path).
# The fix uses `zmx list` to get the session pid, then
# `readlink /proc/<pid>/cwd` for the LIVE cwd (Linux-only, matching the
# design doc's remote-host scope).
#
# This scenario verifies the readlink query returns a valid absolute path
# for a live projection session, distinct from the zmx binary path (the
# original bug). It does not require typing into the projection pane (which
# is harness-fragile); it queries the session created by the projection.
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

# Capture the parent session name + the probed zmx path.
local parent_session="$(awk -F '\t' -v h="$GZMX_E2E_FIXTURE_HOST" '$1 == h { print $3 }' "$GZMX_E2E_DATA_HOME/remote-projections" 2>/dev/null | head -1)"
[[ -n "$parent_session" ]] || gzmx_e2e_fail "no parent projection recorded"
local remote_zmx="$(awk -F '\t' -v h="$GZMX_E2E_FIXTURE_HOST" '$1 == h { print $6 }' "$GZMX_E2E_DATA_HOME/remote-hosts" 2>/dev/null)"
[[ -n "$remote_zmx" ]] || remote_zmx="zmx"
gzmx_e2e_log "parent=$parent_session remote_zmx=$remote_zmx"

# Query the session pid via zmx list.
local -a ssh_argv
ssh_argv=(ssh -T -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST")
local list_out pid live_cwd
list_out="$("${ssh_argv[@]}" "$remote_zmx list" 2>/dev/null)"
pid="$(print -r -- "$list_out" | tr -d '\r' | awk -v n="name=$parent_session" '
  { for (i=1; i<=NF; i++) if ($i == n) {
    for (j=i; j<=NF; j++) if ($j ~ /^pid=/) { sub(/^pid=/, "", $j); print $j; exit }
  } }')"
[[ "$pid" =~ ^[0-9]+$ ]] || gzmx_e2e_fail "could not parse pid from zmx list (got: $(print -r -- "$list_out" | head -3))"

# readlink /proc/<pid>/cwd must return a valid absolute path.
live_cwd="$("${ssh_argv[@]}" "readlink /proc/$pid/cwd" 2>/dev/null)"
live_cwd="$(print -r -- "$live_cwd" | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
[[ "$live_cwd" == /* ]] || gzmx_e2e_fail "readlink did not return an absolute path: '$live_cwd'"

# CRITICAL: the live cwd must NOT be the zmx binary path (the original bug
# where `zmx run pwd` matched the zmx binary path from the remote-shell echo).
[[ "$live_cwd" != "$remote_zmx" ]] \
  || gzmx_e2e_fail "live cwd equals the zmx binary path ($remote_zmx) — the original zmx-run-pwd bug is back"

# The live cwd should be the remote home (the projection's shell starts at ~).
[[ "$live_cwd" == "/home/gzmx" ]] \
  || gzmx_e2e_warn "live cwd is $live_cwd (expected /home/gzmx for a fresh projection)"

gzmx_e2e_log "pid=$pid live_cwd=$live_cwd (readlink returns LIVE cwd, not the zmx binary path)"

gzmx_e2e_pass "scenario 10 (remote cwd query via /proc/<pid>/cwd) complete"
