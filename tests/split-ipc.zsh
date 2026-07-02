#!/bin/zsh
# Unit tests for Prototype D (keybind text: -> local IPC listener).
#
# Covers the pure, testable pieces:
#   1. ghostty_zmx_split_axis_for_direction: right -> horizontal, down -> vertical,
#      unknown -> return 1.
#   2. ghostty_zmx_split_find_parent_by_tty: matches a gzr-* row by local tty,
#      ignores non-gzr rows and non-matching ttys.
#   3. ghostty_zmx_split_socket_path: stable path under the runtime dir.
#
# The IPC listener itself and the AppleScript split are integration paths
# exercised only by live E2E (a running Ghostty + projection); they are not
# unit-testable without a socket + pty harness.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data/ghostty-zmx"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state/ghostty-zmx"
export XDG_RUNTIME_DIR="$workdir/runtime"
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$XDG_RUNTIME_DIR"

# Source the manager without triggering auto-attach (no AUTO_ATTACH/TERM_PROGRAM).
source "$repo_dir/session-manager.zsh"

# --- Case 1: axis mapping ---
out="$(ghostty_zmx_split_axis_for_direction right)" && rc=0 || rc=$?
[[ "$rc" -eq 0 && "$out" == "horizontal" ]] || { print -u2 "right: expected horizontal, got '$out' (rc=$rc)"; exit 1 }
print "ok: direction right -> horizontal"

out="$(ghostty_zmx_split_axis_for_direction down)" && rc=0 || rc=$?
[[ "$rc" -eq 0 && "$out" == "vertical" ]] || { print -u2 "down: expected vertical, got '$out' (rc=$rc)"; exit 1 }
print "ok: direction down -> vertical"

out="$(ghostty_zmx_split_axis_for_direction up 2>/dev/null)" && rc=0 || rc=$?
[[ "$rc" -ne 0 ]] || { print -u2 "up: expected non-zero exit, got rc=0 out='$out'"; exit 1 }
print "ok: unknown direction up -> non-zero exit"

# --- Case 2: parent-by-tty lookup ---
proj="$GHOSTTY_ZMX_DATA_HOME/remote-projections"
cat > "$proj" <<TSV
pcad-dev	ws12345678	gzr-ws12345678-win12345678-tab123abc-pane123abc	/dev/ttys042	12345	attached	1234567890	win12345678	tab123abc
otherhost	ws99999999	gzl-ws99999999-win99999999-tab999999-pan999999	/dev/ttys099	67890	attached	1234567890	win99999999	tab999999
pcad-dev	ws12345678	gzr-ws12345678-win12345678-tab456def-pane456def	/dev/ttys055	22222	attached	1234567890	win12345678	tab456def
TSV

# Match the first gzr row with the given tty.
ghostty_zmx_split_find_parent_by_tty "/dev/ttys042"
rc=$?
[[ "$rc" -eq 0 ]] || { print -u2 "find-by-tty: expected match, got rc=$rc"; exit 1 }
[[ "$_gzmx_split_parent_host" == "pcad-dev" ]] || { print -u2 "find-by-tty: wrong host: $_gzmx_split_parent_host"; exit 1 }
[[ "$_gzmx_split_parent_session" == "gzr-ws12345678-win12345678-tab123abc-pane123abc" ]] || { print -u2 "find-by-tty: wrong session: $_gzmx_split_parent_session"; exit 1 }
print "ok: find-parent-by-tty matches gzr row (ttys042)"

# Second tty in the same window.
ghostty_zmx_split_find_parent_by_tty "/dev/ttys055"
rc=$?
[[ "$rc" -eq 0 ]] || { print -u2 "find-by-tty2: expected match, got rc=$rc"; exit 1 }
[[ "$_gzmx_split_parent_session" == "gzr-ws12345678-win12345678-tab456def-pane456def" ]] || { print -u2 "find-by-tty2: wrong session: $_gzmx_split_parent_session"; exit 1 }
print "ok: find-parent-by-tty matches gzr row (ttys055)"

# gzl (local) rows must be ignored.
ghostty_zmx_split_find_parent_by_tty "/dev/ttys099"
rc=$?
[[ "$rc" -ne 0 ]] || { print -u2 "find-by-tty-gzl: expected non-zero (local row must not match), got rc=0 host=$_gzmx_split_parent_host"; exit 1 }
print "ok: find-parent-by-tty ignores gzl rows"

# Non-existent tty.
ghostty_zmx_split_find_parent_by_tty "/dev/ttys999"
rc=$?
[[ "$rc" -ne 0 ]] || { print -u2 "missing-tty: expected non-zero, got rc=0"; exit 1 }
print "ok: find-parent-by-tty returns 1 for missing tty"

# --- Case 3: socket path is stable + under runtime dir ---
sock="$(ghostty_zmx_split_socket_path)"
[[ "$sock" == "$XDG_RUNTIME_DIR/ghostty-zmx-${UID:-$(id -u)}/split.sock" ]] || { print -u2 "socket: wrong path: $sock"; exit 1 }
print "ok: split socket path = $sock"

print "all split-ipc tests passed"
