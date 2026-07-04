#!/bin/zsh
# Unit tests for ghostty_zmx_is_tsh_ssh — the shared tsh-transport detector.
#
# The widget and inherit paths build transport prefixes with the transport
# binary resolved to an absolute path (e.g. /usr/local/bin/tsh). tsh must be
# detected by basename so absolute paths match, and tsh must never get ssh's
# `-T` flag (tsh rejects it). This helper centralizes that detection so all
# call sites stay in sync.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export HOME="$workdir/home"
mkdir -p "$HOME"

source "$repo_dir/session-manager.zsh"

pass=0
fail=0

# Test 1: bare tsh detected.
print "test 1: bare 'tsh ssh' detected"
if ghostty_zmx_is_tsh_ssh "tsh" "ssh"; then
  print "  ok"; pass=$((pass+1))
else
  print -u2 "  FAIL: bare tsh not detected"; fail=$((fail+1))
fi

# Test 2: absolute tsh path detected (the post-resolve form).
print ""
print "test 2: '/usr/local/bin/tsh ssh' detected"
if ghostty_zmx_is_tsh_ssh "/usr/local/bin/tsh" "ssh"; then
  print "  ok"; pass=$((pass+1))
else
  print -u2 "  FAIL: absolute tsh not detected"; fail=$((fail+1))
fi

# Test 3: plain ssh not detected as tsh.
print ""
print "test 3: '/usr/bin/ssh ssh' (wrong) not detected — ssh isn't tsh"
# ssh ssh doesn't make sense, but the helper should only match tsh basename
if ghostty_zmx_is_tsh_ssh "/usr/bin/ssh" "ssh"; then
  print -u2 "  FAIL: /usr/bin/ssh wrongly detected as tsh"; fail=$((fail+1))
else
  print "  ok"; pass=$((pass+1))
fi

# Test 4: tsh without 'ssh' second word not detected.
print ""
print "test 4: 'tsh' alone (no 'ssh') not detected"
if ghostty_zmx_is_tsh_ssh "tsh" ""; then
  print -u2 "  FAIL: bare tsh without ssh wrongly detected"; fail=$((fail+1))
else
  print "  ok"; pass=$((pass+1))
fi

# Test 5: empty input not detected.
print ""
print "test 5: empty args not detected"
if ghostty_zmx_is_tsh_ssh "" ""; then
  print -u2 "  FAIL: empty args wrongly detected"; fail=$((fail+1))
else
  print "  ok"; pass=$((pass+1))
fi

# Test 6: tsh with a path containing tsh as a directory component (not basename).
print ""
print "test 6: '/opt/tsh/bin/zsh ssh' not detected (basename is zsh)"
if ghostty_zmx_is_tsh_ssh "/opt/tsh/bin/zsh" "ssh"; then
  print -u2 "  FAIL: /opt/tsh/bin/zsh wrongly detected"; fail=$((fail+1))
else
  print "  ok"; pass=$((pass+1))
fi

print ""
if [[ "$fail" -eq 0 ]]; then
  print "all is-tsh-ssh tests passed ($pass/$pass)"
  exit 0
else
  print -u2 "$fail test(s) failed"
  exit 1
fi
