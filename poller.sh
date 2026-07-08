#!/bin/zsh
# Remote projection poller. Sources the manager (GHOSTTY_ZMX_INTERNAL_POLLER=1
# guard: defines all functions, returns before widget/auto-attach side effects)
# then runs the PID-reuse-safe poll loop using the shared manager functions.
# Args: ghostty_pid flag data_home state_home interval debug app_name
#       install_dir ghostty_elapsed scrollback_lines manager_src
ghostty_pid="$1"
flag="$2"
data_home="$3"
state_home="$4"
interval="$5"
debug_enabled="$6"
ghostty_app_name="$7"
install_dir="$8"
ghostty_elapsed="${9:-0}"
manager_src="${11:-$install_dir/session-manager.zsh}"

export GHOSTTY_ZMX_DATA_HOME="$data_home"
export GHOSTTY_ZMX_STATE_HOME="$state_home"
export GHOSTTY_ZMX_DEBUG="$debug_enabled"
export _ghostty_app_name="$ghostty_app_name"

# Paths used by the startup cleanup below and by poll_once (which re-derives
# them, but defining them here makes the startup cleanup self-contained).
hosts_file="$data_home/remote-hosts"
projections_file="$data_home/remote-projections"

# PID-reuse-safe token: the owning Ghostty's elapsed-seconds at startup.
print -r -- "$$" > "$flag/pid" 2>/dev/null || true
print -r -- "$ghostty_elapsed" > "$flag/elapsed" 2>/dev/null || true

# Source the manager: defines all ghostty_zmx_* helpers then returns early
# (GHOSTTY_ZMX_INTERNAL_POLLER guard). The poller reuses ghostty_zmx_poll_once,
# ghostty_zmx_snapshot_remote_sessions, ghostty_zmx_find_live_projection, etc.
# — the same functions the widget and reconcile path use, so they cannot diverge.
#
# Unset TERM_PROGRAM so the manager's version-self-gate (which probes Ghostty
# AppleScript tty capability and falls back to the v0.1 manager when the probe
# fails) does not trigger. The poller is launched from
# ghostty_zmx_start_remote_poller, which only runs after the manager's gate
# already passed at shell init (the surface is v0.2-capable), so the poller
# must take the v0.2 path unconditionally. Without this, a background poller
# whose osascript probe fails (e.g. Ghostty just quit) would source the v0.1
# fallback and run with none of the v0.2 poller helpers defined — the same
# class of "lib helper undefined in poller" bug that the reaper had (issue #39).
unset TERM_PROGRAM
GHOSTTY_ZMX_INTERNAL_POLLER=1 source "$manager_src" 2>/dev/null || exit 70
# Defensive: if the manager source did not define the poller helpers (corrupt
# install, missing lib), exit rather than running a poller with no functions.
(( $+functions[ghostty_zmx_poll_once] )) || exit 71

# Startup cleanup: clear stale local projection rows whose recorded pid is
# dead. After Cmd-Q+reopen, the local remote-projections file still has rows
# from the prior session (pids that no longer exist). Without this cleanup,
# (a) the grouped restore skips those sessions (projection_known returns true),
# so they never re-project; and (b) the dead-pid cleanup runs close-txn on them,
# killing the remote sessions that should survive for re-attach. Clearing
# them here lets the grouped restore re-project fresh while preserving the
# server-side `present` rows. This runs only once, before the first poll.
if [[ -f "$projections_file" ]]; then
  typeset _cleared=0 _h _ws _sess _tty _pid _st _up _w _t
  typeset tmp="$projections_file.tmp.$$"
  : > "$tmp" 2>/dev/null || true
  while IFS=$'\t' read -r _h _ws _sess _tty _pid _st _up _w _t; do
    if [[ "$_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$_pid" 2>/dev/null; then
      _ghostty_zmx_debug "poller startup-cleared stale host=$_h session=$_sess pid=$_pid"
      _cleared=$((_cleared + 1))
    else
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$_h" "$_ws" "$_sess" "$_tty" "$_pid" "$_st" "$_up" "$_w" "$_t" >> "$tmp"
    fi
  done < "$projections_file"
  mv "$tmp" "$projections_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  (( _cleared > 0 )) && _ghostty_zmx_debug "poller startup-cleared count=$_cleared"
fi

startup_grace=1
sleep 1
trap 'rm -rf "$flag" 2>/dev/null || true' EXIT INT TERM
while :; do
  cur_elapsed="$(ps -o etime= -p "$ghostty_pid" 2>/dev/null | tr -d ' ')"
  cur_elapsed="$(_ghostty_zmx_parse_elapsed_seconds "$cur_elapsed" 2>/dev/null)" || cur_elapsed=""
  if [[ -z "$cur_elapsed" ]]; then
    ghostty_zmx_snapshot_remote_sessions
    _ghostty_zmx_debug "poller stopped ghostty_pid=$ghostty_pid reason=ghostty-exit"
    break
  fi
  if [[ -n "$ghostty_elapsed" && "$cur_elapsed" -lt "$ghostty_elapsed" ]]; then
    ghostty_zmx_snapshot_remote_sessions
    _ghostty_zmx_debug "poller stopped ghostty_pid=$ghostty_pid reason=pid-reuse saved=$ghostty_elapsed cur=$cur_elapsed"
    break
  fi
  ghostty_zmx_poll_once "$startup_grace" "$ghostty_pid"
  startup_grace=0
  sleep "$interval"
done
rm -f "$0" 2>/dev/null
