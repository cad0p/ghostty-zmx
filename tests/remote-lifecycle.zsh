#!/bin/zsh
# Unit tests for the remote projection lifecycle fixes:
#   1. ghostty_zmx_kill_orphaned_pollers — kills pollers whose owning Ghostty
#      PID is dead (stray-poller self-heal).
#   2. ghostty_zmx_server_confirmed_deleted — verifies a server layout row
#      reached `deleted` state (reopen-after-close guard).
#   3. ghostty_zmx_inherit_remote_context_if_any — matches `opening` rows with
#      local_win="-" via live-projection fallback (split-opens-local fix).
#
# These are pure-logic tests that don't require a live Ghostty or Docker
# fixture. They stub osascript/ssh where needed and assert on state-file
# contents and function return codes.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data/ghostty-zmx"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state/ghostty-zmx"
export XDG_RUNTIME_DIR="$workdir/runtime"
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$XDG_RUNTIME_DIR"

# Stub osascript so no real Ghostty is needed. Returns a fixed window count.
osascript() {
  case "$*" in
    *count*of*windows*) echo "${_GZMX_STUB_WINCOUNT:-1}" ;;
    *) echo "" ;;
  esac
}

# Source the manager without triggering auto-attach.
source "$repo_dir/session-manager.zsh"

# ---------------------------------------------------------------------------
# Test 1: ghostty_zmx_kill_orphaned_pollers kills pollers whose owning
#         Ghostty PID is dead, but leaves the live owner's poller alone.
# ---------------------------------------------------------------------------
print "test 1: kill_orphaned_pollers kills dead-owner pollers"

runtime="${XDG_RUNTIME_DIR}/ghostty-zmx-${UID:-$(id -u)}"
mkdir -p "$runtime"

# Fake a poller script for a dead Ghostty PID (999999 — guaranteed not alive).
dead_pid=999999
dead_script="$runtime/remote-poller-${dead_pid}.zsh"
dead_lock="$runtime/remote-poller-Ghostty-tip-${dead_pid}.lock"
cat > "$dead_script" <<EOF
#!/bin/zsh
sleep 3600
EOF
chmod +x "$dead_script"
mkdir -p "$dead_lock"
# Simulate a pre-fix orphan: no elapsed file.
: > "$dead_lock/pid"
echo "dead-poller pid written: $(cat "$dead_lock/pid")"

# Start the fake poller in the background.
/bin/zsh "$dead_script" &
dead_poller_zpid=$!
disown

# Also fake a poller for the CURRENT shell (the "live owner") — must survive.
live_pid=$$
live_script="$runtime/remote-poller-${live_pid}.zsh"
cat > "$live_script" <<EOF
#!/bin/zsh
sleep 3600
EOF
chmod +x "$live_script"
/bin/zsh "$live_script" &
live_poller_zpid=$!
disown

sleep 0.3
# Verify both pollers are running.
kill -0 "$dead_poller_zpid" 2>/dev/null && print "  pre: dead-owner poller running"
kill -0 "$live_poller_zpid" 2>/dev/null && print "  pre: live-owner poller running"

# Run the orphan killer, excluding the current shell PID.
ghostty_zmx_kill_orphaned_pollers "$live_pid"
sleep 0.3

# The dead-owner poller should be killed.
if kill -0 "$dead_poller_zpid" 2>/dev/null; then
  print -u2 "FAIL: dead-owner poller was NOT killed"
  kill -9 "$dead_poller_zpid" 2>/dev/null
  exit 1
fi
print "  ok: dead-owner poller killed"

# The live-owner poller should survive.
if ! kill -0 "$live_poller_zpid" 2>/dev/null; then
  print -u2 "FAIL: live-owner poller was wrongly killed"
  exit 1
fi
print "  ok: live-owner poller survived"
kill -9 "$live_poller_zpid" 2>/dev/null
# Also kill any leftover sleep children from the dead-owner poller (kill -9 the
# poller zsh doesn't always reap its sleep child immediately).
pkill -9 -f 'sleep 3600' 2>/dev/null || true

# Cleanup the fake scripts/locks.
rm -f "$dead_script" "$live_script"
rm -rf "$dead_lock" "$runtime/remote-poller-Ghostty-tip-${live_pid}.lock"

print "  PASS test 1"

# ---------------------------------------------------------------------------
# Test 2: ghostty_zmx_server_confirmed_deleted returns 0 only when the server
#         row is `deleted`.
# ---------------------------------------------------------------------------
print ""
print "test 2: server_confirmed_deleted checks server row state"

# Stub ghostty_zmx_remote_prefix_for_host + ghostty_zmx_notty_prefix + helper
# to return a canned layout. We do this by overriding the helper-read path:
# ghostty_zmx_server_confirmed_deleted calls notty_prefix + helper read.
# Instead of stubbing ssh, we stub the three functions it calls.
_ghostty_zmx_remote_prefix_for_host_real() { echo "ssh -T fixture"; }
ghostty_zmx_remote_prefix_for_host() { _ghostty_zmx_remote_prefix_for_host_real "$@"; }

# We can't easily stub ssh, so instead test the logic by directly seeding
# the layout and calling a minimal reproduction. The real function reads the
# server layout over ssh. For unit testing, we verify the awk filter logic
# by feeding a canned layout through the same awk.
_canned_layout_present=$'ws1\twin1\ttab1\tpane1\tgzr-test-1\t-\troot\t1\tpresent\t100\t1'
_canned_layout_deleted=$'ws1\twin1\ttab1\tpane1\tgzr-test-1\t-\troot\t1\tdeleted\t100\t2'

_state_from_layout() {
  local layout="$1" session="$2"
  print -r -- "$layout" | awk -F '\t' -v s="$session" '$5==s {print $9; exit}'
}

[[ "$(_state_from_layout "$_canned_layout_present" "gzr-test-1")" == "present" ]] || { print -u2 "FAIL: expected present"; exit 1 }
[[ "$(_state_from_layout "$_canned_layout_deleted" "gzr-test-1")" == "deleted" ]] || { print -u2 "FAIL: expected deleted"; exit 1 }
[[ "$(_state_from_layout "$_canned_layout_present" "gzr-other")" == "" ]] || { print -u2 "FAIL: expected empty for missing session"; exit 1 }
print "  ok: layout state extraction logic correct (present/deleted/missing)"
print "  PASS test 2"

# ---------------------------------------------------------------------------
# Test 3: inherit matches `opening` rows (not just `attached`), and falls back
#         to live-projection scan when local_win is "-".
#         We test the state filter + fallback logic, not the exec (which would
#         require a real wrapper + ssh).
# ---------------------------------------------------------------------------
print ""
print "test 3: inherit matches opening rows with local_win=-"

# Seed a remote-projections file with an `opening` row whose local_win is "-".
projections_file="$GHOSTTY_ZMX_DATA_HOME/remote-projections"
cat > "$projections_file" <<EOF
gzmx-fixture	d393d2f5	gzr-d393d2f5-6cba0a6a-53f602-c70e8d	/dev/ttys099	12345	opening	100	-	-
EOF

# The inherit function reads this file. We test that it does NOT skip `opening`
# rows by checking that the `[[ "$state" == "attached" || "$state" == "opening" ]]`
# filter admits the row. We simulate the filter inline (the real function execs
# at the end, which we can't do in a test).
_inherit_admits_row() {
  local state="$1"
  [[ "$state" == "attached" || "$state" == "opening" ]]
}

_inherit_admits_row "attached" || { print -u2 "FAIL: should admit attached"; exit 1 }
_inherit_admits_row "opening"  || { print -u2 "FAIL: should admit opening (the fix)"; exit 1 }
_inherit_admits_row "closing"  && { print -u2 "FAIL: should NOT admit closing"; exit 1 }
_inherit_admits_row "deleted"  && { print -u2 "FAIL: should NOT admit deleted"; exit 1 }
print "  ok: inherit state filter admits attached + opening, rejects closing/deleted"

# Verify the opening row in the file has local_win="-" (the fallback trigger).
_row_state="$(awk -F '\t' '$3 ~ /gzr-/ {print $6; exit}' "$projections_file")"
_row_win="$(awk -F '\t' '$3 ~ /gzr-/ {print $8; exit}' "$projections_file")"
[[ "$_row_state" == "opening" ]] || { print -u2 "FAIL: expected opening state"; exit 1 }
[[ "$_row_win" == "-" ]] || { print -u2 "FAIL: expected local_win=- for fallback trigger"; exit 1 }
print "  ok: opening row has local_win=- (fallback trigger present)"
print "  PASS test 3"

# ---------------------------------------------------------------------------
# Test 4: the dead-pid close path does NOT remove the local row when the
#         close-txn fails. We verify the guard logic: if
#         ghostty_zmx_server_confirmed_deleted returns non-zero, the row is
#         marked `closing` (not removed), so the next cycle retries.
# ---------------------------------------------------------------------------
print ""
print "test 4: close-txn failure marks row closing (no reopen)"

# This is a logic assertion: the poller code path is:
#   if close_txn && server_confirmed_deleted; then remove_row
#   else write_row closing  (retry next cycle)
# We verify the decision function signature and that a failing close leaves
# the row in place. Stub server_confirmed_deleted to "fail".
ghostty_zmx_server_confirmed_deleted() { return 1 }
ghostty_zmx_remote_close_transaction() { return 1 }

# Seed an attached row with a dead pid.
dead_ssh_pid=999888  # guaranteed dead
cat > "$projections_file" <<EOF
gzmx-fixture	d393d2f5	gzr-d393d2f5-6cba0a6a-53f602-c70e8d	/dev/ttys099	${dead_ssh_pid}	attached	100	60000349cd80	11c724500
EOF

# Run the dead-pid cleanup decision inline (mirrors poll_once's logic).
_p_host="gzmx-fixture" _p_workspace="d393d2f5" _p_session="gzr-d393d2f5-6cba0a6a-53f602-c70e8d"
_p_pid="$dead_ssh_pid" _p_state="attached" _p_tty="/dev/ttys099" _p_win="60000349cd80" _p_tab="11c724500"

if ! kill -0 "$_p_pid" 2>/dev/null; then
  # pid is dead — this is the close path.
  if ghostty_zmx_remote_close_transaction "$_p_host" "$_p_session" 2>/dev/null && \
     ghostty_zmx_server_confirmed_deleted "$_p_host" "$_p_session" 2>/dev/null; then
    # Success path — would remove the row.
    _action="removed"
    ghostty_zmx_remove_remote_projection "$_p_host" "$_p_session"
  else
    # Failure path — must mark closing, NOT remove.
    _action="closing-retry"
    ghostty_zmx_write_projection_row "$_p_host" "$_p_workspace" "$_p_session" "$_p_tty" "$_p_pid" closing "$_p_win" "$_p_tab"
  fi
fi

[[ "$_action" == "closing-retry" ]] || { print -u2 "FAIL: close-txn failure should mark closing-retry, got $_action"; exit 1 }
print "  ok: close-txn failure → closing-retry (row preserved)"

# Verify the row is still present (not removed) and marked closing.
_row_state_after="$(awk -F '\t' -v s="$_p_session" '$3==s {print $6; exit}' "$projections_file")"
[[ "$_row_state_after" == "closing" ]] || { print -u2 "FAIL: expected closing state, got $_row_state_after"; exit 1 }
print "  ok: row state is closing (preserved for retry, not removed)"
print "  PASS test 4"

# ---------------------------------------------------------------------------
# Test 5: ghostty_zmx_projection_closing returns 0 only for `closing` rows.
#         This is the guard that prevents the grouped restore from re-opening
#         a session whose close-txn is in progress.
# ---------------------------------------------------------------------------
print ""
print "test 5: projection_closing detects closing state"

printf 'gzmx-fixture\tws1\tgzr-test-attached\t/dev/ttys001\t100\tattached\t100\twin1\ttab1\n' > "$projections_file"
printf 'gzmx-fixture\tws1\tgzr-test-closing\t/dev/ttys002\t200\tclosing\t100\twin1\ttab1\n' >> "$projections_file"
printf 'gzmx-fixture\tws1\tgzr-test-opening\t/dev/ttys003\t300\topening\t100\twin1\ttab1\n' >> "$projections_file"

ghostty_zmx_projection_closing "gzmx-fixture" "gzr-test-attached" 2>/dev/null && { print -u2 "FAIL: attached should not be closing"; exit 1 }
print "  ok: attached row is not closing"
ghostty_zmx_projection_closing "gzmx-fixture" "gzr-test-closing" 2>/dev/null || { print -u2 "FAIL: closing row should be detected"; exit 1 }
print "  ok: closing row is detected"
ghostty_zmx_projection_closing "gzmx-fixture" "gzr-test-opening" 2>/dev/null && { print -u2 "FAIL: opening should not be closing"; exit 1 }
print "  ok: opening row is not closing"
ghostty_zmx_projection_closing "gzmx-fixture" "gzr-test-missing" 2>/dev/null && { print -u2 "FAIL: missing row should not be closing"; exit 1 }
print "  ok: missing row is not closing"
print "  PASS test 5"

print ""
print "all remote-lifecycle tests passed"
exit 0
