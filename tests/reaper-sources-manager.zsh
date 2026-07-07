#!/bin/zsh
# Regression test for issue #39: the reaper must source the manager
# (GHOSTTY_ZMX_INTERNAL_REAPER=1 guard) and have every helper it calls
# defined. The pre-refactor reaper inlined ~20 helpers in its heredoc; the
# inlined debug_log called _ghostty_zmx_debug_rotate (a lib function) which
# was never defined in the reaper, so debug-log rotation never fired for the
# reaper — the highest-volume debug-log writer. Sourcing the manager makes
# that class of bug impossible by construction.
#
# This test sources the manager under the REAPER guard (exactly what the
# generated reaper script does) and asserts every helper the reaper body
# calls is defined. It also generates the real reaper script via
# _ghostty_zmx_start_reaper and syntax-checks it.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state"
export XDG_RUNTIME_DIR="$workdir/runtime"
export GHOSTTY_ZMX_DEBUG=1
export GHOSTTY_ZMX_SCROLLBACK_LINES=1000
export GHOSTTY_ZMX_INSTALL_DIR="$repo_dir"
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$XDG_RUNTIME_DIR" "$workdir/bin"

pass=0
fail=0

# Stub zmx + osascript so the manager sources cleanly without a real Ghostty.
cat > "$workdir/bin/zmx" <<'STUB'
#!/bin/zsh
case "$1 $2" in
  "list ") : ;;
  "list --short") : ;;
  "kill "*) ;;
  "history "*) ;;
esac
STUB
chmod +x "$workdir/bin/zmx"
export PATH="$workdir/bin:$PATH"
osascript() { print "0"; }

# Source the lib + manager the way the reaper does. The lib defines
# ghostty_zmx_has_tty_capability; stub it to succeed (production-like: a real
# Ghostty 1.4+ surface passes the probe).
source "$repo_dir/session-manager-lib.zsh"
ghostty_zmx_has_tty_capability() { return 0; }

# Test 1: under the REAPER guard, the manager defines all functions and
# returns before widget install / auto-attach.
print "test 1: manager returns early under GHOSTTY_ZMX_INTERNAL_REAPER=1"
_reaper_auto_attach_ran=0
_ghostty_zmx_auto_attach() { _reaper_auto_attach_ran=1; }
GHOSTTY_ZMX_INTERNAL_REAPER=1 source "$repo_dir/session-manager.zsh"
if [[ "$_reaper_auto_attach_ran" == "0" ]]; then
  print "  ok: auto-attach not called under REAPER guard"
  pass=$((pass+1))
else
  print -u2 "  FAIL: auto-attach ran under REAPER guard"
  fail=$((fail+1))
fi

# Test 2: every helper the reaper body calls is defined after sourcing the
# manager under the REAPER guard.
print ""
print "test 2: all reaper helpers defined after sourcing manager"
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
  print "  ok: all ${#helpers[@]} reaper helpers defined"
  pass=$((pass+1))
else
  print -u2 "  $missing helper(s) missing"
  fail=$((fail+1))
fi

# Test 3: the generated reaper script sources the manager (does not inline
# the helpers). Generate it via _ghostty_zmx_start_reaper and inspect.
print ""
print "test 3: generated reaper script sources the manager (no inlined helpers)"
source "$repo_dir/session-manager.zsh"
_ghostty_zmx_reaper_startup_delay=0
fake_pid=$$
_ghostty_zmx_start_reaper "$fake_pid" 2>/dev/null
runtime_dir="$(_ghostty_zmx_runtime_dir)"
reaper_script="$runtime_dir/reaper-${fake_pid}.zsh"
pkill -f "reaper-${fake_pid}.zsh" 2>/dev/null || true
if [[ ! -f "$reaper_script" ]]; then
  print -u2 "  FAIL: reaper script not generated"
  fail=$((fail+1))
else
  # The reaper must source the manager under the REAPER guard.
  if grep -q 'GHOSTTY_ZMX_INTERNAL_REAPER=1 source "$manager_src"' "$reaper_script"; then
    print "  ok: reaper sources manager under REAPER guard"
    pass=$((pass+1))
  else
    print -u2 "  FAIL: reaper does not source manager under REAPER guard"
    fail=$((fail+1))
  fi
  # The reaper must NOT inline the old no-prefix helpers.
  if grep -q '^valid_session_name() {' "$reaper_script" || \
     grep -q '^managed_detached_sessions() {' "$reaper_script" || \
     grep -q '^registry_heartbeat() {' "$reaper_script" || \
     grep -q '^_reaper_debug_rotate() {' "$reaper_script"; then
    print -u2 "  FAIL: reaper still inlines old no-prefix helpers"
    fail=$((fail+1))
  else
    print "  ok: reaper does not inline old no-prefix helpers"
    pass=$((pass+1))
  fi
  # The reaper must unset TERM_PROGRAM (bypass the version-self-gate).
  if grep -q '^unset TERM_PROGRAM' "$reaper_script"; then
    print "  ok: reaper unsets TERM_PROGRAM (bypasses version-self-gate)"
    pass=$((pass+1))
  else
    print -u2 "  FAIL: reaper does not unset TERM_PROGRAM"
    fail=$((fail+1))
  fi
  # The generated reaper script must be syntactically valid zsh.
  if zsh -n "$reaper_script" 2>/dev/null; then
    print "  ok: generated reaper script passes zsh -n"
    pass=$((pass+1))
  else
    print -u2 "  FAIL: generated reaper script has zsh syntax error"
    fail=$((fail+1))
  fi
fi

print ""
if [[ "$fail" == "0" ]]; then
  print "all reaper-sources-manager tests passed ($pass/$pass)"
  exit 0
else
  print -u2 "$fail test(s) failed"
  exit 1
fi
