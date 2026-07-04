#!/bin/zsh
# Unit tests for transport-path resolution under a launchd-style PATH.
#
# Bug 2 (real-world recurrence): the widget runs in a Ghostty surface shell
# that may inherit macOS launchd's minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin),
# which does NOT include /usr/local/bin (where tsh lives on macOS, as a symlink
# to /Applications/tsh.app). The resolver `command -v tsh` returns nothing on
# that PATH, so the resolver falls back to bare `tsh`, and the projection
# wrapper (also under a minimal PATH) fails with `command not found: tsh` →
# the probe returns non-zero → "could not reach <host> (ssh exit 1)".
#
# Fix: the resolver searches common macOS transport-binary locations
# (/usr/local/bin, /opt/homebrew/bin, /opt/local/bin) when `command -v` fails,
# so it finds tsh even under a launchd PATH.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export HOME="$workdir/home"
mkdir -p "$HOME"

# Stub a fake tsh in a "common" location that mimics /usr/local/bin on macOS.
# We can't write to the real /usr/local/bin, so create a fake common dir and
# point the resolver at it via a custom search-path env var (testability).
fake_common="$workdir/usr-local-bin"
mkdir -p "$fake_common"
cat > "$fake_common/tsh" <<'EOF'
#!/bin/sh
echo "fake tsh at common path"
EOF
chmod +x "$fake_common/tsh"

# Use a launchd-style PATH (no /usr/local/bin) so `command -v tsh` fails.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

# Point the resolver's search list at our fake common dir.
export GHOSTTY_ZMX_TRANSPORT_SEARCH_PATHS="$fake_common"

pass=0
fail=0

# Source the manager (defines ghostty_zmx_resolve_transport_path).
source "$repo_dir/session-manager.zsh"

# Test 1: resolver finds tsh in the common search path even when PATH lacks it.
print "test 1: resolve_transport_path finds tsh via common search path"
_res="$(ghostty_zmx_resolve_transport_path tsh 2>/dev/null)"
if [[ "$_res" == "$fake_common/tsh" ]]; then
  print "  ok: tsh resolved to $_res"
  pass=$((pass+1))
else
  print -u2 "  FAIL: expected $fake_common/tsh, got [$_res]"
  fail=$((fail+1))
fi

# Test 2: ssh is on /usr/bin (launchd PATH has it), so resolves directly.
print ""
print "test 2: resolve_transport_path finds ssh on the launchd PATH"
_res="$(ghostty_zmx_resolve_transport_path ssh 2>/dev/null)"
if [[ "$_res" == "/usr/bin/ssh" ]]; then
  print "  ok: ssh resolved to $_res"
  pass=$((pass+1))
else
  print -u2 "  FAIL: expected /usr/bin/ssh, got [$_res]"
  fail=$((fail+1))
fi

# Test 3: unknown binary falls back to bare name (honest error, not empty).
print ""
print "test 3: resolve_transport_path falls back to bare name for unknown binary"
_res="$(ghostty_zmx_resolve_transport_path nonexistent-transport 2>/dev/null)"
if [[ "$_res" == "nonexistent-transport" ]]; then
  print "  ok: unknown binary fell back to bare name"
  pass=$((pass+1))
else
  print -u2 "  FAIL: expected 'nonexistent-transport', got [$_res]"
  fail=$((fail+1))
fi

print ""
if [[ "$fail" -eq 0 ]]; then
  print "all transport-path-launchd tests passed ($pass/$pass)"
  exit 0
else
  print -u2 "$fail test(s) failed"
  exit 1
fi
