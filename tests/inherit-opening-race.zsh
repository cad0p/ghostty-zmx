#!/bin/zsh
# Unit test for the split-inherit race where the parent pane's projection row
# is still `opening` with tty_path="-" (poller hasn't upgraded it to `attached`
# with the real tty) when a split fires.
#
# Verifies the inherit loop recovers the real tty via
# ghostty_zmx_find_live_projection (same pattern as local_win="-") so the
# best-parent-tty comparison matches the true parent instead of skipping its
# row (which previously caused inherit to fall through to a local zmx session).
set -u

repo_dir="${0:A:h:h}"
cd "$repo_dir"

fails=0
fail() { print -u2 "inherit-opening-race test failed: $*"; fails=$((fails+1)); }

# Source the lib FIRST, then override the functions it calls. (Defining stubs
# before sourcing the lib gets them clobbered by the lib's definitions.)
source ./session-manager-lib.zsh

# Stub: pretend a live projection exists for any session, returning a known
# tty/win/tab. This simulates the poller's scan finding the running wrapper
# process even though the projection row still says tty="-".
_gzmx_stub_tty="/dev/ttysFAKE"
_gzmx_stub_win="6000FAKEWIN00"
_gzmx_stub_tab="6000FAKEKTAB0"

# Track whether find_live_projection was called during the inherit attempt.
_find_live_called=0

ghostty_zmx_find_live_projection() {
  _find_live_called=1
  _gzmx_found_pid="12345"
  _gzmx_found_match_pid="12346"
  _gzmx_found_tty="$_gzmx_stub_tty"
  _gzmx_found_win="$_gzmx_stub_win"
  _gzmx_found_tab="$_gzmx_stub_tab"
  return 0
}

# Stub the sibling enumeration: pretend there IS a sibling (the parent pane)
# at the known tty, distinct from the new split's cur_tty.
ghostty_zmx_find_sibling_tty() { print -r -- "$_gzmx_stub_tty"; return 0; }
ghostty_zmx_select_parent_by_recency() { print -r -- "$_gzmx_stub_tty"; return 0; }

# Stub remote side effects so the loop runs purely locally.
ghostty_zmx_remote_prefix_for_host() { print -r -- "ssh -t fixture-host"; }
ghostty_zmx_notty_prefix() { print -r -- "ssh fixture-host"; }
ghostty_zmx_remote_layout_helper_cmd() { print -r -- "/bin/true"; }
ghostty_zmx_projection_lock_path() { print -r -- "/tmp/gzmx-fake-inherit-race.lock"; }
ghostty_zmx_write_projection_row() { return 0; }
ghostty_zmx_remote_projections_file() { print -r -- "/tmp/gzmx-fake-inherit-race-projections"; }
ghostty_zmx_remote_hosts_file() { print -r -- "/tmp/gzmx-fake-inherit-race-hosts"; }
ghostty_zmx_remote_zmx_for_host() { print -r -- "zmx"; }
ghostty_zmx_enumerate_terminals() { :; }
ghostty_zmx_hex_suffix() { print -r -- "$1"; }

# Point the wrapper at a NON-executable path so the inherit loop reaches the
# "inherit match" point but then fails at the wrapper-existence guard (which
# returns 1 AFTER recording the match). This lets us observe the match.
ghostty_zmx_wrapper_path() { print -r -- "/nonexistent/no-such-wrapper"; }

# Capture whether "inherit match" was reached (the row was NOT skipped as
# nonbest). Without the fix, the opening row's tty="-" fails the best-parent
# comparison and the row is skipped (no match).
_match_reached=0
_ghostty_zmx_debug() {
  case "$1" in
    "inherit match"*) _match_reached=1 ;;
    "inherit skip-nonbest"*) _match_reached=0 ;;
  esac
}

# Build a fake remote-projections file with ONE `opening` row whose tty_path
# is "-" (the race: poller hasn't upgraded it yet).
fake_proj="/tmp/gzmx-fake-inherit-race-projections"
fake_host="fixture-host"
fake_workspace="wsk00001"
fake_session="gzr-wsk00001-win00001-tab0001-pane001"
print -r -- "${fake_host}	${fake_workspace}	${fake_session}	-	-	opening	1234	${_gzmx_stub_win}	${_gzmx_stub_tab}" > "$fake_proj"

# Use /dev/null as cur_tty: it is readable+writable so the inherit loop's
# usable-tty guard ([[ -r "$cur_tty" && -w "$cur_tty" ]]) passes. The final
# `exec ... <"$cur_tty" >"$cur_tty"` never runs (we stubbed the wrapper to a
# nonexistent path, so the loop returns at the wrapper-existence guard before
# exec), so /dev/null's lack of a real pty is irrelevant.
new_identity="${_gzmx_stub_win} ${_gzmx_stub_tab} TERMHASH 99999 /dev/null"

# Run inherit. It should:
# 1. find_sibling_tty -> _gzmx_stub_tty (single sibling)
# 2. the loop reads the opening row (tty_path="-")
# 3. find_live_projection IS called (recovery), recovering tty to _gzmx_stub_tty
# 4. the best-parent comparison PASSES (recovered tty == best parent)
# 5. "inherit match" is recorded
# 6. wrapper-existence check fails -> returns 1 (expected, we stubbed it away)
ghostty_zmx_inherit_remote_context_if_any "$new_identity" >/dev/null 2>&1 || true

(( _find_live_called == 1 )) || fail "find_live_projection was NOT called for the opening row (tty recovery missing)"
(( _match_reached == 1 )) || fail "opening-row tty was NOT recovered; inherit did not match the parent (the split-inherit race)"
print "  ok: find_live_projection called for opening row (tty recovery active)"
print "  ok: opening-row tty recovered; parent matched (split-inherit race fixed)"

rm -f "$fake_proj"
(( fails == 0 )) || exit 1
print "all inherit-opening-race tests passed (2/2)"
