#!/bin/zsh
# Unit tests for ghostty_zmx_notty_prefix tsh detection (split-inherit bug).
#
# Bug: when a remote projection is opened via tsh, the widget resolves the
# transport to an absolute path (/usr/local/bin/tsh). ghostty_zmx_notty_prefix
# builds the no-pty ssh prefix for the inherit's remote-layout `add` call. Its
# tsh detection compared probe[1] to bare "tsh", so an absolute path
# (/usr/local/bin/tsh) was NOT detected as tsh → is_tsh=0 → it inserted `-T`
# (an ssh no-pty flag) into a tsh command → `tsh: error: unknown short flag
# '-T'` → the remote-layout `add` failed → inherit fell back to a local
# session. This is the same basename bug fixed in the widget's _is_tsh check,
# but missed here.
#
# Fix: detect tsh by the basename of probe[1] (so /usr/local/bin/tsh matches),
# and never add `-T` to a tsh command (tsh rejects it; tsh ssh gets no-pty
# by default for non-interactive remote commands).

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export HOME="$workdir/home"
mkdir -p "$HOME"

source "$repo_dir/session-manager.zsh"

pass=0
fail=0

# Test 1: absolute tsh path is detected as tsh (no -T added).
print "test 1: notty_prefix detects absolute tsh path, no -T"
_res="$(ghostty_zmx_notty_prefix "/usr/local/bin/tsh ssh -t pier@pcad-dev" 2>/dev/null)"
if [[ "$_res" == "/usr/local/bin/tsh ssh pier@pcad-dev" ]]; then
  print "  ok: $_res"
  pass=$((pass+1))
else
  print -u2 "  FAIL: expected '/usr/local/bin/tsh ssh pier@pcad-dev', got [$_res]"
  fail=$((fail+1))
fi

# Test 2: bare tsh still works.
print ""
print "test 2: notty_prefix detects bare tsh, no -T"
_res="$(ghostty_zmx_notty_prefix "tsh ssh -t pier@pcad-dev" 2>/dev/null)"
if [[ "$_res" == "tsh ssh pier@pcad-dev" ]]; then
  print "  ok: $_res"
  pass=$((pass+1))
else
  print -u2 "  FAIL: expected 'tsh ssh pier@pcad-dev', got [$_res]"
  fail=$((fail+1))
fi

# Test 3: ssh gets -T (correct — ssh supports it).
print ""
print "test 3: notty_prefix adds -T for plain ssh"
_res="$(ghostty_zmx_notty_prefix "/usr/bin/ssh -t pier@pcad-dev" 2>/dev/null)"
if [[ "$_res" == "/usr/bin/ssh -T pier@pcad-dev" ]]; then
  print "  ok: $_res"
  pass=$((pass+1))
else
  print -u2 "  FAIL: expected '/usr/bin/ssh -T pier@pcad-dev', got [$_res]"
  fail=$((fail+1))
fi

# Test 4: the produced tsh prefix actually runs without "unknown short flag".
print ""
print "test 4: tsh notty_prefix does not produce '-T' (would break tsh)"
_res="$(ghostty_zmx_notty_prefix "/usr/local/bin/tsh ssh -t pier@pcad-dev" 2>/dev/null)"
if [[ "$_res" != *"-T"* ]]; then
  print "  ok: no -T in tsh prefix"
  pass=$((pass+1))
else
  print -u2 "  FAIL: tsh prefix contains -T: [$_res]"
  fail=$((fail+1))
fi

print ""
if [[ "$fail" -eq 0 ]]; then
  print "all notty-prefix-tsh tests passed ($pass/$pass)"
  exit 0
else
  print -u2 "$fail test(s) failed"
  exit 1
fi
