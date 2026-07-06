#!/bin/zsh
# Unit tests for the per-install instance lock.
#
# The lock prevents two Ghostty instances from sharing one GHOSTTY_ZMX_DATA_HOME
# (which would corrupt shared state). A dead pid means the prior instance is
# gone and a new one can take over.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data"
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME"

source "$repo_dir/session-manager-lib.zsh"

pass=0; fail=0

# Test 1: no lock → not locked by other
print "test 1: absent lock → not locked by other"
if ghostty_zmx_instance_locked_by_other 11111 2>/dev/null; then
  print -u2 "  FAIL: should not be locked"; fail=$((fail+1))
else
  print "  ok: absent lock → not locked"; pass=$((pass+1))
fi

# Test 2: lock by self → not locked by other
print "test 2: lock by self → not locked by other"
ghostty_zmx_acquire_instance_lock 11111 2>/dev/null
if ghostty_zmx_instance_locked_by_other 11111 2>/dev/null; then
  print -u2 "  FAIL: self-lock should not count as other"; fail=$((fail+1))
else
  print "  ok: self-lock → not locked by other"; pass=$((pass+1))
fi

# Test 3: lock by a dead pid → not locked (can take over)
print "test 3: lock by dead pid → not locked (takeover)"
# Write a lock with a pid that is definitely not alive (999999)
print "999999" > "$GHOSTTY_ZMX_DATA_HOME/instance.lock"
if ghostty_zmx_instance_locked_by_other 11111 2>/dev/null; then
  print -u2 "  FAIL: dead-pid lock should not block"; fail=$((fail+1))
else
  print "  ok: dead-pid lock → can take over"; pass=$((pass+1))
fi

# Test 4: lock by a live pid → locked by other
print "test 4: lock by live pid → locked by other"
# Use our own pid as the "live other" (we are alive)
ghostty_zmx_acquire_instance_lock $$ 2>/dev/null
if ghostty_zmx_instance_locked_by_other 11111 2>/dev/null; then
  print "  ok: live-pid lock → blocked by other"; pass=$((pass+1))
else
  print -u2 "  FAIL: live-pid lock should block"; fail=$((fail+1))
fi

# Test 5: acquire overwrites stale lock
print "test 5: acquire overwrites stale lock"
print "999999" > "$GHOSTTY_ZMX_DATA_HOME/instance.lock"
ghostty_zmx_acquire_instance_lock 22222 2>/dev/null
_readback="$(cat "$GHOSTTY_ZMX_DATA_HOME/instance.lock" 2>/dev/null)"
if [[ "$_readback" == "22222" ]]; then
  print "  ok: stale lock overwritten"; pass=$((pass+1))
else
  print -u2 "  FAIL: expected 22222, got $_readback"; fail=$((fail+1))
fi

print ""
if [[ "$fail" -eq 0 ]]; then
  print "all instance-lock tests passed ($pass/$pass)"
  exit 0
else
  print -u2 "$fail test(s) failed"
  exit 1
fi
