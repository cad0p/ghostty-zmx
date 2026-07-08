#!/bin/zsh
# Unit test for ghostty_zmx_descendants_matching: the root pid itself must NOT
# be returned as a match even when its own `ps args` contain the needle.
#
# Ghostty reports the terminal pid, which (when a surface command is set) is
# the `login` process. login's args contain the full command string —
# including `--session <gzr>` — because it is all passed as the `-c` argument.
# Checking the root at depth 0 would falsely match login and return the login
# pid as match_pid, instead of the actual wrapper or ssh child. The function
# must skip the root and only check descendants so match_pid is always a
# process below the terminal.
#
# The test builds a real process tree where BOTH the root and a child have
# the needle in their `ps args`, and asserts the function returns the child,
# never the root. A second case uses a root whose args contain the needle but
# whose only child does NOT, and asserts the function returns no match.
set -u

repo_dir="${0:A:h:h}"
cd "$repo_dir"

pass=0; fail=0
_ok() { print "  ok: $1"; pass=$((pass+1)); }
_bad() { print -u2 "  FAIL: $1"; fail=$((fail+1)); }

source ./session-manager-lib.zsh

needle="gzr-deadbeef-1234-5678-9abc-def0"
workdir="$(mktemp -d)"
_pids=()
_cleanup() { for p in "${_pids[@]}"; do kill "$p" 2>/dev/null; done; wait 2>/dev/null; rm -rf "$workdir"; }
trap '_cleanup' EXIT INT TERM

# Spawn a tree whose root stays as `zsh -c <script>` (so the needle embedded
# in the script text appears in the root's `ps args`) and whose single child is
# reported via a pid file. The root script always embeds `--session <needle>`
# so the root itself would match under the old code (the false-match
# condition). The child_script controls whether the child also matches.
spawn_tree() {
  local child_script="$1"
  pidfile="$workdir/root$$.pid"
  root_script='needle="'"$needle"'"; pidfile="'"$pidfile"'"; child_script="'"$child_script"'"; : "--session '"$needle"' root-needle"; zsh -c "$child_script" & print -r -- "$!" > "$pidfile"; sleep 60 & wait'
  zsh -c "$root_script" &
  local root=$!
  for i in {1..100}; do [[ -f "$pidfile" ]] && break; sleep 0.05; done
  local child="$(cat "$pidfile" 2>/dev/null)"
  rm -f "$pidfile"
  _pids+=("$root" "$child")
  REPLY_root=$root
  REPLY_child=$child
}

# --- Case 1: root args contain the needle AND a descendant also matches. ---
# Expectation: return the DESCENDANT, never the root.
# The child script keeps zsh alive (sleep 60 & wait) so its args stay as
# `zsh -c <script text containing the needle>`.
spawn_tree "sleep 60 & wait # --session $needle wrapper-fake"
root_pid=$REPLY_root
child_pid=$REPLY_child

[[ "$root_pid" =~ ^[0-9]+$ ]] || { _bad "case1: root pid not captured"; exit 1; }
[[ "$child_pid" =~ ^[0-9]+$ ]] || { _bad "case1: child pid not captured"; exit 1; }
kill -0 "$root_pid" 2>/dev/null && kill -0 "$child_pid" 2>/dev/null \
  || { _bad "case1: pids not alive"; exit 1; }

# Precondition: the root's own args contain the needle (the false-match
# condition the fix prevents). Under the old code (queue=("$root")) this
# would have returned the root at depth 0.
root_args="$(ps -o args= -p "$root_pid" 2>/dev/null)"
[[ "$root_args" == *"--session $needle"* ]] \
  || { _bad "case1 precondition: root args do not contain the needle (got: $root_args)"; exit 1; }

match="$(ghostty_zmx_descendants_matching "$root_pid" "$needle" 2>/dev/null)"
if [[ "$match" == "$root_pid" ]]; then
  _bad "case1: returned the root pid itself (login-process false match): $match"
elif [[ "$match" == "$child_pid" ]]; then
  _ok "case1: returned the descendant pid, not the root: $match"
elif [[ -z "$match" ]]; then
  _bad "case1: returned no match (expected child pid $child_pid)"
else
  _bad "case1: returned an unexpected pid: $match (expected $child_pid)"
fi

# --- Case 2: root args contain the needle, but no descendant matches. ---
# Expectation: return no match (rc 1), NOT the root.
spawn_tree "sleep 60 & wait # plain non-matching child"
edge_root=$REPLY_root
edge_child=$REPLY_child

[[ "$edge_root" =~ ^[0-9]+$ && "$edge_child" =~ ^[0-9]+$ ]] || { _bad "case2: pids not captured"; exit 1; }
kill -0 "$edge_root" 2>/dev/null && kill -0 "$edge_child" 2>/dev/null \
  || { _bad "case2: pids not alive"; exit 1; }

edge_root_args="$(ps -o args= -p "$edge_root" 2>/dev/null)"
[[ "$edge_root_args" == *"--session $needle"* ]] \
  || { _bad "case2 precondition: root args do not contain the needle (got: $edge_root_args)"; exit 1; }

if ghostty_zmx_descendants_matching "$edge_root" "$needle" 2>/dev/null; then
  _bad "case2: returned a match for a root with only non-matching children (should return no match)"
else
  _ok "case2: returned no match when only the root (not descendants) matches"
fi

(( fail == 0 )) || exit 1
print "all descendants-root-skip tests passed ($((pass))/$((pass+fail)))"
