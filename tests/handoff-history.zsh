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
# runs a marker command, types a handoff command, presses Enter (widget fires),
# then presses Up-arrow and asserts the handoff command, not the marker command,
# is recalled into the buffer.

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

zdot="$workdir/zdot"
mkdir -p "$zdot"
hf="$workdir/.zsh_history"

cat > "$zdot/.zshrc" <<EOF
export HISTFILE='$hf'
rm -f '$hf'
export HISTSIZE=100 SAVEHIST=100
setopt share_history hist_ignore_dups
PS1="P> "
# Mirror the production accept-line widget's history step ONLY: print -s + fc -R.
# No Up-arrow override is installed — the handoff command must be recallable by
# plain up-line-or-history, exactly as if the user had executed it.
gzmx_test_widget() {
  local original_buffer="\$BUFFER"
  print -s -- "\$original_buffer"
  fc -AI "\$HISTFILE" 2>/dev/null || fc -W "\$HISTFILE" 2>/dev/null || true
  fc -R "\$HISTFILE" 2>/dev/null || true
  BUFFER=""
  zle reset-prompt
}
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
inputs = [
    b'print -r -- GZMX_HISTORY_MARKER\r',
    b'tsh ssh pcad-dev\r',
    b'\x1b[A',
]
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
last_prompt = clean.split('P> ')[-1] if 'P> ' in clean else ''
if 'tsh ssh pcad-dev' in last_prompt and 'GZMX_HISTORY_MARKER' not in last_prompt:
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
  _last_history="$(tail -n 1 "$hf" 2>/dev/null)"
  [[ "$_last_history" == ": "*";"* ]] && _last_history="${_last_history#*;}"
  [[ "$_last_history" == "tsh ssh pcad-dev" ]] || {
    print -u2 "FAIL: handoff command was not persisted as latest history entry: $_last_history"
    exit 1
  }
  print "  ok: handoff command persisted as latest history entry"
else
  exit 1
fi

# --- Second assertion: multi-Up/Down traversal after a handoff ---
# Regression: an earlier revision overrode Up-arrow (but not Down) to surface
# the handoff command via a pending-recall short-circuit. That asymmetric
# binding desynced search widgets' internal state after the synthetic recall,
# so pressing Up again did not traverse to older history. The fix removed the
# Up-arrow override entirely; plain up-line-or-history must walk the full
# history (handoff -> CCC -> BBB -> AAA -> BBB -> CCC) just like normal zsh.
workdir2="$(mktemp -d)"
trap 'rm -rf "$workdir2"' EXIT
zdot2="$workdir2/zdot"; mkdir -p "$zdot2"
hf2="$workdir2/.zsh_history"
dumpfile="$workdir2/bufs.txt"; : > "$dumpfile"

cat > "$zdot2/.zshrc" <<EOF
export HISTFILE='$hf2'
rm -f '$hf2'
export HISTSIZE=100 SAVEHIST=100
setopt share_history hist_ignore_dups
PS1="P> "
gzmx_test_widget() {
  local original_buffer="\$BUFFER"
  if [[ "\$BUFFER" == ssh* || "\$BUFFER" == tsh\ ssh* ]]; then
    print -s -- "\$original_buffer"
    fc -AI "\$HISTFILE" 2>/dev/null || fc -W "\$HISTFILE" 2>/dev/null || true
    fc -R "\$HISTFILE" 2>/dev/null || true
    BUFFER=""
    zle reset-prompt
  else
    zle .accept-line
  fi
}
dumpw() { print -rn -- "\$BUFFER" >> "$dumpfile"; printf '\n' >> "$dumpfile"; zle redisplay; }
zle -N gzmx_test_widget; zle -N dumpw
bindkey "^M" gzmx_test_widget; bindkey "^J" gzmx_test_widget
bindkey "^[d" dumpw
EOF

python3 - "$zdot2" <<'PY' || { print -u2 "FAIL: multi-traversal pty harness failed"; exit 1; }
import pty, os, sys, time, select
zdot = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.environ['ZDOTDIR'] = zdot
    os.execvp('zsh', ['zsh', '-i'])
out = b''; t0 = time.time()
# Type three normal commands, then an ssh handoff. Then traverse history with
# Up x4, Down x3, dumping BUFFER after each arrow.
inputs = [b'echo AAA\r', b'echo BBB\r', b'echo CCC\r',
          b'tsh ssh pcad-dev\r',
          b'\x1b[A', b'\x1bd',   # Up1: tsh ssh pcad-dev
          b'\x1b[A', b'\x1bd',   # Up2: echo CCC
          b'\x1b[A', b'\x1bd',   # Up3: echo BBB
          b'\x1b[A', b'\x1bd',   # Up4: echo AAA
          b'\x1b[B', b'\x1bd',   # Down1: echo BBB
          b'\x1b[B', b'\x1bd',   # Down2: echo CCC
          b'\x1b[B', b'\x1bd']   # Down3: (tsh ssh pcad-dev or empty)
idx=0; last=time.time()
while time.time()-t0 < 18:
    r,_,_ = select.select([fd],[],[],0.2)
    if r:
        try: d=os.read(fd,4096)
        except OSError: break
        if not d: break
        out += d
    if idx < len(inputs) and time.time()-last > 0.9:
        os.write(fd, inputs[idx]); idx+=1; last=time.time()
    try:
        wpid,_=os.waitpid(pid, os.WNOHANG)
        if wpid==pid: break
    except ChildProcessError: break
try: os.close(fd)
except: pass
PY

# Assert the recorded traversal matches the expected sequence.
expected=("tsh ssh pcad-dev" "echo CCC" "echo BBB" "echo AAA" "echo BBB" "echo CCC")
actual=()
while IFS= read -r line; do actual+=("$line"); done < "$dumpfile"
if (( ${#actual[@]} < ${#expected[@]} )); then
  print -u2 "FAIL: multi-traversal captured only ${#actual[@]} buffers, expected ${#expected[@]}"
  print -u2 "  got: ${actual[*]}"
  exit 1
fi
fail=0
for ((i=1; i<=${#expected[@]}; i++)); do
  if [[ "${actual[$i]}" != "${expected[$i]}" ]]; then
    print -u2 "FAIL: traversal step $i: expected '${expected[$i]}', got '${actual[$i]}'"
    fail=1
  fi
done
if (( fail )); then
  print -u2 "  full sequence: ${actual[*]}"
  exit 1
fi
print "  ok: multi-Up/Down traversal intact after handoff (no Up-arrow override)"
print "all handoff-history tests passed"
exit 0
