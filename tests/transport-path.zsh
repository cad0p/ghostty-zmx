#!/bin/zsh
# Unit tests for transport-path resolution (bug 2: tsh not found in projection).
#
# Bug 2: when a user types `tsh ssh pier@pcad-dev`, the widget built the
# projection prefix as `tsh ssh -t pier@pcad-dev` (bare `tsh`). The projection
# wrapper runs under `#!/bin/zsh -f` as a Ghostty surface command, inheriting
# Ghostty's launchd PATH — which does NOT include `/usr/local/bin` where `tsh`
# lives on macOS. So the remote pane printed `command not found: tsh` and the
# surface exited.
#
# The fix: resolve the transport binary (`tsh`/`ssh`) to an absolute path when
# building the projection prefix, the same way `ghostty_zmx_remote_zmx_for_host`
# resolves the remote zmx path. This test asserts `ghostty_zmx_resolve_transport_path`
# returns an absolute path for a known binary and falls back to the bare name
# (not an empty string) when the binary is not found.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export HOME="$workdir/home"
mkdir -p "$HOME"

# Stub a fake tsh on a custom PATH so the test is hermetic.
fake_bin="$workdir/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/tsh" <<'EOF'
#!/bin/sh
echo "fake tsh"
EOF
chmod +x "$fake_bin/tsh"

# Source the manager (defines ghostty_zmx_resolve_transport_path if present).
# Use the fake bin PATH so `command -v tsh` finds our stub.
export PATH="$fake_bin:/usr/bin:/bin"
source "$repo_dir/session-manager.zsh"

pass=0
fail=0

# Test 1: resolves a known binary (tsh) to an absolute path.
print "test 1: resolve_transport_path returns absolute path for tsh"
_res="$(ghostty_zmx_resolve_transport_path tsh 2>/dev/null)"
if [[ "$_res" == "$fake_bin/tsh" ]]; then
  print "  ok: tsh resolved to $_res"
  pass=$((pass+1))
else
  print -u2 "  FAIL: expected $fake_bin/tsh, got [$_res]"
  fail=$((fail+1))
fi

# Test 2: falls back to the bare name (not empty) when binary is missing.
print "test 2: resolve_transport_path falls back to bare name for missing binary"
_res2="$(ghostty_zmx_resolve_transport_path nonexistent-transport-xyz 2>/dev/null)"
if [[ "$_res2" == "nonexistent-transport-xyz" ]]; then
  print "  ok: missing binary falls back to bare name"
  pass=$((pass+1))
else
  print -u2 "  FAIL: expected bare name 'nonexistent-transport-xyz', got [$_res2]"
  fail=$((fail+1))
fi

# Test 3: ssh resolves (always present on macOS at /usr/bin/ssh).
print "test 3: resolve_transport_path returns absolute path for ssh"
_res3="$(ghostty_zmx_resolve_transport_path ssh 2>/dev/null)"
if [[ "$_res3" == /* ]]; then
  print "  ok: ssh resolved to $_res3"
  pass=$((pass+1))
else
  print -u2 "  FAIL: expected absolute path, got [$_res3]"
  fail=$((fail+1))
fi

print ""
if (( fail > 0 )); then
  print -u2 "$fail test(s) FAILED"
  exit 1
fi
print "all transport-path tests passed ($pass/$pass)"
exit 0
