#!/bin/zsh
# Regression test for the poller extraction: the poller is a real file
# (poller.sh) that sources the manager (GHOSTTY_ZMX_INTERNAL_POLLER=1 guard)
# and reuses its helpers instead of inlining ~400 lines of duplicated copies
# (PR #23). The extraction (this PR) moved the poller body out of a heredoc
# in session-manager.zsh into a real file, mirroring the reaper extraction.
#
# These are behavioral tests: they source the manager under the POLLER guard
# and assert the helpers are defined; then they generate the real poller
# script via ghostty_zmx_start_remote_poller and syntax-check it.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state"
export XDG_RUNTIME_DIR="$workdir/runtime"
export TERM_PROGRAM=ghostty
export GHOSTTY_ZMX_INSTALL_DIR="$repo_dir"
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$XDG_RUNTIME_DIR"

pass=0; fail=0

# Source the lib first, then stub the 1.4.0 tty/pid capability probe so the
# manager's version-self-gate does not early-return (same shape as
# tests/reaper-stacking.zsh).
source "$repo_dir/session-manager-lib.zsh"
ghostty_zmx_has_tty_capability() { return 0; }

# Test 1: under GHOSTTY_ZMX_INTERNAL_POLLER=1, the manager defines all
# functions and returns before widget install / auto-attach.
print "test 1: manager returns early under GHOSTTY_ZMX_INTERNAL_POLLER=1"
_poller_auto_attach_ran=0
_ghostty_zmx_auto_attach() { _poller_auto_attach_ran=1; }
GHOSTTY_ZMX_INTERNAL_POLLER=1 source "$repo_dir/session-manager.zsh"
if [[ "$_poller_auto_attach_ran" == "0" ]]; then
  print "  ok: auto-attach not called under POLLER guard"; pass=$((pass+1))
else
  print -u2 "  FAIL: auto-attach ran under POLLER guard"; fail=$((fail+1))
fi

# Test 2: every helper the poller body calls is defined after sourcing the
# manager under the POLLER guard.
print ""
print "test 2: all poller helpers defined after sourcing manager under POLLER guard"
helpers=(
  ghostty_zmx_poll_once
  ghostty_zmx_snapshot_remote_sessions
  ghostty_zmx_find_live_projection
  _ghostty_zmx_parse_elapsed_seconds
  _ghostty_zmx_debug
  _ghostty_zmx_debug_rotate
)
missing=0
for h in "${helpers[@]}"; do
  if (( ! $+functions[$h] )); then
    print -u2 "  FAIL: $h not defined"
    missing=$((missing + 1))
  fi
done
if [[ "$missing" == "0" ]]; then
  print "  ok: all ${#helpers[@]} poller helpers defined"; pass=$((pass+1))
else
  print -u2 "  $missing helper(s) missing"; fail=$((fail+1))
fi

# Test 3: poller.sh sources the manager under the POLLER guard and has the
# unset TERM_PROGRAM + defensive guard (mirroring the reaper fix).
print ""
print "test 3: poller.sh sources manager, unsets TERM_PROGRAM, defensive guard"
if grep -q 'GHOSTTY_ZMX_INTERNAL_POLLER=1 source "$manager_src"' "$repo_dir/poller.sh"; then
  print "  ok: poller.sh sources manager under POLLER guard"; pass=$((pass+1))
else
  print -u2 "  FAIL: poller.sh does not source manager under POLLER guard"; fail=$((fail+1))
fi
if grep -q '^unset TERM_PROGRAM' "$repo_dir/poller.sh"; then
  print "  ok: poller.sh unsets TERM_PROGRAM (bypasses version-self-gate)"; pass=$((pass+1))
else
  print -u2 "  FAIL: poller.sh does not unset TERM_PROGRAM"; fail=$((fail+1))
fi
if grep -q 'exit 71' "$repo_dir/poller.sh"; then
  print "  ok: poller.sh has defensive exit 71 guard"; pass=$((pass+1))
else
  print -u2 "  FAIL: poller.sh missing defensive exit 71 guard"; fail=$((fail+1))
fi
# poller.sh must pass zsh -n.
if zsh -n "$repo_dir/poller.sh" 2>/dev/null; then
  print "  ok: poller.sh passes zsh -n"; pass=$((pass+1))
else
  print -u2 "  FAIL: poller.sh fails zsh -n"; fail=$((fail+1))
fi

# Test 4: the generated poller script (cp'd from poller.sh) is syntactically
# valid and sources the manager. Generate it via ghostty_zmx_start_remote_poller
# with stubs so no real poller runs.
print ""
print "test 4: generated poller script is a copy of poller.sh"
# Stub osascript + zmx so the manager sources cleanly.
osascript() { print "0"; }
mkdir -p "$workdir/bin"
cat > "$workdir/bin/zmx" <<'STUB'
#!/bin/zsh
case "$1 $2" in
  "list ") : ;;
  "list --short") : ;;
  *) ;;
esac
STUB
chmod +x "$workdir/bin/zmx"
export PATH="$workdir/bin:$PATH"
export GHOSTTY_ZMX_DEBUG=1
export GHOSTTY_ZMX_REMOTE_POLL_INTERVAL=0.2
export GHOSTTY_ZMX_SCROLLBACK_LINES=1000
source "$repo_dir/session-manager.zsh"
fake_ghostty_pid=$$
# Stub the pid detector so the poller script is named with our fake pid
# (force mode re-detects the pid via ghostty_zmx_detect_ghostty_pid, which
# would walk up to the real Ghostty.app and name the script with that pid).
ghostty_zmx_detect_ghostty_pid() { print -r -- "$fake_ghostty_pid"; }
ghostty_zmx_start_remote_poller force 2>/dev/null
_runtime="$(_ghostty_zmx_runtime_dir 2>/dev/null)"
_poller_script="$_runtime/remote-poller-${fake_ghostty_pid}.zsh"
if [[ -f "$_poller_script" ]]; then
  print "  ok: poller script generated"; pass=$((pass+1))
else
  print -u2 "  FAIL: poller script not generated"; fail=$((fail+1))
fi
# The generated script must be a copy of poller.sh (same content, modulo the
# shebang line which the old noclobber print wrote first — now cp writes the
# whole file including its own shebang).
if zsh -n "$_poller_script" 2>/dev/null; then
  print "  ok: generated poller script passes zsh -n"; pass=$((pass+1))
else
  print -u2 "  FAIL: generated poller script fails zsh -n"; fail=$((fail+1))
fi
# The generated script must source the manager under the POLLER guard.
if grep -q 'GHOSTTY_ZMX_INTERNAL_POLLER=1 source "$manager_src"' "$_poller_script" 2>/dev/null; then
  print "  ok: generated poller script sources manager under POLLER guard"; pass=$((pass+1))
else
  print -u2 "  FAIL: generated poller script does not source manager"; fail=$((fail+1))
fi
pkill -f "remote-poller-${fake_ghostty_pid}.zsh" 2>/dev/null || true
rm -f "$_poller_script" 2>/dev/null || true
rm -rf "$_runtime/remote-poller-${_ghostty_app_name}-${fake_ghostty_pid}.lock" 2>/dev/null || true

print ""
if [[ "$fail" == "0" ]]; then
  print "all poller-sources-manager tests passed ($pass/$pass)"
  exit 0
else
  print -u2 "$fail test(s) failed"
  exit 1
fi
