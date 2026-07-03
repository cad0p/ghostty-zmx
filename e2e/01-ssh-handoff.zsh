#!/bin/zsh
# E2E 01 — interactive ssh handoff opens a remote projection.
#
# Typing `ssh <fixture-host>` in a managed local pane must:
#   - open a new Ghostty window
#   - attach to a gzr-* remote zmx session (clients=1)
#   - leave the original local pane at its prompt
#   - record the host in remote-hosts
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_ghostty_launch

# Wait for the local shell to be ready, then type the ssh command.
sleep 2
gzmx_e2e_type "ssh -F $GZMX_E2E_SSHCONFIG $GZMX_E2E_FIXTURE_HOST"

# A new window should open and attach within ~15s.
gzmx_e2e_wait_remote_clients 1 20
gzmx_e2e_assert_window_count 2   # local + projection

# Verify remote-hosts was recorded.
grep -qx "$GZMX_E2E_FIXTURE_HOST	ssh.*$GZMX_E2E_FIXTURE_HOST" "$GZMX_E2E_DATA_HOME/remote-hosts" \
  || gzmx_e2e_fail "remote-hosts not updated"

gzmx_e2e_pass "scenario 01 (ssh handoff) complete"
