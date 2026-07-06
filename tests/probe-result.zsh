#!/bin/zsh
# Unit tests for ghostty_zmx_probe_result — the remote zmx probe decision
# function extracted from the accept-line widget.
#
# Covers the four probe outcomes:
#   1. host unreachable (ssh exit != 0, empty stdout) → connection error
#   2. zmx missing (no-zmx) → install-zmx error
#   3. zmx wrong version (0.5.0) → update-zmx error
#   4. zmx ok (0.6.0) → success, prints parsed version
#
# And asserts each error message is on its own line (leading+trailing newline).

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data/ghostty-zmx"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state/ghostty-zmx"
unset TERM_PROGRAM GHOSTTY_RESOURCES_DIR 2>/dev/null || true
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME"

# Source the manager without triggering auto-attach (no AUTO_ATTACH/TERM_PROGRAM).
source "$repo_dir/session-manager.zsh"

# Helper: run the probe fn, capture stdout + exit code without set -e aborting.
# NOTE: command substitution $(...) strips trailing newlines, so trailing-
# newline assertions are done separately via a direct pipe at the end.
run_probe() {
  local host="$1" out="$2" rc="$3"
  _probe_out="$(ghostty_zmx_probe_result "$host" "$out" "$rc" 2>/dev/null)"
  _probe_rc=$?
}

# --- Case 1: host unreachable (ssh exit 255, empty stdout) ---
run_probe "gzmx-fixture" "" 255
[[ "$_probe_rc" -ne 0 ]] || { print -u2 "unreachable: expected non-zero exit, got $_probe_rc"; exit 1 }
[[ "$_probe_out" == *"could not reach gzmx-fixture (ssh exit 255)"* ]] || { print -u2 "unreachable: wrong message: $_probe_out"; exit 1 }
[[ "$_probe_out" == *"Is the host online"* ]] || { print -u2 "unreachable: missing hint: $_probe_out"; exit 1 }
# Must NOT mention zmx (the old wrong error).
[[ "$_probe_out" != *"zmx 0.6.x on PATH"* ]] || { print -u2 "unreachable: wrongly mentions zmx: $_probe_out"; exit 1 }
# Leading newline (message on its own line, separate from typed command).
[[ "$_probe_out" == $'\n'* ]] || { print -u2 "unreachable: missing leading newline: $_probe_out"; exit 1 }
print "ok: unreachable → connection error"

# --- Case 1b: probe timeout ---
run_probe "gzmx-fixture" "" 124
[[ "$_probe_rc" -ne 0 ]] || { print -u2 "timeout: expected non-zero exit, got $_probe_rc"; exit 1 }
[[ "$_probe_out" == *"timed out probing gzmx-fixture over ssh"* ]] || { print -u2 "timeout: wrong message: $_probe_out"; exit 1 }
[[ "$_probe_out" == *"ssh proxy/auth is ready"* ]] || { print -u2 "timeout: missing proxy/auth hint: $_probe_out"; exit 1 }
[[ "$_probe_out" == $'\n'* ]] || { print -u2 "timeout: missing leading newline: $_probe_out"; exit 1 }
print "ok: timeout → proxy/auth hint"

# --- Case 2: zmx missing (no-zmx) ---
run_probe "gzmx-fixture" "no-zmx" 0
[[ "$_probe_rc" -ne 0 ]] || { print -u2 "no-zmx: expected non-zero exit, got $_probe_rc"; exit 1 }
[[ "$_probe_out" == *"needs zmx 0.6.x on PATH"* ]] || { print -u2 "no-zmx: wrong message: $_probe_out"; exit 1 }
[[ "$_probe_out" == *"install zmx on gzmx-fixture"* ]] || { print -u2 "no-zmx: missing install hint: $_probe_out"; exit 1 }
[[ "$_probe_out" == $'\n'* ]] || { print -u2 "no-zmx: missing leading newline"; exit 1 }
print "ok: no-zmx → install-zmx error"

# --- Case 3: zmx wrong version (0.5.0) ---
run_probe "gzmx-fixture" "zmx:zmx		0.5.0" 0
[[ "$_probe_rc" -ne 0 ]] || { print -u2 "wrong-ver: expected non-zero exit, got $_probe_rc"; exit 1 }
[[ "$_probe_out" == *"has zmx 0.5.0"* ]] || { print -u2 "wrong-ver: wrong message: $_probe_out"; exit 1 }
[[ "$_probe_out" == *"needs zmx 0.6.x"* ]] || { print -u2 "wrong-ver: missing needs hint: $_probe_out"; exit 1 }
[[ "$_probe_out" == $'\n'* ]] || { print -u2 "wrong-ver: missing leading newline"; exit 1 }
print "ok: wrong-version → update-zmx error"

# --- Case 4: zmx ok (0.6.0) → success, prints parsed version ---
run_probe "gzmx-fixture" "zmx:zmx		0.6.0" 0
[[ "$_probe_rc" -eq 0 ]] || { print -u2 "ok: expected zero exit, got $_probe_rc"; exit 1 }
[[ "$_probe_out" == "0.6.0" ]] || { print -u2 "ok: expected version 0.6.0 on stdout, got: $_probe_out"; exit 1 }
print "ok: zmx 0.6.0 → success"

# --- Case 5: zmx ok (0.6.1 patch) → success ---
run_probe "gzmx-fixture" "zmx:zmx		0.6.1" 0
[[ "$_probe_rc" -eq 0 ]] || { print -u2 "ok-patch: expected zero exit, got $_probe_rc"; exit 1 }
[[ "$_probe_out" == "0.6.1" ]] || { print -u2 "ok-patch: expected version 0.6.1, got: $_probe_out"; exit 1 }
print "ok: zmx 0.6.1 → success"

# --- Case 6: new probe payload includes absolute remote zmx path ---
_new_probe=$'zmx-path:/home/gzmx/.local/bin/zmx\nzmx:zmx		0.6.1'
run_probe "gzmx-fixture" "$_new_probe" 0
[[ "$_probe_rc" -eq 0 ]] || { print -u2 "ok-path: expected zero exit, got $_probe_rc"; exit 1 }
[[ "$_probe_out" == "0.6.1" ]] || { print -u2 "ok-path: expected version 0.6.1, got: $_probe_out"; exit 1 }
[[ "$(ghostty_zmx_probe_zmx_path "$_new_probe")" == "/home/gzmx/.local/bin/zmx" ]] || { print -u2 "ok-path: failed to parse zmx path"; exit 1 }
[[ -z "$(ghostty_zmx_probe_zmx_path $'zmx-path:../../bad\nzmx:zmx		0.6.1')" ]] || { print -u2 "ok-path: accepted unsafe zmx path"; exit 1 }
print "ok: zmx path payload → success"

# --- Trailing-newline check (direct pipe; $(...) strips them) ---
# All three error messages must end with \n\n so a blank line separates them
# from the next prompt. Command substitution strips trailing newlines, so
# inspect the raw bytes via a pipe.
_tail="$(ghostty_zmx_probe_result "gzmx-fixture" "" 255 2>/dev/null | tail -c 3 | od -An -c | tr -d ' ')"
[[ "$_tail" == *"\\n\\n"* ]] || { print -u2 "trailing: unreachable expected \\n\\n, got: $_tail"; exit 1 }
_tail="$(ghostty_zmx_probe_result "gzmx-fixture" "no-zmx" 0 2>/dev/null | tail -c 3 | od -An -c | tr -d ' ')"
[[ "$_tail" == *"\\n\\n"* ]] || { print -u2 "trailing: no-zmx expected \\n\\n, got: $_tail"; exit 1 }
_tail="$(ghostty_zmx_probe_result "gzmx-fixture" "zmx:zmx		0.5.0" 0 2>/dev/null | tail -c 3 | od -An -c | tr -d ' ')"
[[ "$_tail" == *"\\n\\n"* ]] || { print -u2 "trailing: wrong-ver expected \\n\\n, got: $_tail"; exit 1 }
print "ok: all error messages end with blank line (trailing \\n\\n)"

# --- Case 7: host name with user@ (normalized) — message uses the host key ---
run_probe "pcad-dev" "" 255
[[ "$_probe_out" == *"could not reach pcad-dev"* ]] || { print -u2 "host-key: wrong message: $_probe_out"; exit 1 }
print "ok: host key in message"

print -r -- $'gzmx-fixture\tssh\t0.6.1\tactive\tssh gzmx-fixture\t/home/gzmx/.local/bin/zmx' > "$GHOSTTY_ZMX_DATA_HOME/remote-hosts"
_cmd="$(ghostty_zmx_projection_command_string gzmx-fixture ws sess 'ssh gzmx-fixture')"
[[ "$_cmd" == *"/home/gzmx/.local/bin/zmx attach sess"* ]] || { print -u2 "projection command did not use remote zmx path: $_cmd"; exit 1 }
[[ "$_cmd" != *"source ~/.zshrc"* ]] || { print -u2 "projection command still sources remote zshrc: $_cmd"; exit 1 }
[[ "$_cmd" == env\ PATH=* ]] || { print -u2 "projection command did not carry local PATH for ssh ProxyCommand helpers: $_cmd"; exit 1 }
print "ok: projection command uses remote zmx path"

print "all probe-result tests passed"
