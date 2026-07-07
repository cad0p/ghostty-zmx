#!/bin/zsh
# E2E 04 — interactive `tsh ssh` handoff opens a remote projection.
#
# Typing `tsh ssh <fixture-host>` in a managed local pane must:
#   - open a new Ghostty window
#   - attach to a gzr-* remote zmx session (clients=1)
#   - leave the original local pane at its prompt
#   - record the host in remote-hosts with transport=tsh
#
# This exercises the widget's tsh code path (parsing `tsh ssh`, probe without
# -T, projection command with `tsh ssh -t` prefix) against a mock-tsh fixture
# that delegates to the sshd fixture. A real Teleport cluster Docker fixture
# was attempted but fights tsh client/server version mismatches (laptop tsh v18
# vs Teleport v14 image = ALPN/grpc handshake failure) unrelated to ghostty-zmx.
# The mock exercises the same widget branches a real tsh would.
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state
gzmx_e2e_use_mock_tsh
gzmx_e2e_ghostty_launch

# Wait for the local shell to be ready, then type the tsh command.
sleep 2
gzmx_e2e_type "tsh ssh $GZMX_E2E_FIXTURE_HOST"

# A new window should open and attach within ~20s.
gzmx_e2e_wait_remote_clients 1 20
gzmx_e2e_assert_window_count 2   # local + projection

# Verify remote-hosts was recorded with transport=tsh.
_transport="$(awk -F '\t' -v h="$GZMX_E2E_FIXTURE_HOST" '$1 == h { print $2 }' "$GZMX_E2E_DATA_HOME/remote-hosts")"
[[ "$_transport" == "tsh" ]] \
  || gzmx_e2e_fail "remote-hosts transport not tsh (got: $_transport)"

gzmx_e2e_pass "scenario 04 (tsh handoff) complete"
