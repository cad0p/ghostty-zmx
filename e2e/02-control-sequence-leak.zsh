#!/bin/zsh
# E2E 02 — tsh OSC 11 / CSI 6n leak fixed via projection wrapper TERM=dumb.
#
# Root cause (confirmed live 2026-07-04): the Teleport `tsh` client emits an
# OSC 11 (foreground-color) and CSI 6n (cursor-position) query to the LOCAL
# terminal on every SSH connection (`tsh ssh -T host /bin/true` emits both;
# plain OpenSSH emits neither). Ghostty answers; in a projection pane the
# local pty IS the zmx pty, so the response echoes into scrollback as stray
# `11;rgb:...1R` characters.
#
# Fix: the projection wrapper (`ghostty-zmx` CLI) sets `TERM=dumb` in its env
# before exec-ing the transport when the transport is `tsh ssh`. tsh gates its
# probe on the local TERM; with TERM=dumb it emits zero queries. tsh does NOT
# forward local TERM to the remote (the remote shell gets TERM from sshd), so
# this only affects tsh's probe — it does NOT cripple the remote shell.
#
# This scenario uses the mock-tsh fixture (which delegates to the sshd fixture
# but asserts TERM=dumb was set) to verify the fix without a real Teleport
# cluster. The mock exits 2 if the wrapper failed to set TERM=dumb.
#
# NOTE: plain-ssh hosts never had this leak (OpenSSH doesn't emit the queries),
# and no real shell plugin emits OSC 11 unpreparedly (zsh-autosuggestions uses
# `fg=8` by default; the dotenv plugin emits CSI 6n but consumes its own
# response). So the tsh fix is the complete fix for the leak. See Goldmine
# debugging/2026-07-04-osc-leak-live-verification-csi-6n-emitter-hunt.
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state
gzmx_e2e_use_mock_tsh
gzmx_e2e_ghostty_launch

# 1. Open a remote projection via mock-tsh. The widget detects `tsh ssh` and
#    builds a projection command whose transport is the mock tsh. The
#    projection wrapper must set TERM=dumb before exec-ing the mock tsh;
#    otherwise the mock exits 2 and the projection pane dies.
sleep 2
gzmx_e2e_type "tsh ssh gzmx-fixture"
gzmx_e2e_wait_remote_clients 1 30
gzmx_e2e_assert_window_count 2
gzmx_e2e_pass "projection opened via mock-tsh (wrapper set TERM=dumb)"

# 2. Verify the remote session is attached (the mock delegated to ssh after
#    the TERM=dumb assertion passed).
local zmx_bin parent_session
zmx_bin="$(gzmx_e2e_fixture_zmx)"
parent_session="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin list 2>/dev/null | grep 'name=gzr-' | head -1" 2>/dev/null \
  | sed -n 's/.*name=\(gzr-[A-Za-z0-9-]*\).*/\1/p')"
[[ -n "$parent_session" ]] || gzmx_e2e_fail "no parent gzr-* session found"
gzmx_e2e_log "parent session: $parent_session"

# 3. Create a native split of the projection pane and let it inherit. The
#    split's projection wrapper must also set TERM=dumb (the inherit path
#    re-execs the wrapper for the tsh transport).
gzmx_e2e_split_focused right
sleep 4
gzmx_e2e_wait_remote_clients 2 30

# 4. Find the child (split) session and verify it attached (split wrapper set
#    TERM=dumb too).
local child_session
child_session="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin list 2>/dev/null | grep 'name=gzr-' | grep -v '$parent_session'" 2>/dev/null \
  | sed -n 's/.*name=\(gzr-[A-Za-z0-9-]*\).*/\1/p' | head -1)"
[[ -n "$child_session" ]] || gzmx_e2e_fail "no child gzr-* session found (split did not inherit or wrapper failed TERM=dumb)"
gzmx_e2e_log "child session: $child_session"
gzmx_e2e_pass "split projection opened via mock-tsh (wrapper set TERM=dumb)"

gzmx_e2e_pass "scenario 02 (tsh OSC 11 / CSI 6n leak fixed via TERM=dumb) complete"
