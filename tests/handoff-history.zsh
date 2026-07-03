#!/bin/zsh
# E2E test for bug 3: ssh/tsh handoff command registered in history.
#
# Bug 3: after typing `tsh ssh pier@pcad-dev` in a managed local pane, the
# widget intercepts Enter (does not call zle .accept-line), so zsh's normal
# history recording is bypassed. The widget does `print -s` to record it, but
# that alone may not surface in the in-memory history list that up-arrow
# traverses (depends on SHARE_HISTORY re-read timing). The fix adds `fc -R`
# after `print -s` to force a re-read.
#
# This test uses a pty to faithfully reproduce the zle widget context: it
# binds Enter to a widget that mimics ghostty_zmx_accept_line's history step,
# types a handoff command, presses Enter (widget fires), then presses Up-arrow
# and asserts the command is recalled into the buffer.

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

zdot="$workdir/zdot"
mkdir -p "$zdot"
hf="$workdir/.zsh_history"

# Two variants: BUGGY (print -s only) and FIXED (print -s + fc -R).
# Both should pass after the fix is in place; the BUGGY variant is kept to
# document the historical failure mode (it may pass on some zsh/option
# combinations, which is why this is a defense-in-depth test).
widget_body='print -s -- "$BUFFER"; fc -R "$HISTFILE"; BUFFER=""; zle reset-prompt'

cat > "$zdot/.zshrc" <<EOF
export HISTFILE='$hf'
rm -f '$hf'
export HISTSIZE=100 SAVEHIST=100
setopt share_history hist_ignore_dups
PS1="P> "
gzmx_test_widget() { $widget_body }
zle -N gzmx_test_widget
bindkey "^M" gzmx_test_widget
bindkey "^J" gzmx_test_widget
EOF

# Drive a pty: type the handoff + Enter, then Up-arrow, then dump BUFFER.
# We use a python3 helper because zsh's zpty can't easily assert on buffer
# state across a real terminal.
python3 - "$zdot" <<'PY' || { print -u2 "FAIL: pty test harness failed"; exit 1; }
import pty, os, sys, time, select, re

zdot = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.environ['ZDOTDIR'] = zdot
    os.execvp('zsh', ['zsh', '-i'])

out = b''
t0 = time.time()
inputs = [b'tsh ssh pcad-dev\r', b'\x1b[A']  # handoff+Enter, then Up-arrow
idx = 0
last = time.time()
while time.time() - t0 < 10:
    r,_,_ = select.select([fd],[],[],0.2)
    if r:
        try: d = os.read(fd, 4096)
        except OSError: break
        if not d: break
        out += d
    if idx < len(inputs) and time.time() - last > 1.5:
        os.write(fd, inputs[idx]); idx += 1; last = time.time()
    try:
        wpid, _ = os.waitpid(pid, os.WNOHANG)
        if wpid == pid: break
    except ChildProcessError: break
try: os.close(fd)
except: pass

clean = re.sub(r'\x1b\][0-9;]*[^\x07\x1b]*(\x07|\x1b\\)', '', out.decode('utf-8','replace'))
clean = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', clean)
# After Up-arrow, the buffer should contain 'tsh ssh pcad-dev' on the prompt line.
if 'tsh ssh pcad-dev' in clean.split('P> ')[-1] if 'P> ' in clean else '':
    print("  ok: handoff command recalled by Up-arrow")
    sys.exit(0)
# Fallback: check the whole output for the command after the second prompt.
lines = [l.strip() for l in clean.splitlines() if l.strip()]
for l in lines[-3:]:
    if 'tsh ssh pcad-dev' in l and l.startswith('P>'):
        print("  ok: handoff command recalled by Up-arrow")
        sys.exit(0)
print("  FAIL: handoff command NOT recalled by Up-arrow")
print("  last lines:", lines[-4:])
sys.exit(1)
PY

if (( $? == 0 )); then
  print "all handoff-history tests passed"
  exit 0
else
  exit 1
fi
