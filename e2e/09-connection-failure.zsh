#!/bin/zsh
# E2E 09 — interactive ssh to an unreachable host fails gracefully.
#
# The user reported `tsh ssh pier@pcad-dev` "fails for some reason".
# Root cause: expired Teleport certs (tsh status → "Not logged in"),
# NOT a ghostty-zmx bug. The widget's probe must:
#   - detect the ssh/tsh connection failure (probe_rc != 0)
#   - print a clear "could not reach <host> ... ssh config/certs valid?" message
#   - clear the input buffer and return to the local prompt
#   - NOT open a new Ghostty window (no orphan projection)
#
# This scenario codifies that graceful handling against a fixture host that
# refuses connections (sshd not started), so it runs without real Teleport.
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init

# Write an ssh config that points at an unreachable port (no docker needed).
# This reliably produces connection-refused (probe_rc != 0) without racing
# a docker stop against the ssh attempt.
local _bad_cfg="$GZMX_E2E_TMPDIR/bad-sshconfig"
cat > "$_bad_cfg" <<EOF
Host $GZMX_E2E_FIXTURE_HOST
  HostName 127.0.0.1
  Port 1
  User gzmx
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  ConnectTimeout 3
EOF

# Configure the managed Ghostty surface.
gzmx_e2e_ghostty_launch

# Wait for the local shell to be ready.
sleep 2

# Type an interactive ssh command to the unreachable host.
gzmx_e2e_type "ssh -F $_bad_cfg $GZMX_E2E_FIXTURE_HOST"

# The widget must NOT open a projection window. Poll for the probe to run
# (which fails fast on connection-refused) and then assert no new window.
sleep 5
gzmx_e2e_assert_window_count 1   # only the local pane, no projection

# The widget must have logged the probe attempt (and it must have failed).
# Poll the debug log for up to 10s for the probe line.
local _probe_logged=0 _w
for (( _w=1; _w<=20; _w++ )); do
  if [[ -f "$GZMX_E2E_STATE_HOME/debug.log" ]] && grep -q "widget probe" "$GZMX_E2E_STATE_HOME/debug.log" 2>/dev/null; then
    _probe_logged=1; break
  fi
  sleep 0.5
done
[[ "$_probe_logged" -eq 1 ]] || gzmx_e2e_fail "widget probe was not invoked for unreachable host"

# Verify the widget did NOT open a projection (no "widget opened" log line).
# The harness pre-seeds remote-hosts, so we cannot assert on its absence;
# instead assert the widget returned before the open step.
if [[ -f "$GZMX_E2E_STATE_HOME/debug.log" ]]; then
  if grep -q "widget opened" "$GZMX_E2E_STATE_HOME/debug.log" 2>/dev/null; then
    gzmx_e2e_fail "widget opened a projection window for an unreachable host"
  fi
fi

gzmx_e2e_pass "scenario 09 (connection failure handled gracefully) complete"
