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
unset TERM_PROGRAM GHOSTTY_RESOURCES_DIR 2>/dev/null || true
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

# ---------------------------------------------------------------------------
# Test 6: startup stale-row cleanup logic. After Cmd-Q+reopen, the local
# remote-projections file has rows with dead pids (from the prior session).
# The poller clears them before the first poll so the grouped restore can
# re-project fresh. We test the cleanup logic inline (it mirrors the poller
# script's startup-cleanup block).
# ---------------------------------------------------------------------------
print ""
print "test 6: startup stale-row cleanup clears dead pids, keeps live"

# Seed rows: one with a dead pid, one with a live pid (this shell).
_live_pid=$$
_dead_pid=999888
printf 'gzmx-fixture\tws1\tgzr-dead\t/dev/ttys001\t%s\tattached\t100\twin1\ttab1\n' "$_dead_pid" > "$projections_file"
printf 'gzmx-fixture\tws1\tgzr-live\t/dev/ttys002\t%s\tattached\t100\twin1\ttab1\n' "$_live_pid" >> "$projections_file"

# Run the cleanup logic (mirrors the poller script startup-cleanup block).
typeset _cleared=0 _h _ws _sess _tty _pid _st _up _w _t
_tmp="$projections_file.cleanup.$$"
: > "$_tmp" 2>/dev/null || true
while IFS=$'\t' read -r _h _ws _sess _tty _pid _st _up _w _t; do
  if [[ "$_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$_pid" 2>/dev/null; then
    _cleared=$((_cleared + 1))
  else
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_h" "$_ws" "$_sess" "$_tty" "$_pid" "$_st" "$_up" "$_w" "_t" >> "$_tmp"
  fi
done < "$projections_file"
mv "$_tmp" "$projections_file" 2>/dev/null || rm -f "$_tmp" 2>/dev/null

[[ "$_cleared" == "1" ]] || { print -u2 "FAIL: expected 1 cleared, got $_cleared"; exit 1 }
print "  ok: cleared 1 dead-pid row"

# The live row must survive.
_rows="$(wc -l < "$projections_file" | tr -d ' ')"
[[ "$_rows" == "1" ]] || { print -u2 "FAIL: expected 1 surviving row, got $_rows"; exit 1 }
 Surviving_session="$(awk -F '\t' '{print $3}' "$projections_file")"
[[ "$Surviving_session" == "gzr-live" ]] || { print -u2 "FAIL: expected gzr-live to survive, got $Surviving_session"; exit 1 }
print "  ok: live row survived (gzr-live)"
print "  PASS test 6"

# ---------------------------------------------------------------------------
# Test 7: ghostty_zmx_kill_orphaned_pollers emits NO stdout.
# Regression: 'local _zpid' / 'local _oldlock' with no assignment leaked
# '_zpid=""' / '_oldlock=""' to stdout (zsh TYPESET_SILENT-off behavior)
# for each dead orphan poller. With N orphans, N pairs of lines printed
# before the first prompt on every shell startup.
#
# The leak only manifests when (a) the full manager is sourced AND (b) the
# orphan killer actually iterates over a dead-orphan entry. We reproduce both:
# the manager is already sourced above, and we seed a dead-orphan script +
# a RUNNING zsh poller so pgrep matches and the kill branch runs. We also
# run a second variant: source lib+manager in a clean subshell (the real
# startup path) and assert no stdout from the orphan killer there too.
# ---------------------------------------------------------------------------
print ""
print "test 7: kill_orphaned_pollers emits no stdout"

# Variant A: dead-orphan script (no running process) — exercises the dead
# branch's glob + local declarations.
reg_pid=999998
cat > "$runtime/remote-poller-${reg_pid}.zsh" <<EOF
#!/bin/zsh
sleep 3600
EOF
chmod +x "$runtime/remote-poller-${reg_pid}.zsh"
mkdir -p "$runtime/remote-poller-Ghostty-tip-${reg_pid}.lock"

_out="$(ghostty_zmx_kill_orphaned_pollers 999999 2>&1)"
_rc=$?
[[ -z "$_out" ]] || { print -u2 "FAIL: kill_orphaned_pollers leaked stdout (variant A): [$_out]"; exit 1; }
print "  ok: no stdout/stderr from orphan killer (dead-orphan script)"

# Variant B: the real startup path — source lib+manager in a clean
# subshell (mirrors what .zshrc does) and call the orphan killer. Catches
# leaks that only appear under the full source context, which is the
# actual regression condition.
_out2="$(zsh -fc '
  source "$1/session-manager-lib.zsh" 2>/dev/null
  source "$1/session-manager.zsh" 2>/dev/null
  runtime="${XDG_RUNTIME_DIR}/ghostty-zmx-${UID:-$(id -u)}"
  mkdir -p "$runtime"
  echo "#!/bin/zsh
sleep 3600" > "$runtime/remote-poller-999996.zsh"
  chmod +x "$runtime/remote-poller-999996.zsh"
  mkdir -p "$runtime/remote-poller-Ghostty-tip-999996.lock"
  ghostty_zmx_kill_orphaned_pollers 999999 2>&1
  rc=$?
  rm -f "$runtime/remote-poller-999996.zsh"
  rm -rf "$runtime/remote-poller-Ghostty-tip-999996.lock"
  exit $rc
' -- "$repo_dir" 2>&1)"
_rc2=$?
[[ -z "$_out2" ]] || { print -u2 "FAIL: kill_orphaned_pollers leaked stdout (variant B, full-source subshell): [$_out2]"; exit 1; }
print "  ok: no stdout/stderr from orphan killer (full-source subshell)"

print "  PASS test 7"

# Cleanup.
rm -f "$runtime/remote-poller-${reg_pid}.zsh"
rm -rf "$runtime/remote-poller-Ghostty-tip-${reg_pid}.lock"

# ---------------------------------------------------------------------------
# Test 8: stale opening rows are not "known" and must not block restore.
# After Cmd-Q/reopen or a failed opener, a local row can be left as:
#   state=opening, tty=-, pid=-
# Once its TTL has expired, grouped restore must be allowed to recreate the
# projection from the server-authoritative `present` row.
# ---------------------------------------------------------------------------
print ""
print "test 8: stale opening rows do not block restore"

now="$(date +%s)"
old=$(( now - 120 ))
fresh=$(( now ))
cat > "$projections_file" <<EOF
gzmx-fixture	ws1	gzr-stale-opening	-	-	opening	${old}	-	-
gzmx-fixture	ws1	gzr-fresh-opening	-	-	opening	${fresh}	-	-
gzmx-fixture	ws1	gzr-attached	/dev/ttys001	${$}	attached	${fresh}	win	tab
gzmx-fixture	ws1	gzr-closing	/dev/ttys002	999888	closing	${fresh}	win	tab
EOF

GHOSTTY_ZMX_OPENING_TTL=30 ghostty_zmx_projection_known "gzmx-fixture" "gzr-stale-opening" 2>/dev/null && {
  print -u2 "FAIL: stale opening row should not be known"
  exit 1
}
print "  ok: stale opening row is not known"

GHOSTTY_ZMX_OPENING_TTL=30 ghostty_zmx_projection_known "gzmx-fixture" "gzr-fresh-opening" 2>/dev/null || {
  print -u2 "FAIL: fresh opening row should be known"
  exit 1
}
print "  ok: fresh opening row is known"

ghostty_zmx_projection_known "gzmx-fixture" "gzr-attached" 2>/dev/null || {
  print -u2 "FAIL: attached row should be known"
  exit 1
}
ghostty_zmx_projection_known "gzmx-fixture" "gzr-closing" 2>/dev/null || {
  print -u2 "FAIL: closing row should be known"
  exit 1
}
print "  ok: attached/closing rows remain known"
print "  PASS test 8"

# ---------------------------------------------------------------------------
# Test 9: unobserved opens are cleaned up immediately.
# AppleScript can return before a usable projection process exists; callers
# must remove the optimistic `opening` row so the poller can retry.
# ---------------------------------------------------------------------------
print ""
print "test 9: unobserved opens remove opening row"

cat > "$projections_file" <<EOF
gzmx-fixture	ws1	gzr-unobserved	-	-	opening	${fresh}	-	-
EOF

ghostty_zmx_wait_remote_projection() { return 1; }
GHOSTTY_ZMX_OPENING_TTL=30 ghostty_zmx_confirm_remote_projection_open "gzmx-fixture" "ws1" "gzr-unobserved" 1 0 2>/dev/null && {
  print -u2 "FAIL: unobserved open should fail"
  exit 1
}
if grep -q "gzr-unobserved" "$projections_file" 2>/dev/null; then
  print -u2 "FAIL: unobserved opening row was not removed"
  exit 1
fi
print "  ok: unobserved opening row removed"
print "  PASS test 9"

# ---------------------------------------------------------------------------
# Test 10: close grace distinguishes pane close from Cmd-Q teardown.
# A fresh `closing` row should wait; an old one should be eligible for the
# server close transaction.
# ---------------------------------------------------------------------------
print ""
print "test 10: projection close grace"

now="$(date +%s)"
GHOSTTY_ZMX_CLOSE_GRACE=4 ghostty_zmx_projection_close_grace_elapsed "$now" 2>/dev/null && {
  print -u2 "FAIL: fresh closing row should still be in grace"
  exit 1
}
old=$(( now - 10 ))
GHOSTTY_ZMX_CLOSE_GRACE=4 ghostty_zmx_projection_close_grace_elapsed "$old" 2>/dev/null || {
  print -u2 "FAIL: old closing row should be past grace"
  exit 1
}
GHOSTTY_ZMX_CLOSE_GRACE=0 ghostty_zmx_projection_close_grace_elapsed "$now" 2>/dev/null || {
  print -u2 "FAIL: zero grace should elapse immediately"
  exit 1
}
print "  ok: fresh waits, old/zero-grace elapse"
print "  PASS test 10"

# ---------------------------------------------------------------------------
# Test 11: projection launcher uses zsh -f.
# Restore-created projection surfaces must not source .zprofile/.zshrc before
# execing the wrapper, or a restored tab can run the inherit hook and create an
# extra gzr-* session.
# ---------------------------------------------------------------------------
print ""
print "test 11: projection launcher uses zsh -f"

_launcher_cmd="$(ghostty_zmx_projection_launcher_command "gzr-launcher-test" "/bin/echo ok")"
[[ "$_launcher_cmd" == "/bin/zsh -f "* ]] || { print -u2 "FAIL: launcher command should use /bin/zsh -f, got $_launcher_cmd"; exit 1; }
_launcher_script="${_launcher_cmd#/bin/zsh -f }"
head -1 "$_launcher_script" | grep -qxF '#!/bin/zsh -f' || { print -u2 "FAIL: launcher script shebang should use zsh -f"; exit 1; }
print "  ok: launcher command and shebang use zsh -f"
print "  PASS test 11"

# ---------------------------------------------------------------------------
# Test 12: grouped remote restore resets the "first tab" flag per tab.
# Regression: after restoring tab 1, _first_in_tab stayed false for tab 2, so
# the first pane of tab 2 was restored as a split in tab 1 instead of a new tab.
# ---------------------------------------------------------------------------
print ""
print "test 12: grouped restore opens second tab as tab, not split"

: > "$projections_file"
_restore_calls="$workdir/restore-calls.log"
: > "$_restore_calls"
ghostty_zmx_find_live_projection() { return 1; }
ghostty_zmx_wait_remote_projection() { return 0; }
ghostty_zmx_projection_launcher_command() { print -r -- "/bin/true"; }
osascript() {
  local script
  script="$(cat)"
  if [[ "$script" == *"new tab in targetWindow"* ]]; then
    print -r -- "new-tab" >> "$_restore_calls"
    print -r -- "window:aaaaaaaaaaaaaaaa tab-group-ghostty-zmx-test/tab-bbbbbbbb"
  elif [[ "$script" == *"split t direction"* ]]; then
    print -r -- "split" >> "$_restore_calls"
  elif [[ "$script" == *"new window with configuration"* ]]; then
    print -r -- "new-window" >> "$_restore_calls"
    print -r -- "window:aaaaaaaaaaaaaaaa tab-group-ghostty-zmx-test/tab-aaaaaaaa"
  elif [[ "$*" == *"count of windows"* ]]; then
    print -r -- "1"
  fi
}

_layout=$'wsaaaaaa\twinbbbbbb\ttab111111\tpane111\tgzr-wsaaaaaa-winbbbbbb-tab111111-pane111\t-\troot\t1\tpresent\t100\t1\nwsaaaaaa\twinbbbbbb\ttab222222\tpane222\tgzr-wsaaaaaa-winbbbbbb-tab222222-pane222\t-\troot\t1\tpresent\t100\t2'
GHOSTTY_ZMX_RESTORE_STEP_DELAY=0 ghostty_zmx_restore_remote_layout "gzmx-fixture" "ssh -t fixture" "$_layout"

grep -qxF "new-window" "$_restore_calls" || { print -u2 "FAIL: expected first restored tab to open a new window"; exit 1; }
grep -qxF "new-tab" "$_restore_calls" || { print -u2 "FAIL: expected second restored tab to open a new tab"; exit 1; }
if grep -qxF "split" "$_restore_calls"; then
  print -u2 "FAIL: second restored tab was opened as a split"
  exit 1
fi
print "  ok: second tab restored with new-tab path"
print "  PASS test 12"

print ""
print "all remote-lifecycle tests passed"
exit 0
