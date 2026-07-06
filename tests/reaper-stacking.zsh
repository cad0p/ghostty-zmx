#!/bin/zsh
# Regression test: calling _ghostty_zmx_start_reaper twice for the same
# ghostty pid must NOT stack reapers. The start-lock (reaper-<pid>.lock dir)
# prevents a second start. The instance-lock check must not remove the flag
# on the skip path (the bug that caused stacking).

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state"
export XDG_RUNTIME_DIR="$workdir/runtime"
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$XDG_RUNTIME_DIR"

# Use a fake but live pid (our own $$) as the ghostty pid.
fake_ghostty_pid=$$
pass=0; fail=0

# Source the manager (defines _ghostty_zmx_start_reaper and the lib functions)
source "$repo_dir/session-manager-lib.zsh"
source "$repo_dir/session-manager.zsh" 2>/dev/null

# Stub the actual reaper launch so we don't spawn a real background process.
# We override the part that runs nohup by checking the flag + script generation.
# Instead, call the function and verify the flag is created exactly once.

print "test 1: first start_reaper creates the flag"
_runtime="$(_ghostty_zmx_runtime_dir 2>/dev/null)"
_flag="$_runtime/reaper-${fake_ghostty_pid}.lock"
[[ -d "$_flag" ]] && { print -u2 "  FAIL: flag pre-exists"; fail=$((fail+1)); }

# First call: acquires the instance lock + creates the flag.
# _ghostty_zmx_start_reaper will try to generate a script and nohup it.
# Stub osascript (used by elapsed_seconds) and zmx (not needed here).
osascript() { :; }
# Stub the reaper launch: just don't run nohup. We do this by making the
# generated script a no-op (the function still creates the flag + script).
# Actually, the function calls nohup at the end. We can't easily stub nohup
# in zsh, so we check the flag + lock state after the call instead.
_ghostty_zmx_start_reaper "$fake_ghostty_pid" 2>/dev/null
if [[ -d "$_flag" ]]; then
  print "  ok: flag created by first call"; pass=$((pass+1))
else
  print -u2 "  FAIL: flag not created"; fail=$((fail+1))
fi

print "test 2: second start_reaper does NOT stack (flag already held)"
# Second call: mkdir fails (flag exists) → return 0, no new reaper.
_ghostty_zmx_start_reaper "$fake_ghostty_pid" 2>/dev/null
# The flag should still exist (not removed by the skip path).
if [[ -d "$_flag" ]]; then
  print "  ok: flag preserved by second call (no rmdir on skip)"; pass=$((pass+1))
else
  print -u2 "  FAIL: flag removed by second call (stacking bug)"; fail=$((fail+1))
fi

print "test 3: instance lock held by self (not 'other')"
_lock_file="$GHOSTTY_ZMX_DATA_HOME/instance.lock"
if [[ -f "$_lock_file" ]]; then
  _lock_pid="$(cat "$_lock_file" 2>/dev/null)"
  if [[ "$_lock_pid" == "$fake_ghostty_pid" ]]; then
    print "  ok: instance lock held by self ($_lock_pid)"; pass=$((pass+1))
  else
    print -u2 "  FAIL: instance lock held by $_lock_pid, expected $fake_ghostty_pid"; fail=$((fail+1))
  fi
else
  print -u2 "  FAIL: instance lock not created"; fail=$((fail+1))
fi

# Cleanup: kill any background reaper we spawned
pkill -f "reaper-${fake_ghostty_pid}.zsh" 2>/dev/null || true

print ""
if [[ "$fail" -eq 0 ]]; then
  print "all reaper-stacking tests passed ($pass/$pass)"
  exit 0
else
  print -u2 "$fail test(s) failed"
  exit 1
fi
