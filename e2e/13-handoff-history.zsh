#!/bin/zsh
# E2E 13 — ssh handoff commands are immediately recallable with Up-arrow.
#
# The accept-line widget intercepts interactive ssh/tsh handoffs and therefore
# skips zsh's normal accept-line history write. It must push the handoff command
# into both the history file and the in-memory history list so Up-arrow restores
# the ssh command, not the command that ran before it.
#
# This scenario covers:
#   - happy ssh handoff probe/branch to the fixture,
#   - connection failure,
#   - reachable host with no zmx,
#   - reachable host with the wrong zmx version.
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state

# Put a deterministic ssh shim first on PATH. It delegates normal fixture
# traffic to /usr/bin/ssh, but returns controlled probe results for failure
# hosts so the scenario can exercise all probe failure modes without extra
# remote machines.
mkdir -p "$GZMX_E2E_DATA_HOME/bin"
cat > "$GZMX_E2E_DATA_HOME/bin/ssh" <<'EOF'
#!/bin/zsh
set -u
host=""
expect_arg=0
for arg in "$@"; do
  if (( expect_arg )); then
    expect_arg=0
    continue
  fi
  case "$arg" in
    -F|-i|-l|-p|-J|-o|-S|-b|-c|-m|-W|-L|-R|-D)
      expect_arg=1
      continue
      ;;
    -t|-tt|-T|--tty)
      continue
      ;;
    -*)
      continue
      ;;
    *)
      host="$arg"
      break
      ;;
  esac
done

case "$host" in
  history-unreachable)
    exit 255
    ;;
  history-no-zmx)
    print -r -- "no-zmx"
    exit 0
    ;;
  history-old-zmx)
    print -r -- "zmx-path:/tmp/fake-zmx"
    print -r -- $'zmx:zmx\t0.5.0'
    exit 0
    ;;
esac

exec /usr/bin/ssh "$@"
EOF
chmod 0755 "$GZMX_E2E_DATA_HOME/bin/ssh"
cat > "$GZMX_E2E_DATA_HOME/e2e-path.zsh" <<EOF
export PATH="$GZMX_E2E_DATA_HOME/bin:\$PATH"
EOF

gzmx_e2e_ghostty_launch
sleep 2

local local_session local_window_id
local_session="$(gzmx_e2e_local_session)" || gzmx_e2e_fail "local zmx session not recorded"
local_window_id="$(gzmx_e2e_front_window_id)"
[[ -n "$local_window_id" ]] || gzmx_e2e_fail "local Ghostty window id not recorded"
gzmx_e2e_log "local session: $local_session"
gzmx_e2e_log "local window id: $local_window_id"

_assert_recall() {
  emulate -L zsh
  local label="$1" command="$2" expected_windows="$3"
  local marker="GZMX_E2E_HISTORY_MARKER_${label}_$$"
  local recall="GZMX_E2E_RECALL_${label}:"
  local expected="${recall}${command}"

  gzmx_e2e_type_in_window_id_direct "$local_window_id" "print -r -- $marker"
  sleep 1
  gzmx_e2e_type_in_window_id_direct "$local_window_id" "$command"
  if [[ "$label" == "happy" ]]; then
    gzmx_e2e_wait_remote_clients 1 30
  else
    sleep 4
  fi

  gzmx_e2e_assert_window_count "$expected_windows"

  # Recall the previous command in the local pane, move to the beginning, and
  # prefix it with a print command. If Up-arrow recalled the marker command,
  # the output starts with "$recall print -r -- $marker"; if it recalled the
  # handoff, the output starts with "$recall$command".
  gzmx_e2e_terminal_control_in_window_id "$local_window_id" "up"
  sleep 0.5
  gzmx_e2e_terminal_control_in_window_id "$local_window_id" "ctrl-a"
  sleep 0.25
  gzmx_e2e_type_in_window_id_direct "$local_window_id" "print -r -- $recall"

  _recall_seen() {
    local hist
    hist="$(gzmx_e2e_local_history_compact "$local_session")"
    [[ "$hist" == *"$expected"* ]]
  }
  gzmx_e2e_wait_for 10 _recall_seen || {
    print -r -- "$(gzmx_e2e_local_history_compact "$local_session")" | tail -c 2000 >&2
    gzmx_e2e_fail "Up-arrow did not recall handoff command for $label"
  }

  local compact
  compact="$(gzmx_e2e_local_history_compact "$local_session")"
  [[ "$compact" != *"${recall}print -r -- $marker"* ]] \
    || gzmx_e2e_fail "Up-arrow recalled marker command instead of handoff for $label"
  gzmx_e2e_pass "Up-arrow recalls handoff command after $label"
}

local happy_cmd="ssh -F $GZMX_E2E_SSHCONFIG $GZMX_E2E_FIXTURE_HOST"
_assert_recall "happy" "$happy_cmd" 2
_assert_recall "unreachable" "ssh history-unreachable" 2
_assert_recall "no_zmx" "ssh history-no-zmx" 2
_assert_recall "wrong_zmx" "ssh history-old-zmx" 2

if [[ -f "$GZMX_E2E_STATE_HOME/debug.log" ]]; then
  grep -q "widget probe-ok host=$GZMX_E2E_FIXTURE_HOST" "$GZMX_E2E_STATE_HOME/debug.log" \
    || gzmx_e2e_fail "missing happy probe-ok log"
  grep -q "widget probe host=history-unreachable" "$GZMX_E2E_STATE_HOME/debug.log" \
    || gzmx_e2e_fail "missing unreachable probe log"
  grep -q "widget probe host=history-no-zmx" "$GZMX_E2E_STATE_HOME/debug.log" \
    || gzmx_e2e_fail "missing no-zmx probe log"
  grep -q "widget probe host=history-old-zmx" "$GZMX_E2E_STATE_HOME/debug.log" \
    || gzmx_e2e_fail "missing wrong-version probe log"
fi

gzmx_e2e_pass "scenario 13 (handoff history recall) complete"
