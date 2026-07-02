#!/bin/zsh
# Unit tests for the `ghostty-zmx split` CLI subcommand (Prototype B).
#
# Covers the pure-logic parts that don't require a live Ghostty or ssh:
#   1. argument parsing (right/down/help/unknown)
#   2. axis mapping (right->horizontal, down->vertical)
#   3. parent-session parsing (gzr-<ws>-<win>-<tab>-<pane>)
#   4. notty-prefix building (drop -t/-tt/--tty, ensure -T; tsh ssh passthrough)
#
# The AppleScript split call and the ssh layout-add call are integration points
# that require a live Ghostty + remote host; they are exercised by manual E2E
# (docs/manual-e2e.md) and the Docker remote-lifecycle fixture, not here.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

export HOME="$workdir/home"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data/ghostty-zmx"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state/ghostty-zmx"
export GHOSTTY_ZMX_RUNTIME_DIR="$workdir/runtime"
mkdir -p "$HOME" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$GHOSTTY_ZMX_RUNTIME_DIR"

wrapper="$repo_dir/ghostty-zmx"

# --- Case 1: help / no-arg exits 0 and prints usage ---
out="$("$wrapper" split 2>&1)"
rc=$?
[[ "$rc" -eq 0 ]] || { print -u2 "no-arg: expected exit 0, got $rc"; exit 1 }
[[ "$out" == *"Usage: ghostty-zmx split"* ]] || { print -u2 "no-arg: missing usage: $out"; exit 1 }
echo "  ok: no-arg prints usage, exit 0"

out="$("$wrapper" split --help 2>&1)"
rc=$?
[[ "$rc" -eq 0 ]] || { print -u2 "--help: expected exit 0, got $rc"; exit 1 }
[[ "$out" == *"Splits the current projection pane"* ]] || { print -u2 "--help: missing description: $out"; exit 1 }
echo "  ok: --help prints description, exit 0"

# --- Case 2: unknown direction exits 2 ---
out="$("$wrapper" split sideways 2>&1)"
rc=$?
[[ "$rc" -eq 2 ]] || { print -u2 "unknown-dir: expected exit 2, got $rc"; exit 1 }
[[ "$out" == *"sideways"* ]] || { print -u2 "unknown-dir: wrong message: $out"; exit 1 }
echo "  ok: unknown direction exits 2 with message"

# --- Case 3: not inside a projection pane (no TTY match / no projections file) ---
# No remote-projections file => find_current returns 1, CLI exits 1.
# Stub osascript to return empty (no Ghostty / no tty match).
export TTY="/dev/ttys99999"
mkdir -p "$GHOSTTY_ZMX_DATA_HOME"
out="$("$wrapper" split right --tty /dev/ttys99999 2>&1)"
rc=$?
[[ "$rc" -eq 1 ]] || { print -u2 "no-projection: expected exit 1, got $rc"; exit 1 }
[[ "$out" == *"not inside a managed projection pane"* ]] || { print -u2 "no-projection: wrong message: $out"; exit 1 }
echo "  ok: not-in-projection exits 1 with message"

# --- Case 4: axis mapping via the layout-add argv ---
# Build a fake remote-projections row for our TTY, a fake remote-hosts entry,
# and stub osascript + ssh to capture the argv passed to the layout helper and
# the AppleScript split. We can't easily stub osascript (it's a binary called
# by name), so instead we verify the helper argv by replacing the helper path
# with a recording shim via a custom PATH. But the wrapper hardcodes
# $HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout. So we create that shim.
mkdir -p "$HOME/.config/ghostty-zmx"
shim="$HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout"
cat > "$shim" <<'SH'
#!/bin/sh
# Record the argv for later assertion.
echo "ADD:$*" >> "$GHOSTTY_ZMX_DATA_HOME/.shim-calls"
exit 0
SH
chmod +x "$shim"

# Stub osascript so the AppleScript split is a no-op success, AND the
# identity lookup returns a fake window/tab/tty for /dev/ttys99999.
mkdir -p "$workdir/bin"
osascript_shim="$workdir/bin/osascript"
cat > "$osascript_shim" <<'SH'
#!/bin/sh
# If stdin contains the identity lookup (has "tty of tm"), return a fake
# identity. Otherwise (the split call) succeed silently.
input="$(cat)"
if echo "$input" | grep -q "tty of tm"; then
  printf 'win-6000020060a0 tab-6000030060a0 term-6000040060a0 /dev/ttys99999\n'
else
  exit 0
fi
SH
chmod +x "$osascript_shim"

# remote-projections row (format from ghostty_zmx_write_projection_row):
# host\tws\tsession\ttty\tpid\tstate\tupdated\twin\ttab
printf 'pcad-dev\tws12345678\tgzr-ws12345678-win12345678-tab1234-pane12\t/dev/ttys99999\t99999\tattached\t1700000000\twinabc\ttabdef\n' > "$GHOSTTY_ZMX_DATA_HOME/remote-projections"

# remote-hosts row: host\ttransport\tversion\tmode\tprefix
printf 'pcad-dev\ttsh\t0.6.0\tactive\ttsh ssh -t pcad-dev\n' > "$GHOSTTY_ZMX_DATA_HOME/remote-hosts"

# tsh stub: recognize the ghostty-zmx-remote-layout helper path in argv and
# exec it directly with the remaining args (simulating "ssh ran the helper on
# the remote"). POSIX sh only (no [[ ]]).
tsh_shim="$workdir/bin/tsh"
cat > "$tsh_shim" <<'SH'
#!/bin/sh
shim="$HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout"
found=0
for a in "$@"; do
  case "$a" in
    *ghostty-zmx-remote-layout) found=1; break ;;
  esac
done
[ "$found" = 1 ] || { echo "tsh stub: helper not found in argv: $*" >&2; exit 0; }
# Shift past everything up to and including the helper path.
while [ $# -gt 0 ]; do
  case "$1" in
    *ghostty-zmx-remote-layout) shift; break ;;
  esac
  shift
done
exec "$shim" "$@"
SH
chmod +x "$tsh_shim"

# ssh stub (same logic, for plain-ssh hosts).
ssh_shim="$workdir/bin/ssh"
cp "$tsh_shim" "$ssh_shim"
chmod +x "$ssh_shim"

PATH="$workdir/bin:$PATH" "$wrapper" split right --tty /dev/ttys99999 >/dev/null 2>&1
rc=$?
[[ "$rc" -eq 0 ]] || { print -u2 "split-right: expected exit 0, got $rc"; cat "$GHOSTTY_ZMX_DATA_HOME/.shim-calls" 2>/dev/null; exit 1 }
calls="$(cat "$GHOSTTY_ZMX_DATA_HOME/.shim-calls" 2>/dev/null)"
[[ "$calls" == *"add ws12345678 win12345678 tab1234"* ]] || { print -u2 "split-right: layout-add not called with ws/win/tab: $calls"; exit 1 }
[[ "$calls" == *" horizontal "* ]] || { print -u2 "split-right: axis not horizontal: $calls"; exit 1 }
[[ "$calls" == *" 0.5 present"* ]] || { print -u2 "split-right: ratio/state wrong: $calls"; exit 1 }
[[ "$calls" == *" pane12 "* ]] || { print -u2 "split-right: parent-pane not pane12: $calls"; exit 1 }
echo "  ok: split right records axis=horizontal, parent-pane, ratio=0.5, state=present"

# Reset and test down -> vertical.
rm -f "$GHOSTTY_ZMX_DATA_HOME/.shim-calls"
PATH="$workdir/bin:$PATH" "$wrapper" split down --tty /dev/ttys99999 >/dev/null 2>&1
rc=$?
[[ "$rc" -eq 0 ]] || { print -u2 "split-down: expected exit 0, got $rc"; exit 1 }
calls="$(cat "$GHOSTTY_ZMX_DATA_HOME/.shim-calls" 2>/dev/null)"
[[ "$calls" == *" vertical "* ]] || { print -u2 "split-down: axis not vertical: $calls"; exit 1 }
echo "  ok: split down records axis=vertical"

echo "all split-cli tests passed"
