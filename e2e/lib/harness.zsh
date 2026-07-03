#!/bin/zsh
# ghostty-zmx E2E harness library.
#
# Provides reusable functions for disposable Ghostty-tip E2E scenarios:
#   - fixture lifecycle (sshd Docker container up/down)
#   - disposable state (GHOSTTY_ZMX_DATA_HOME / STATE_HOME tmpdirs)
#   - Ghostty-tip launch with a disposable config (no user-session disruption)
#   - AppleScript input injection + assertions
#   - remote-state assertions (zmx list, remote-layout read)
#
# Sourced by individual e2e/*.zsh scenario scripts. Never sourced by unit tests
# (tests/) — this library drives a live Ghostty process and Docker containers.
#
# Usage in a scenario:
#   source "${0:A:h}/lib/harness.zsh"
#   gzmx_e2e_init
#   gzmx_e2e_fixture_sshd_up
#   gzmx_e2e_ghostty_launch
#   gzmx_e2e_type "ssh gzmx-fixture"
#   gzmx_e2e_assert_remote_clients 1
#   gzmx_e2e_cleanup

emulate -L zsh
setopt local_options no_sh_word_split err_return

# --- configuration -----------------------------------------------------------

GZMX_E2E_GHOSTTY_APP=${GHOSTTY_APP_NAME:-Ghostty-tip}
GZMX_E2E_GHOSTTY_BIN="/Applications/${GZMX_E2E_GHOSTTY_APP}.app/Contents/MacOS/${GZMX_E2E_GHOSTTY_APP}"
GZMX_E2E_REPO_DIR="${0:A:h:h:h}"
GZMX_E2E_FIXTURE_DIR="$GZMX_E2E_REPO_DIR/e2e/fixtures/sshd"
GZMX_E2E_SSH_PORT=${GZMX_E2E_SSH_PORT:-2222}
GZMX_E2E_FIXTURE_HOST="gzmx-fixture"
GZMX_E2E_TMPDIR=""
GZMX_E2E_DATA_HOME=""
GZMX_E2E_STATE_HOME=""
GZMX_E2E_GHOSTTY_PID=""
GZMX_E2E_SSHCONFIG=""
GZMX_E2E_STARTED_DOCKER=0
GZMX_E2E_STARTED_GHOSTTY=0

# --- logging -----------------------------------------------------------------

gzmx_e2e_log() { print -P -- "%F{blue}e2e%f $*" >&2 }
gzmx_e2e_pass() { print -P -- "%F{green}✓ PASS%f $*" >&2 }
gzmx_e2e_fail() {
  print -P -- "%F{red}✗ FAIL%f $*" >&2
  gzmx_e2e_cleanup
  exit 1
}
gzmx_e2e_warn() { print -P -- "%F{yellow}! warn%f $*" >&2 }

# --- lifecycle ---------------------------------------------------------------

gzmx_e2e_init() {
  emulate -L zsh
  GZMX_E2E_TMPDIR="$(mktemp -d /tmp/gzmx-e2e-XXXXXX)"
  GZMX_E2E_DATA_HOME="$GZMX_E2E_TMPDIR/data"
  GZMX_E2E_STATE_HOME="$GZMX_E2E_TMPDIR/state"
  mkdir -p "$GZMX_E2E_DATA_HOME" "$GZMX_E2E_STATE_HOME"
  GZMX_E2E_SSHCONFIG="$GZMX_E2E_TMPDIR/sshconfig"
  gzmx_e2e_log "tmpdir=$GZMX_E2E_TMPDIR"
}

# Bring up the sshd Docker fixture if not already running. Writes an sshconfig
# that maps GZMX_E2E_FIXTURE_HOST to localhost:GZMX_E2E_SSH_PORT using the
# fixture's generated key. Idempotent: if a container with our name is already
# up, reuses it.
gzmx_e2e_fixture_sshd_up() {
  emulate -L zsh
  # Already running?
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx ghostty-zmx-sshd-fixture; then
    gzmx_e2e_log "sshd fixture already running"
  else
    gzmx_e2e_log "starting sshd fixture"
    ( cd "$GZMX_E2E_FIXTURE_DIR" && ./up.sh ) || gzmx_e2e_fail "sshd fixture up failed"
    GZMX_E2E_STARTED_DOCKER=1
  fi
  # Write a disposable sshconfig pointing at the fixture.
  local key="$GZMX_E2E_FIXTURE_DIR/id_ed25519"
  [[ -r "$key" ]] || key="$GZMX_E2E_FIXTURE_DIR/id_ed25519.pub"
  # up.sh generates id_ed25519 (private) + .pub; use the private key.
  key="$GZMX_E2E_FIXTURE_DIR/id_ed25519"
  [[ -r "$key" ]] || gzmx_e2e_fail "fixture ssh key missing: $key"
  cat > "$GZMX_E2E_SSHCONFIG" <<EOF
Host $GZMX_E2E_FIXTURE_HOST
  HostName 127.0.0.1
  Port $GZMX_E2E_SSH_PORT
  User gzmx
  IdentityFile $key
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
  # Smoke-test the fixture.
  ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" 'echo fixture-ok' >/dev/null 2>&1 \
    || gzmx_e2e_fail "cannot reach sshd fixture"
  gzmx_e2e_log "sshd fixture reachable"
}

gzmx_e2e_fixture_sshd_down() {
  emulate -L zsh
  [[ "$GZMX_E2E_STARTED_DOCKER" == "1" ]] || return 0
  gzmx_e2e_log "stopping sshd fixture"
  ( cd "$GZMX_E2E_FIXTURE_DIR" && ./down.sh ) 2>/dev/null || true
}

# Install ghostty-zmx server-side files on the sshd fixture via the tar-over-ssh
# bootstrap (mirrors `ghostty-zmx install-server` but standalone).
gzmx_e2e_fixture_install_server() {
  emulate -L zsh
  local install_dir="$HOME/.config/ghostty-zmx"
  [[ -d "$install_dir" ]] || gzmx_e2e_fail "laptop install missing; run ghostty-zmx install first"
  local tmpdir="/tmp/ghostty-zmx-server-install.e2e.$$"
  local -a remote_cmd=(
    "set -e"
    "tmpdir='$tmpdir'"
    "rm -rf \"\$tmpdir\""
    "mkdir -p \"\$tmpdir\""
    "cd \"\$tmpdir\""
    "tar xzf -"
    "./install-server.sh --yes"
    "rc=$?"
    "cd /"
    "rm -rf \"\$tmpdir\""
    "exit \$rc"
  )
  COPYFILE_DISABLE=1 tar --no-mac-metadata --format ustar -czf - \
    -C "$install_dir" \
    install-server.sh session-manager.zsh session-manager-lib.zsh \
    ghostty-zmx-remote-layout terminfo/xterm-ghostty.terminfo 2>/dev/null \
    | ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" "${(j:;:)remote_cmd}" \
    || gzmx_e2e_fail "server install on fixture failed"
  gzmx_e2e_log "server files installed on fixture"
}

# Launch Ghostty-tip with disposable env. Does NOT use -e /bin/zsh (triggers
# macOS execute prompt). Returns as soon as Ghostty reports a version via
# AppleScript (surface registration stable). Records the PID for cleanup.
gzmx_e2e_ghostty_launch() {
  emulate -L zsh
  [[ -x "$GZMX_E2E_GHOSTTY_BIN" ]] || gzmx_e2e_fail "Ghostty binary not found: $GZMX_E2E_GHOSTTY_BIN"
  # Pre-seed remote-hosts so the poller knows the fixture transport.
  printf '%s\tssh\t0.6.0\tactive\tssh -t -F %s %s\n' \
    "$GZMX_E2E_FIXTURE_HOST" "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    > "$GZMX_E2E_DATA_HOME/remote-hosts"
  open -na "/Applications/${GZMX_E2E_GHOSTTY_APP}.app" --args \
    --env=GHOSTTY_ZMX_AUTO_ATTACH=1 \
    --env=GHOSTTY_ZMX_DEBUG=1 \
    --env=GHOSTTY_ZMX_DATA_HOME="$GZMX_E2E_DATA_HOME" \
    --env=GHOSTTY_ZMX_STATE_HOME="$GZMX_E2E_STATE_HOME" \
    --window-save-state=never \
    --confirm-close-surface=false
  GZMX_E2E_STARTED_GHOSTTY=1
  # Wait for Ghostty to be AppleScript-addressable and report a surface.
  local i
  for (( i=1; i<=40; i++ )); do
    if osascript -e "tell application \"$GZMX_E2E_GHOSTTY_APP\" to get version" >/dev/null 2>&1; then
      GZMX_E2E_GHOSTTY_PID="$(pgrep -f "/Applications/${GZMX_E2E_GHOSTTY_APP}.app/Contents/MacOS" | head -1)"
      [[ -n "$GZMX_E2E_GHOSTTY_PID" ]] && break
    fi
    sleep 0.5
  done
  [[ -n "$GZMX_E2E_GHOSTTY_PID" ]] || gzmx_e2e_fail "Ghostty did not launch"
  # Wait for at least one window + a focused terminal.
  for (( i=1; i<=40; i++ )); do
    local wc="$(osascript -e "tell application \"$GZMX_E2E_GHOSTTY_APP\" to count of windows" 2>/dev/null)"
    [[ "$wc" == <-> && "$wc" -ge 1 ]] && break
    sleep 0.5
  done
  gzmx_e2e_log "Ghostty launched pid=$GZMX_E2E_GHOSTTY_PID"
}

# Quit the disposable Ghostty we launched (do NOT touch a user's real session).
gzmx_e2e_ghostty_quit() {
  emulate -L zsh
  [[ "$GZMX_E2E_STARTED_GHOSTTY" == "1" ]] || return 0
  [[ -n "$GZMX_E2E_GHOSTTY_PID" ]] || return 0
  # Kill only the PID we launched, by exact match.
  kill "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || true
  # Wait for it to exit.
  local i
  for (( i=1; i<=20; i++ )); do
    kill -0 "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || break
    sleep 0.25
  done
  kill -9 "$GZMX_E2E_GHOSTTY_PID" 2>/dev/null || true
  GZMX_E2E_STARTED_GHOSTTY=0
}

# --- input injection ---------------------------------------------------------

# Type text into the focused terminal of the front window and press Enter.
gzmx_e2e_type() {
  emulate -L zsh
  local text="$1"
  osascript <<OSA 2>/dev/null
tell application "$GZMX_E2E_GHOSTTY_APP"
  set w to front window
  set tb to selected tab of w
  set tm to focused terminal of tb
  input text "$text" to tm
  send key "enter" to tm
end tell
OSA
}

# Type text WITHOUT pressing Enter (for pre-fill scenarios).
gzmx_e2e_type_no_enter() {
  emulate -L zsh
  local text="$1"
  osascript <<OSA 2>/dev/null
tell application "$GZMX_E2E_GHOSTTY_APP"
  set w to front window
  set tb to selected tab of w
  set tm to focused terminal of tb
  input text "$text" to tm
end tell
OSA
}

# Send a Ghostty key (e.g. "cmd+d", "cmd+t", "cmd+shift+d") to the focused terminal.
gzmx_e2e_send_key() {
  emulate -L zsh
  local key="$1"
  osascript <<OSA 2>/dev/null
tell application "$GZMX_E2E_GHOSTTY_APP"
  set w to front window
  set tb to selected tab of w
  set tm to focused terminal of tb
  send key "$key" to tm
end tell
OSA
}

# --- assertions --------------------------------------------------------------

# Assert the number of windows reported by Ghostty.
gzmx_e2e_assert_window_count() {
  emulate -L zsh
  local expected="$1" actual
  actual="$(osascript -e "tell application \"$GZMX_E2E_GHOSTTY_APP\" to count of windows" 2>/dev/null)"
  [[ "$actual" == "$expected" ]] \
    || gzmx_e2e_fail "window count: expected $expected, got $actual"
  gzmx_e2e_pass "window count == $expected"
}

# Wait up to N seconds for a condition (function name) to return 0.
gzmx_e2e_wait_for() {
  emulate -L zsh
  local seconds="$1" cond_fn="$2"
  local i
  for (( i=1; i<=seconds*4; i++ )); do
    "$cond_fn" && return 0
    sleep 0.25
  done
  return 1
}

# Assert the fixture has N attached clients on gzr-* sessions.
gzmx_e2e_assert_remote_clients() {
  emulate -L zsh
  local expected="$1" actual
  actual="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
    'zmx list 2>/dev/null | grep "^gzr-" | grep -c "clients=[1-9]"' 2>/dev/null)"
  [[ "$actual" == "$expected" ]] \
    || gzmx_e2e_fail "remote clients: expected $expected, got $actual"
  gzmx_e2e_pass "remote clients == $expected"
}

# Wait for N attached remote clients (polls, since attach is async over ssh).
gzmx_e2e_wait_remote_clients() {
  emulate -L zsh
  local expected="$1" seconds="${2:-30}" actual
  local i
  for (( i=1; i<=seconds*4; i++ )); do
    actual="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
      'zmx list 2>/dev/null | grep "^gzr-" | grep -c "clients=[1-9]"' 2>/dev/null)"
    [[ "$actual" == "$expected" ]] && { gzmx_e2e_pass "remote clients == $expected (after ${i} polls)"; return 0; }
    sleep 0.25
  done
  gzmx_e2e_fail "remote clients never reached $expected (last=$actual)"
}

# Assert a marker string is present in a remote session's zmx history (scrollback).
gzmx_e2e_assert_remote_history_contains() {
  emulate -L zsh
  local session="$1" marker="$2" hist
  hist="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" "zmx history $session 2>/dev/null")"
  [[ "$hist" == *"$marker"* ]] \
    || gzmx_e2e_fail "marker '$marker' not in $session history"
  gzmx_e2e_pass "marker '$marker' found in $session history"
}

# Assert NO control-sequence leak (OSC 11 / CSI 6n response bytes) in a remote
# session's zmx history. The leak manifests as `11;rgb:...1R` or `;rgb:...` in
# the scrollback.
gzmx_e2e_assert_no_query_leak() {
  emulate -L zsh
  local session="$1" hist
  hist="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" "zmx history $session 2>/dev/null")"
  # OSC 11 response: "11;rgb:rrrr/gggg/bbbb" ; CSI 6n response: "<n>;<m>R" tail "1R"
  if [[ "$hist" == *"11;rgb:"* || "$hist" == *";rgb:"* ]]; then
    print -r -- "$hist" | grep -E "11;rgb:|;rgb:" | head -3 >&2
    gzmx_e2e_fail "query-response leak detected in $session history"
  fi
  gzmx_e2e_pass "no query-response leak in $session history"
}

# Assert the remote shell's cwd (via OSC 7 in zmx history, or `zmx run` pwd) for a session.
gzmx_e2e_assert_remote_cwd() {
  emulate -L zsh
  local session="$1" expected="$2" actual
  # Use zmx run to print pwd in the session's shell (non-interactive).
  actual="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" "zmx run $session pwd 2>/dev/null" 2>/dev/null)"
  [[ "$actual" == "$expected" ]] \
    || gzmx_e2e_fail "remote cwd: expected $expected, got $actual"
  gzmx_e2e_pass "remote cwd == $expected"
}

# --- debug -------------------------------------------------------------------

gzmx_e2e_debug_tail() {
  emulate -L zsh
  local n="${1:-40}"
  gzmx_e2e_log "debug.log tail:"
  tail -n "$n" "$GZMX_E2E_STATE_HOME/debug.log" 2>/dev/null >&2 || print "  (no debug.log)" >&2
}

# --- cleanup -----------------------------------------------------------------

gzmx_e2e_cleanup() {
  emulate -L zsh
  setopt local_options no_err_return
  gzmx_e2e_ghostty_quit
  gzmx_e2e_fixture_sshd_down
  [[ -n "$GZMX_E2E_TMPDIR" ]] && rm -rf "$GZMX_E2E_TMPDIR" 2>/dev/null
}

# Install cleanup on exit (normal or signal).
trap 'gzmx_e2e_cleanup' INT TERM HUP EXIT
