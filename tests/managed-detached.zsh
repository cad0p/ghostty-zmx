#!/bin/zsh
# Unit tests for the reaper's startup orphan sweep.
#
# When Ghostty is killed (not cleanly exited), managed zmx sessions are left
# detached (clients=0) forever. The reaper's startup sweep kills them. The
# sweep uses managed_detached_sessions() which must ONLY return managed v0.1
# sessions (zmx-<win>-<tab>-<term>) that are in the sessions log with
# clients=0 — never user-created sessions, gzr-* remote sessions, or attached
# sessions.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data"
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME"

pass=0
fail=0

# Test 1: the startup sweep call is present in the reaper source.
print "test 1: reaper source has startup orphan-sweep call"
if grep -q 'cleanup_detached_sessions "startup-orphan-sweep"' "$repo_dir/session-manager.zsh"; then
  print "  ok: sweep call present"
  pass=$((pass+1))
else
  print -u2 "  FAIL: startup-orphan-sweep call not found in session-manager.zsh"
  fail=$((fail+1))
fi

# Test 2: the sweep runs AFTER reaperStartupDelay and BEFORE the main loop.
print ""
print "test 2: sweep runs at startup (before the main while loop)"
sweep_ok=0
awk '
  /sleep "\$reaperStartupDelay"/ { found_sleep=1; next }
  found_sleep && /cleanup_detached_sessions "startup-orphan-sweep"/ { found_sweep=1; next }
  found_sweep && /while kill -0 "\$ghosttyPID"/ { print "ok"; exit }
' "$repo_dir/session-manager.zsh" | grep -q ok && sweep_ok=1
if [[ "$sweep_ok" -eq 1 ]]; then
  print "  ok: sweep is between startup delay and main loop"
  pass=$((pass+1))
else
  print -u2 "  FAIL: sweep not positioned correctly at startup"
  fail=$((fail+1))
fi

# Test 3: extract ONLY valid_session_name + managed_detached_sessions (the
# two functions the sweep relies on) and test their filtering. Extract each
# function by its def line through its closing brace.
print ""
print "test 3: managed_detached_sessions filters correctly"
extracted="$workdir/funcs.zsh"
# Extract valid_session_name (a single short function).
sed -n '/^valid_session_name() {/,/^}/p' "$repo_dir/session-manager.zsh" > "$extracted"
# Append the inlined registry helpers (reaper is standalone; these are the
# no-prefix versions: registry_dir, registry_file, registry_tracked_sessions,
# registry_heartbeat).
sed -n '/^registry_dir() {/,/^}/p' "$repo_dir/session-manager.zsh" >> "$extracted"
sed -n '/^registry_file() {/,/^}/p' "$repo_dir/session-manager.zsh" >> "$extracted"
sed -n '/^registry_tracked_sessions() {/,/^}/p' "$repo_dir/session-manager.zsh" >> "$extracted"
# Append managed_detached_sessions (also def-through-close-brace).
sed -n '/^managed_detached_sessions() {/,/^}/p' "$repo_dir/session-manager.zsh" >> "$extracted"
# debug_log stub (extracted code calls it).
print 'debug_log() { :; }' >> "$extracted"

# Seed the sessions log: only managed sessions that ghostty-zmx recorded.
cat > "$GHOSTTY_ZMX_DATA_HOME/sessions" <<EOF
zmx-6000035bc6c0-10b40f340-85691562
zmx-6000035bc6c0-10b40f340-DEADBEEF
EOF
cat > "$GHOSTTY_ZMX_DATA_HOME/tty-map" <<EOF
S	zmx-6000035bc6c0-10b40f340-DEADBEEF	/dev/ttys777	12345
EOF

got="$(zsh -c '
  log="'"$GHOSTTY_ZMX_DATA_HOME"'/sessions"
  ttyMap="'"$GHOSTTY_ZMX_DATA_HOME"'/tty-map"
  current_terminal_ttys() { print /dev/ttys777; }
  zmx() {
    case "$1" in
      list) cat <<ZMX
  name=zmx-6000035bc6c0-10b40f340-85691562	pid=42979	clients=0	created=1	start_dir=/h
  name=zmx-6000035bc6c0-10b40f340-D001E11D	pid=47669	clients=1	created=1	start_dir=/h
  name=mywork	pid=12345	clients=0	created=1	start_dir=/h
  name=gzr-abc12345-def67890-abc123-abc123	pid=999	clients=0	created=1	start_dir=/h
  name=zmx-notvalid	pid=111	clients=0	created=1	start_dir=/h
  name=zmx-6000035bc6c0-10b40f340-DEADBEEF	pid=222	clients=0	created=1	start_dir=/h
ZMX
    ;;
  esac
  }
  source "'"$extracted"'" 2>/dev/null
  managed_detached_sessions
' 2>/dev/null)"
print "  returned: [$(print "$got" | tr '\n' ' ')]"

# Excludes user-created "mywork"
if print "$got" | grep -q "mywork"; then
  print -u2 "  FAIL: user session 'mywork' returned"; fail=$((fail+1))
else
  print "  ok: 'mywork' excluded"; pass=$((pass+1))
fi
# Excludes gzr-*
if print "$got" | grep -q "gzr-"; then
  print -u2 "  FAIL: gzr-* returned"; fail=$((fail+1))
else
  print "  ok: gzr-* excluded"; pass=$((pass+1))
fi
# Excludes attached (D001E11D has clients=1)
if print "$got" | grep -q "D001E11D"; then
  print -u2 "  FAIL: attached D001E11D returned"; fail=$((fail+1))
else
  print "  ok: attached excluded"; pass=$((pass+1))
fi
# Excludes invalid "zmx-notvalid"
if print "$got" | grep -q "zmx-notvalid"; then
  print -u2 "  FAIL: invalid name returned"; fail=$((fail+1))
else
  print "  ok: invalid name excluded"; pass=$((pass+1))
fi
# Returns the valid orphan 85691562
if print "$got" | grep -q "85691562"; then
  print "  ok: orphan 85691562 returned"; pass=$((pass+1))
else
  print -u2 "  FAIL: expected 85691562"; fail=$((fail+1))
fi
# Excludes a clients=0 session whose mapped Ghostty terminal tty is still live.
if print "$got" | grep -q "DEADBEEF"; then
  print -u2 "  FAIL: live-tty DEADBEEF returned"; fail=$((fail+1))
else
  print "  ok: live-tty session excluded"; pass=$((pass+1))
fi

# --- Test 4: cross-install registry protects a session tracked by another install ---
print ""
print "test 4: registry-tracked session (another install) is not reaped"
# Stage a registry file for a DIFFERENT install (different data-home hash)
# that tracks a session the reaper would otherwise reap.
registry_dir="$HOME/.local/state/ghostty-zmx/managed-sessions"
mkdir -p "$registry_dir"
other_hash="$(print -r -- "/fake/other/install/data-home" | cksum 2>/dev/null | tr -d ' ' | cut -c1-16)"
cat > "$registry_dir/${other_hash}.tsv" <<EOF
zmx-6000035bc6c0-10b40f340-REGISTRY	99999	$(date +%s)
EOF
# Re-run managed_detached_sessions; the REGISTRY session must now be excluded
got2="$(zsh -c '
  log="'"$GHOSTTY_ZMX_DATA_HOME"'/sessions"
  ttyMap="'"$GHOSTTY_ZMX_DATA_HOME"'/tty-map"
  current_terminal_ttys() { print /dev/ttys777; }
  zmx() {
    case "$1" in
      list) cat <<ZMX
  name=zmx-6000035bc6c0-10b40f340-85691562	pid=42979	clients=0	created=1	start_dir=/h
  name=zmx-6000035bc6c0-10b40f340-REGISTRY	pid=47669	clients=0	created=1	start_dir=/h
ZMX
      ;;
    esac
  }
  source "'"$extracted"'" 2>/dev/null
  managed_detached_sessions
' 2>/dev/null)"
print "  returned: [$(print "$got2" | tr '\n' ' ')]"
# 85691562 (untracked) is still reaped
if print "$got2" | grep -q "85691562"; then
  print "  ok: untracked orphan 85691562 still reaped"; pass=$((pass+1))
else
  print -u2 "  FAIL: expected 85691562 reaped"; fail=$((fail+1))
fi
# REGISTRY (tracked by another install) is NOT reaped
if print "$got2" | grep -q "REGISTRY"; then
  print -u2 "  FAIL: registry-tracked REGISTRY reaped"; fail=$((fail+1))
else
  print "  ok: registry-tracked session (another install) excluded"; pass=$((pass+1))
fi
rm -rf "$registry_dir" 2>/dev/null

print ""
if [[ "$fail" -eq 0 ]]; then
  print "all managed-detached tests passed ($pass/$pass)"
  exit 0
else
  print -u2 "$fail test(s) failed"
  exit 1
fi
