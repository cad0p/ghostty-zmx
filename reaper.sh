#!/bin/zsh
# ghostty-zmx local reaper. Sources the manager (GHOSTTY_ZMX_INTERNAL_REAPER=1
# guard: defines all functions, returns before widget/auto-attach side effects)
# then runs the PID-reuse-safe reap loop using the shared manager functions.
#
# Before this refactor the reaper inlined ~20 helper functions duplicating the
# manager (valid_session_name, history_file_for_session, debug_log,
# _reaper_debug_rotate, parse_elapsed_seconds, elapsed_seconds, cleanup_tty_map,
# cleanup_log, snapshot_history, forget_snapshot, managed_sessions_from_log,
# registry_dir, registry_file, registry_tracked_sessions, registry_heartbeat,
# managed_detached_sessions, current_terminal_ttys, managed_disappeared_sessions,
# managed_existing_sessions, snapshot_existing_sessions, cleanup_detached_session,
# cleanup_detached_sessions, cleanup_seen_detached_sessions). That duplication
# caused a real bug: the reaper's debug_log called _ghostty_zmx_debug_rotate (a
# lib function) but the function was never defined in the reaper heredoc, so
# debug-log rotation never fired for the reaper — the highest-volume debug-log
# writer. Sourcing the manager makes that class of bug impossible by construction
# and keeps the reaper consistent with the poller (which already sources the
# manager via the GHOSTTY_ZMX_INTERNAL_POLLER guard). See issue #39 and the
# poller refactor in PR #23.
#
# Args: ghosttyPID flag dataHome interval zeroWindowGrace stateHome debugEnabled
#       scrollbackLines reaperStartupDelay runtimeDir ghosttyElapsed
#       ghosttyAppName manager_src
ghosttyPID="$1"
flag="$2"
dataHome="$3"
interval="$4"
zeroWindowGrace="$5"
stateHome="$6"
debugEnabled="$7"
scrollbackLines="$8"
reaperStartupDelay="$9"
runtimeDir="${10}"
ghosttyElapsed="${11}"
ghosttyAppName="${12}"
manager_src="${13:-${GHOSTTY_ZMX_INSTALL_DIR:-$HOME/.config/ghostty-zmx}/session-manager.zsh}"

export GHOSTTY_ZMX_DATA_HOME="$dataHome"
export GHOSTTY_ZMX_STATE_HOME="$stateHome"
export GHOSTTY_ZMX_DEBUG="$debugEnabled"
export GHOSTTY_ZMX_SCROLLBACK_LINES="$scrollbackLines"
export _ghostty_app_name="$ghosttyAppName"

# Source the manager: defines all _ghostty_zmx_* helpers (including the reaper
# helpers promoted out of this heredoc) then returns early
# (GHOSTTY_ZMX_INTERNAL_REAPER guard). The reaper reuses
# _ghostty_zmx_snapshot_history, _ghostty_zmx_cleanup_log, _ghostty_zmx_forget_snapshot,
# _ghostty_zmx_managed_detached_sessions, _ghostty_zmx_managed_disappeared_sessions,
# _ghostty_zmx_managed_existing_sessions, _ghostty_zmx_snapshot_existing_sessions,
# _ghostty_zmx_cleanup_detached_session, _ghostty_zmx_registry_heartbeat,
# _ghostty_zmx_parse_elapsed_seconds, _ghostty_zmx_ghostty_elapsed_seconds,
# _ghostty_zmx_debug, _ghostty_zmx_debug_rotate — the same functions the widget
# and attach path use, so they cannot diverge.
#
# Unset TERM_PROGRAM so the manager's version-self-gate (which probes Ghostty
# AppleScript tty capability and falls back to the v0.1 manager when the probe
# fails) does not trigger. The reaper is launched from _ghostty_zmx_start_reaper,
# which only runs after the manager's gate already passed at shell init (the
# surface is v0.2-capable), so the reaper must take the v0.2 path unconditionally.
# Without this, a background reaper whose osascript probe fails (e.g. Ghostty
# just quit) would source the v0.1 fallback and run with none of the v0.2
# reaper helpers defined — the same class of "lib helper undefined in reaper"
# bug that motivated this refactor.
unset TERM_PROGRAM
GHOSTTY_ZMX_INTERNAL_REAPER=1 source "$manager_src" 2>/dev/null || exit 70
# Defensive: if the manager source did not define the reaper helpers (corrupt
# install, missing lib), exit rather than running a reaper with no functions.
(( $+functions[_ghostty_zmx_managed_detached_sessions] )) || exit 71

# Convenience locals bound to the data-home paths (the reaper loop reads these).
log="$dataHome/sessions"
ttyMap="$dataHome/tty-map"
queue="$dataHome/restore-queue"
firstFile="$dataHome/restore-first"
restoring="$runtimeDir/restoring-${ghosttyPID}.lock"
attempted="$runtimeDir/restore-attempted-${ghosttyPID}.done"

# Reaper-local debug wrapper: tags lines with "reaper" so they are
# distinguishable from widget/attach/poller lines in the shared debug log.
# Delegates rotation to the manager's _ghostty_zmx_debug_rotate (now available
# because the manager is sourced above — the bug that motivated this refactor).
_reaper_debug() {
  [[ "$debugEnabled" == "1" ]] || return 0
  mkdir -p "$stateHome" 2>/dev/null
  _ghostty_zmx_debug_rotate "$stateHome/debug.log"
  print -r -- "$(date -u '+%Y-%m-%dT%H:%M:%SZ') reaper $*" >> "$stateHome/debug.log"
}

_reaper_debug "started ghostty_pid=$ghosttyPID sessions_file=$log"

sleep "$reaperStartupDelay"
# Startup sweep: kill managed zmx sessions left detached (clients=0) by a
# prior Ghostty instance that was killed (not cleanly exited). The reaper
# only cleans up during its lifetime; a killed Ghostty leaves its managed
# sessions detached forever. This runs once at startup.
# _ghostty_zmx_managed_detached_sessions filters by the v0.1 managed naming
# (zmx-<win>-<tab>-<term>) AND cross-references the sessions log, so
# user-created sessions and gzr-* remote sessions are never touched. A
# session the user intentionally detached (zmx detach) to reattach later
# would be killed here; that is an accepted trade-off (documented as a
# known limitation).
while IFS= read -r orphan; do
  _ghostty_zmx_cleanup_detached_session "$orphan" "startup-orphan-sweep"
done < <(_ghostty_zmx_managed_detached_sessions)
# Heartbeat this install's registry file before entering the loop, so the
# cross-install tracked set is fresh even if the first loop iteration sleeps.
# This marks all live zmx-* sessions as tracked by THIS install, so other
# installs' reapers (or this one after a restart) will not reap them.
_ghostty_zmx_registry_heartbeat 2>/dev/null || true
zeroWindowsSeen=0
lastAttached=0
typeset -A detachedSeen
while kill -0 "$ghosttyPID" 2>/dev/null; do
  # Heartbeat every cycle: refresh this install's registry file so the tracked
  # set reflects current live sessions. This is the cross-install persistence
  # signal — closed Ghostty's file stays on disk (sessions survive), but a
  # live Ghostty keeps its file fresh so other reapers know it's active.
  _ghostty_zmx_registry_heartbeat 2>/dev/null || true
  typeset currentElapsed
  currentElapsed="$(_ghostty_zmx_ghostty_elapsed_seconds "$ghosttyPID")"
  if [[ -n "$currentElapsed" && "$currentElapsed" -lt "$ghosttyElapsed" ]]; then
    _ghostty_zmx_snapshot_existing_sessions "ghostty-pid-reuse"
    _reaper_debug "stopped ghostty_pid=$ghosttyPID reason=pid-reuse"
    break
  fi
  if [[ -z "$currentElapsed" ]]; then
    _ghostty_zmx_snapshot_existing_sessions "ghostty-exit"
    _reaper_debug "stopped ghostty_pid=$ghosttyPID reason=elapsed-check-failed"
    break
  fi

  typeset windows
  windows=$(osascript -e "tell application \"$ghosttyAppName\" to count of windows" 2>/dev/null)
  [[ "$windows" =~ '^[0-9]+$' ]] || break

  if [[ "$windows" -eq 0 ]]; then
    zeroWindowsSeen=$((zeroWindowsSeen + interval))
    if [[ "$zeroWindowsSeen" -ge "$zeroWindowGrace" ]]; then
      while IFS= read -r orphan; do
        _ghostty_zmx_cleanup_detached_session "$orphan" "zero-window cleanup"
      done < <(_ghostty_zmx_managed_detached_sessions)
    fi
    sleep "$interval"
    continue
  fi
  zeroWindowsSeen=0

  if [[ -f "$restoring" || -s "$queue" || -s "$firstFile" ]]; then
    _reaper_debug "restore active; skipping cleanup"
    sleep "$interval"
    continue
  fi

  typeset attached=0 managed clients
  while IFS= read -r managed; do
    clients=$(zmx list 2>/dev/null | awk -F '\t' -v name="$managed" '$1 ~ "name="name"$" { sub(/^clients=/, "", $3); print $3; exit }')
    [[ "$clients" == "1" ]] && attached=$((attached + 1))
  done < <(_ghostty_zmx_managed_sessions_from_log)
  lastAttached=$attached
  if [[ "$attached" -eq 0 ]]; then
    _ghostty_zmx_snapshot_existing_sessions "all-detached"
    sleep "$interval"
    continue
  fi

  typeset orphan
  while IFS= read -r orphan; do
    _ghostty_zmx_cleanup_detached_session "$orphan" "tty-disappeared cleanup"
    unset "detachedSeen[$orphan]"
  done < <(_ghostty_zmx_managed_disappeared_sessions)

  while IFS= read -r orphan; do
    detachedSeen[$orphan]=$(( ${detachedSeen[$orphan]:-0} + interval ))
    if [[ "${detachedSeen[$orphan]}" -lt "$zeroWindowGrace" ]]; then
      _ghostty_zmx_snapshot_history "$orphan"
      _reaper_debug "detached pending session=$orphan attached_managed=$attached stable_for=${detachedSeen[$orphan]}"
      continue
    fi
    _ghostty_zmx_snapshot_history "$orphan"
    _reaper_debug "detached cleanup session=$orphan attached_managed=$attached stable_for=${detachedSeen[$orphan]}"
    zmx kill "$orphan" >/dev/null 2>&1
    _ghostty_zmx_cleanup_log "$orphan"
    _ghostty_zmx_forget_snapshot "$orphan"
    unset "detachedSeen[$orphan]"
  done < <(_ghostty_zmx_managed_detached_sessions)
  sleep "$interval"
done
if [[ "${#detachedSeen[@]}" -gt 0 && "$lastAttached" -gt 1 ]]; then
  typeset orphan
  for orphan in ${(k)detachedSeen}; do
    _ghostty_zmx_cleanup_detached_session "$orphan" "detached exit cleanup"
  done
  _ghostty_zmx_snapshot_existing_sessions "ghostty-exit"
else
  _ghostty_zmx_snapshot_existing_sessions "ghostty-exit"
fi
_reaper_debug "stopped ghostty_pid=$ghosttyPID"
rm -f "$attempted" 2>/dev/null
rmdir "$flag" 2>/dev/null
rm -f "$0" 2>/dev/null
