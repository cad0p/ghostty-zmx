#!/bin/zsh
# E2E 02 — no terminal-query-response leak in remote projection scrollback.
#
# Release-blocking bug: remote shell `.zshrc` startup emits terminal queries
# (OSC 11 foreground-color, CSI 6n cursor-position) whose responses leak
# into the zmx scrollback, appearing as stray `11;rgb:...1R` characters in
# the visible prompt and `zmx history`.
#
# Two leak paths exist:
#   (a) Original projection pane: the remote shell starts fresh over ssh,
#       sends queries, Ghostty responds, and (without mitigation) the
#       responses land in the scrollback capture window.
#   (b) Split/tab pane (inherit path): the new shell starts inside an
#       already-attached zmx session with active scrollback capture, so
#       query responses land during the capture window and appear in
#       `zmx history`.
#
# The fixture's `.zshrc` emits OSC 11 + CSI 6n at interactive startup
# (mirrors pcad-dev's oh-my-zsh + zsh-autosuggestions), so this scenario
# exercises the real leak path deterministically. It asserts no
# query-response bytes (`11;rgb:` / `;rgb:`) in either the original
# projection's or a split's `zmx history`.
source "${0:A:h}/lib/harness.zsh"

gzmx_e2e_init
gzmx_e2e_fixture_sshd_up
gzmx_e2e_fixture_install_server
gzmx_e2e_fixture_reset_server_state
gzmx_e2e_ghostty_launch

# 1. Open a remote projection (ssh handoff). The remote shell's .zshrc emits
#    OSC 11 + CSI 6n at startup; Ghostty answers; the responses would leak
#    into the projection's zmx history without mitigation.
sleep 2
gzmx_e2e_type "ssh -F $GZMX_E2E_SSHCONFIG $GZMX_E2E_FIXTURE_HOST"
gzmx_e2e_wait_remote_clients 1 20
gzmx_e2e_assert_window_count 2

# Give the remote shell init + query/response cycle time to settle.
sleep 4

# 2. Find the original projection session.
local zmx_bin parent_session
zmx_bin="$(gzmx_e2e_fixture_zmx)"
parent_session="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin list 2>/dev/null | grep 'name=gzr-' | head -1" 2>/dev/null \
  | sed -n 's/.*name=\(gzr-[A-Za-z0-9-]*\).*/\1/p')"
[[ -n "$parent_session" ]] || gzmx_e2e_fail "no parent gzr-* session found"
gzmx_e2e_log "parent session: $parent_session"

# 3. Assert NO query-response leak in the original projection's history.
gzmx_e2e_assert_no_query_leak "$parent_session"

# 4. Create a native split of the projection pane and let it inherit. The
#    split's remote shell also emits queries at startup; the inherit path
#    must mitigate the leak there too.
gzmx_e2e_split_focused right
sleep 4
gzmx_e2e_wait_remote_clients 2 20

# 5. Find the child (split) session.
local child_session
child_session="$(ssh -F "$GZMX_E2E_SSHCONFIG" "$GZMX_E2E_FIXTURE_HOST" \
  "$zmx_bin list 2>/dev/null | grep 'name=gzr-' | grep -v '$parent_session'" 2>/dev/null \
  | sed -n 's/.*name=\(gzr-[A-Za-z0-9-]*\).*/\1/p' | head -1)"
[[ -n "$child_session" ]] || gzmx_e2e_fail "no child gzr-* session found (split did not inherit remote context)"
gzmx_e2e_log "child session: $child_session"

# 6. Assert NO query-response leak in the split's history.
gzmx_e2e_assert_no_query_leak "$child_session"

gzmx_e2e_pass "scenario 02 (no control-sequence leak) complete"
