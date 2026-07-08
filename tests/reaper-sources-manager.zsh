#!/bin/zsh
# Regression test for issue #39: the reaper sources the manager
# (GHOSTTY_ZMX_INTERNAL_REAPER=1 guard) and reuses its helpers instead of
# inlining ~20 duplicated copies. The pre-refactor reaper's inlined debug_log
# called _ghostty_zmx_debug_rotate (a lib function) which was never defined
# in the reaper heredoc, so debug-log rotation never fired for the reaper —
# the highest-volume debug-log writer. Sourcing the manager makes that class
# of "lib helper undefined in reaper" bug impossible by construction.
#
# These are behavioral tests: they source the manager under the REAPER guard
# and assert the helpers are defined; then they generate the real reaper
# script via _ghostty_zmx_start_reaper and run it, asserting it executes the
# reap loop without undefined-function errors and actually reaps a detached
# session (snapshot → kill → cleanup_log → forget_snapshot).

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state"
export XDG_RUNTIME_DIR="$workdir/runtime"
export TERM_PROGRAM=ghostty
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$XDG_RUNTIME_DIR"

# Use a fake but live pid (our own $$) as the ghostty pid.
fake_ghostty_pid=$$
pass=0; fail=0

# Source the lib first, then stub the 1.4.0 tty/pid capability probe so the
# manager's version-self-gate does not early-return (same shape as
# tests/reaper-stacking.zsh).
source "$repo_dir/session-manager-lib.zsh"
ghostty_zmx_has_tty_capability() { return 0; }

# Test 1: under GHOSTTY_ZMX_INTERNAL_REAPER=1, the manager defines all
# functions and returns before widget install / auto-attach.
print "test 1: manager returns early under GHOSTTY_ZMX_INTERNAL_REAPER=1"
_reaper_auto_attach_ran=0
_ghostty_zmx_auto_attach() { _reaper_auto_attach_ran=1; }
GHOSTTY_ZMX_INTERNAL_REAPER=1 source "$repo_dir/session-manager.zsh"
if [[ "$_reaper_auto_attach_ran" == "0" ]]; then
  print "  ok: auto-attach not called under REAPER guard"; pass=$((pass+1))
else
  print -u2 "  FAIL: auto-attach ran under REAPER guard"; fail=$((fail+1))
fi

# Test 2: every helper the reaper body calls is defined after sourcing the
# manager under the REAPER guard. This is the direct regression check for the
# issue #39 bug: _ghostty_zmx_debug_rotate must be defined (it was not, in
# the pre-refactor reaper heredoc).
print ""
print "test 2: all reaper helpers defined after sourcing manager under REAPER guard"
helpers=(
  _ghostty_zmx_debug_rotate
  _ghostty_zmx_snapshot_history
  _ghostty_zmx_cleanup_log
  _ghostty_zmx_forget_snapshot
  _ghostty_zmx_managed_detached_sessions
  _ghostty_zmx_managed_disappeared_sessions
  _ghostty_zmx_managed_existing_sessions
  _ghostty_zmx_snapshot_existing_sessions
  _ghostty_zmx_cleanup_detached_session
  _ghostty_zmx_registry_heartbeat
  _ghostty_zmx_parse_elapsed_seconds
  _ghostty_zmx_ghostty_elapsed_seconds
  _ghostty_zmx_debug
  _ghostty_zmx_managed_sessions_from_log
  _ghostty_zmx_current_terminal_ttys
  _ghostty_zmx_registry_tracked_sessions
  _ghostty_zmx_valid_session_name
  _ghostty_zmx_sessions_file
  _ghostty_zmx_tty_map_file
  _ghostty_zmx_history_file_for_session
  _ghostty_zmx_cleanup_tty_map
)
missing=0
for h in "${helpers[@]}"; do
  if (( ! $+functions[$h] )); then
    print -u2 "  FAIL: $h not defined"
    missing=$((missing + 1))
  fi
done
if [[ "$missing" == "0" ]]; then
  print "  ok: all ${#helpers[@]} reaper helpers defined"; pass=$((pass+1))
else
  print -u2 "  $missing helper(s) missing"; fail=$((fail+1))
fi

# Test 3: the generated reaper script runs the reap loop without
# undefined-function errors and writes debug lines (proves _reaper_debug +
# _ghostty_zmx_debug_rotate work end-to-end). This generates the REAL reaper
# script via _ghostty_zmx_start_reaper and lets it run.
print ""
print "test 3: generated reaper runs without undefined-function errors"
# Stub osascript (reaper uses it for window counting + elapsed probe) and zmx.
osascript() { print "1"; }
mkdir -p "$workdir/bin"
cat > "$workdir/bin/zmx" <<'STUB'
#!/bin/zsh
case "$1 $2" in
  "list ") print "name=zmx-aaaaaaaaaaaa-bbbbbbbb-1234abcd	pid=111	clients=0	created=1	start_dir=/h" ;;
  "list --short") print "zmx-aaaaaaaaaaaa-bbbbbbbb-1234abcd" ;;
  "kill "*) ;;
  "history "*) ;;
esac
STUB
chmod +x "$workdir/bin/zmx"
export PATH="$workdir/bin:$PATH"
# Re-source the manager (full, not REAPER guard) so _ghostty_zmx_start_reaper
# is available. GHOSTTY_ZMX_DEBUG=1 so the reaper writes debug lines.
export GHOSTTY_ZMX_DEBUG=1
export GHOSTTY_ZMX_SCROLLBACK_LINES=1000
export GHOSTTY_ZMX_REAPER_INTERVAL=0.2
export GHOSTTY_ZMX_ZERO_WINDOWS_GRACE=1
export GHOSTTY_ZMX_INSTALL_DIR="$repo_dir"
source "$repo_dir/session-manager.zsh"
_ghostty_zmx_reaper_startup_delay=0.2
_ghostty_zmx_start_reaper "$fake_ghostty_pid" 2>/dev/null
_runtime="$(_ghostty_zmx_runtime_dir 2>/dev/null)"
_reaper_script="$_runtime/reaper-${fake_ghostty_pid}.zsh"
_reaper_log="$_runtime/reaper-${fake_ghostty_pid}.log"
[[ -f "$_reaper_script" ]] || { print -u2 "  FAIL: reaper script not generated"; fail=$((fail+1)); }
# Let the reaper run ~1s (5 iterations at interval=0.2), then kill it.
sleep 1
pkill -f "reaper-${fake_ghostty_pid}.zsh" 2>/dev/null || true
sleep 0.3
_debug_log="$GHOSTTY_ZMX_STATE_HOME/debug.log"
# No undefined-function errors in the reaper log.
if [[ -f "$_reaper_log" ]] && grep -qi "command not found\|undefined" "$_reaper_log"; then
  print -u2 "  FAIL: reaper log has undefined-function errors:"; cat "$_reaper_log"; fail=$((fail+1))
elif [[ ! -f "$_debug_log" ]] || ! grep -q "reaper " "$_debug_log"; then
  print -u2 "  FAIL: no reaper debug lines (debug_log / _reaper_debug broken)"; fail=$((fail+1))
else
  print "  ok: reaper ran, wrote debug lines, no undefined-function errors"; pass=$((pass+1))
fi
# Clean up everything test 3 created so test 4 starts from a clean slate:
# - kill the reaper process (already done above, but be defensive)
# - remove the reaper script (written with noclobber by _ghostty_zmx_start_reaper;
#   a leftover would make a later start_reaper for the same pid silently return
#   without generating a new script)
# - remove the start-lock flag dir + instance lock (a leftover flag would make a
#   later start_reaper skip via the mkdir guard)
# - clear data/state homes + the cross-install registry so test 4's seeded
#   session is not registry-tracked (managed_detached_sessions skips
#   registry-tracked sessions, which would suppress the startup sweep)
pkill -f "reaper-${fake_ghostty_pid}.zsh" 2>/dev/null || true
rm -f "$_runtime/reaper-${fake_ghostty_pid}.zsh" 2>/dev/null || true
rmdir "$_runtime/reaper-${fake_ghostty_pid}.lock" 2>/dev/null || true
rm -f "$GHOSTTY_ZMX_DATA_HOME/instance.lock" 2>/dev/null || true
rm -rf "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$HOME/.local/state/ghostty-zmx"
mkdir -p "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME"

# Test 4: the reaper actually reaps a detached session — snapshot → kill →
# cleanup_log → forget_snapshot. Seed a managed detached session and verify
# the startup orphan sweep cleans it up. Test 3 cleaned up after itself, so
# this starts from a clean slate.
print ""
print "test 4: reaper startup sweep reaps a detached session"
# Reuse $$ as the fake pid; test 3 removed its script + flag so start_reaper
# will generate a fresh script.
fake_ghostty_pid2=$$
SESSION="zmx-aaaaaaaaaaaa-bbbbbbbb-1234abcd"
cat > "$workdir/bin/zmx" <<STUB
#!/bin/zsh
case "\$1 \$2" in
  "list ") print "name=$SESSION	pid=111	clients=0	created=1	start_dir=/h" ;;
  "list --short") print "$SESSION" ;;
  "kill "*) ;;
  "history "*) print "line1"; print "line2"; print "line3" ;;
esac
STUB
chmod +x "$workdir/bin/zmx"
# Seed the sessions log + tty-map so the reaper sees the session as managed.
print -r -- "$SESSION" >> "$GHOSTTY_ZMX_DATA_HOME/sessions"
print -r -- "S	$SESSION	/dev/ttys999	12345" >> "$GHOSTTY_ZMX_DATA_HOME/tty-map"
_ghostty_zmx_reaper_startup_delay=0.2
_ghostty_zmx_start_reaper "$fake_ghostty_pid2" 2>/dev/null
# Let the reaper run ~1.5s so the startup sweep fires.
sleep 1.5
pkill -f "reaper-${fake_ghostty_pid2}.zsh" 2>/dev/null || true
sleep 0.3
_debug_log="$GHOSTTY_ZMX_STATE_HOME/debug.log"
_swept=0
grep -q "startup-orphan-sweep session=$SESSION" "$_debug_log" 2>/dev/null && _swept=1
if [[ "$_swept" == "1" ]]; then
  print "  ok: startup-orphan-sweep ran for $SESSION"; pass=$((pass+1))
else
  print -u2 "  FAIL: startup-orphan-sweep did not log for $SESSION"; fail=$((fail+1))
fi
# cleanup_log removed the session from the sessions log.
if grep -qxF "$SESSION" "$GHOSTTY_ZMX_DATA_HOME/sessions" 2>/dev/null; then
  print -u2 "  FAIL: session still in sessions log (cleanup_log did not run)"; fail=$((fail+1))
else
  print "  ok: session removed from sessions log (cleanup_log ran)"; pass=$((pass+1))
fi
# forget_snapshot deleted the snapshot file.
if [[ -f "$GHOSTTY_ZMX_STATE_HOME/history/${SESSION}.txt" ]]; then
  print -u2 "  FAIL: snapshot file still exists (forget_snapshot did not run)"; fail=$((fail+1))
else
  print "  ok: snapshot forgotten (forget_snapshot ran)"; pass=$((pass+1))
fi
pkill -f "reaper-${fake_ghostty_pid2}.zsh" 2>/dev/null || true

print ""
if [[ "$fail" == "0" ]]; then
  print "all reaper-sources-manager tests passed ($pass/$pass)"
  exit 0
else
  print -u2 "$fail test(s) failed"
  exit 1
fi
