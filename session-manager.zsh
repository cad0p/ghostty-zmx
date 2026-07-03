# ghostty-zmx session manager for zsh.
# Source this file from an interactive zsh launched by Ghostty.

# Shared pure helpers are sourced by both this full .zshrc manager and the
# minimal .zprofile early-inherit hook. Keep side effects out of the lib.
typeset _gzmx_manager_self="${(%):-%N}"
typeset _gzmx_manager_dir="${_gzmx_manager_self:A:h}"
if [[ -r "$_gzmx_manager_dir/session-manager-lib.zsh" ]]; then
  source "$_gzmx_manager_dir/session-manager-lib.zsh"
else
  # Partial/corrupt install safety: the v0.2 manager depends on the shared lib
  # for defaults and helper functions. If the lib is missing, fail open to the
  # frozen v0.1 fallback when present (or silently return) rather than breaking
  # the user's shell with unbound variables / missing functions.
  [[ -r "$_gzmx_manager_dir/session-manager-v0.1.zsh" ]] &&
    source "$_gzmx_manager_dir/session-manager-v0.1.zsh"
  return 0
fi

# Version self-gating: on Ghostty without the 1.4.0 AppleScript terminal pid/tty
# properties, defer to the frozen v0.1 manager. We probe capability (does the
# terminal class respond to `tty`?) rather than parsing TERM_PROGRAM_VERSION.
# The shared lib only provides the probe; the v0.1 fallback remains in this
# .zshrc entry point so the .zprofile early hook can fail open silently.
if [[ "${TERM_PROGRAM:-}" == "ghostty" ]] && ! ghostty_zmx_has_tty_capability 2>/dev/null; then
  [[ -r "$HOME/.config/ghostty-zmx/session-manager-v0.1.zsh" ]] &&
    source "$HOME/.config/ghostty-zmx/session-manager-v0.1.zsh"
  return 0
fi

: ${GHOSTTY_ZMX_REAPER_INTERVAL:=2}
: ${GHOSTTY_ZMX_ZERO_WINDOWS_GRACE:=6}
: ${GHOSTTY_ZMX_RESTORE_STEP_DELAY:=1}
: ${GHOSTTY_ZMX_SCROLLBACK_LINES:=1000}

# Internal waits are named here so lifecycle timing is auditable without expanding the public API.
_ghostty_zmx_reaper_startup_delay=5
_ghostty_zmx_queue_lock_attempts=50
_ghostty_zmx_queue_lock_delay=0.1
_ghostty_zmx_ghostty_ready_attempts=10
_ghostty_zmx_ghostty_ready_delay=0.5
_ghostty_zmx_restore_assignment_attempts=80
_ghostty_zmx_restore_assignment_delay=0.1
# Restore lock cleanup margin covers AppleScript overhead not counted by per-step restore delays.
_ghostty_zmx_restore_lock_margin=10

_ghostty_zmx_valid_session_name() {
  typeset session="$1"
  [[ ${#session} -le 46 && "$session" =~ ^zmx-[A-Fa-f0-9]+-[A-Fa-f0-9]+-[A-Fa-f0-9]{8,}$ ]]
}





_ghostty_zmx_valid_physical_id() {
  typeset id="$1"
  [[ "$id" =~ ^[A-Fa-f0-9]+$ ]]
}

_ghostty_zmx_session_history_file() {
  typeset session="$1"
  _ghostty_zmx_valid_session_name "$session" || return 1
  print -r -- "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt"
}



_ghostty_zmx_parse_elapsed_seconds() {
  typeset elapsed="$1" days=0 hours=0 minutes seconds
  typeset -a parts
  [[ -n "$elapsed" ]] || return 1
  if [[ "$elapsed" == *-* ]]; then
    days="${elapsed%%-*}"
    elapsed="${elapsed#*-}"
    [[ "$days" =~ ^[0-9]+$ ]] || return 1
  fi
  parts=("${(@s/:/)elapsed}")
  case ${#parts} in
    2)
      minutes="${parts[1]}"
      seconds="${parts[2]}"
      ;;
    3)
      hours="${parts[1]}"
      minutes="${parts[2]}"
      seconds="${parts[3]}"
      ;;
    *) return 1 ;;
  esac
  [[ "$hours" =~ ^[0-9]+$ && "$minutes" =~ ^[0-9]+$ && "$seconds" =~ ^[0-9]+$ ]] || return 1
  print -r -- $(( days * 86400 + 10#$hours * 3600 + 10#$minutes * 60 + 10#$seconds ))
}

_ghostty_zmx_ghostty_elapsed_seconds() {
  typeset pid="$1" elapsed
  elapsed="$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')" || return 1
  _ghostty_zmx_parse_elapsed_seconds "$elapsed"
}

_ghostty_zmx_ghostty_process_token() {
  typeset pid="$1" start elapsed
  start="$(ps -o lstart= -p "$pid" 2>/dev/null | tr -s ' ' | sed 's/^ //; s/ $//')"
  if [[ -n "$start" ]]; then
    print -r -- "lstart:$start"
    return 0
  fi
  elapsed="$(_ghostty_zmx_ghostty_elapsed_seconds "$pid")" || return 1
  print -r -- "elapsed:$elapsed"
}

_ghostty_zmx_restore_attempted_current() {
  typeset attemptedFlag="$1" currentToken="$2" savedToken="" savedElapsed="" currentElapsed=""
  [[ -f "$attemptedFlag" ]] || return 1
  IFS= read -r savedToken < "$attemptedFlag" 2>/dev/null || savedToken=""
  if [[ -z "$savedToken" || -z "$currentToken" ]]; then
    rm -f "$attemptedFlag" 2>/dev/null
    return 1
  fi
  if [[ "$savedToken" == "$currentToken" ]]; then
    return 0
  fi
  if [[ "$savedToken" == elapsed:* && "$currentToken" == elapsed:* ]]; then
    savedElapsed="${savedToken#elapsed:}"
    currentElapsed="${currentToken#elapsed:}"
    if [[ "$savedElapsed" =~ ^[0-9]+$ && "$currentElapsed" =~ ^[0-9]+$ && "$currentElapsed" -ge "$savedElapsed" ]]; then
      return 0
    fi
  fi
  rm -f "$attemptedFlag" 2>/dev/null
  return 1
}

_ghostty_zmx_mark_restore_attempted() {
  typeset attemptedFlag="$1" currentToken="$2"
  [[ -n "$attemptedFlag" && -n "$currentToken" ]] || return 0
  mkdir -p "${attemptedFlag:h}" 2>/dev/null
  print -r -- "$currentToken" > "${attemptedFlag}.tmp.$$" 2>/dev/null && mv "${attemptedFlag}.tmp.$$" "$attemptedFlag" 2>/dev/null
}


_ghostty_zmx_scrollback_line_count() {
  typeset value="${GHOSTTY_ZMX_SCROLLBACK_LINES:-1000}"
  if [[ "$value" =~ ^[0-9]+$ && "$value" -gt 0 ]]; then
    print -r -- "$value"
  else
    _ghostty_zmx_debug "invalid scrollback line count value=$value defaulting=1000"
    print -r -- 1000
  fi
}
typeset GHOSTTY_ZMX_SCROLLBACK_LINES="$(_ghostty_zmx_scrollback_line_count)"

_ghostty_zmx_debug "shell init data_home=$GHOSTTY_ZMX_DATA_HOME state_home=$GHOSTTY_ZMX_STATE_HOME"

_ghostty_zmx_sessions_file() {
  print -r -- "$GHOSTTY_ZMX_DATA_HOME/sessions"
}

_ghostty_zmx_tty_map_file() {
  print -r -- "$GHOSTTY_ZMX_DATA_HOME/tty-map"
}



_ghostty_zmx_record_tty_map() {
  typeset session="$1" identity="$2" map tmp pid tty_path
  _ghostty_zmx_valid_session_name "$session" || { _ghostty_zmx_debug "invalid session skipped action=record-tty session=$session"; return 1; }
  [[ -n "$identity" ]] || identity="$(_ghostty_zmx_current_surface_identity)" || return 1
  pid="$(print -r -- "$identity" | awk '{print $4}')"
  tty_path="$(print -r -- "$identity" | awk '{print $5}')"
  [[ "$pid" =~ ^[0-9]+$ && "$tty_path" == /dev/* ]] || return 1
  map="$(_ghostty_zmx_tty_map_file)"
  mkdir -p "${map:h}" 2>/dev/null
  tmp="${map}.tmp.$$"
  { grep -v -F $'\t'"${session}"$'\t' "$map" 2>/dev/null || true
    print -r -- "S	${session}	${tty_path}	${pid}"
  } > "$tmp" && mv "$tmp" "$map" 2>/dev/null
  _ghostty_zmx_debug "tty-map write session=$session tty=$tty_path pid=$pid"
}

_ghostty_zmx_terminal_tty_present() {
  typeset needle="$1" found
  [[ "$needle" == /dev/* ]] || return 1
  found="$(osascript <<EOF 2>/dev/null
tell application "$_ghostty_app_name"
  repeat with w in windows
    repeat with tb in tabs of w
      repeat with tm in terminals of tb
        try
          if (tty of tm as string) is "$needle" then return "1"
        end try
      end repeat
    end repeat
  end repeat
  return "0"
end tell
EOF
)" || return 1
  [[ "$found" == "1" ]]
}

_ghostty_zmx_session_clients() {
  typeset session="$1"
  zmx list 2>/dev/null | awk -F '\t' -v name="$session" '$1 ~ "name="name"$" { sub(/^clients=/, "", $3); print $3; exit }'
}

_ghostty_zmx_cleanup_closed_surface() {
  typeset session="$1" tty_path="$2" windows
  _ghostty_zmx_valid_session_name "$session" || return 0
  [[ "$tty_path" == /dev/* ]] || return 0
  windows="$(osascript -e "tell application \"$_ghostty_app_name\" to count of windows" 2>/dev/null)" || return 0
  [[ "$windows" =~ ^[0-9]+$ && "$windows" -gt 0 ]] || return 0
  _ghostty_zmx_terminal_tty_present "$tty_path" && return 0
  _ghostty_zmx_debug "attach-exit tty-disappeared cleanup session=$session tty=$tty_path windows=$windows"
  _ghostty_zmx_snapshot_history "$session"
  zmx kill "$session" >/dev/null 2>&1
  _ghostty_zmx_unlog_session "$session"
  rm -f "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt" 2>/dev/null
}

_ghostty_zmx_unmap_session_tty() {
  typeset session="$1" map="$(_ghostty_zmx_tty_map_file)" tmp
  [[ -f "$map" ]] || return 0
  tmp="${map}.tmp.$$"
  awk -F '\t' -v session="$session" '$2 != session { print }' "$map" > "$tmp" 2>/dev/null && mv "$tmp" "$map" 2>/dev/null
}

_ghostty_zmx_log_session() {
  typeset session="$1"
  if ! _ghostty_zmx_valid_session_name "$session"; then
    _ghostty_zmx_debug "invalid session skipped action=log session=$session"
    return 1
  fi
  typeset log="$(_ghostty_zmx_sessions_file)"
  mkdir -p "${log:h}" 2>/dev/null
  if [[ ! -f "$log" ]] || ! grep -qxF "$session" "$log" 2>/dev/null; then
    print -r -- "$session" >> "$log"
    _ghostty_zmx_debug "session logged session=$session file=$log"
  fi
}

_ghostty_zmx_random_hex() {
  od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d '[:space:]' || print -r -- "${RANDOM}${RANDOM}"
}

_ghostty_zmx_session_in_zmx() {
  typeset session="$1" runtime_dir list_file
  runtime_dir="$(_ghostty_zmx_runtime_dir)" || return 1
  list_file="$runtime_dir/list.short.reserve.$$"
  zmx list --short > "$list_file" 2>/dev/null || { rm -f "$list_file" 2>/dev/null; return 1; }
  grep -qxF "$session" "$list_file" 2>/dev/null
  typeset found=$?
  rm -f "$list_file" 2>/dev/null
  return "$found"
}

_ghostty_zmx_session_available_unlocked() {
  typeset session="$1" log="$(_ghostty_zmx_sessions_file)"
  _ghostty_zmx_valid_session_name "$session" || return 1
  grep -qxF "$session" "$log" 2>/dev/null && return 1
  _ghostty_zmx_session_in_zmx "$session" && return 1
  return 0
}

_ghostty_zmx_collision_variant() {
  typeset base="$1" rest win tab term nonce_tab nonce_term
  rest="${base#zmx-}"
  win="${rest%%-*}"
  rest="${rest#*-}"
  tab="${rest%%-*}"
  term="${rest#*-}"
  win="${win[1,12]}"
  tab="${tab[1,9]}"
  term="${term[1,8]}"
  nonce_tab="$(_ghostty_zmx_random_hex)"
  nonce_term="$(_ghostty_zmx_random_hex)"
  nonce_tab="${nonce_tab[1,4]}"
  nonce_term="${nonce_term[1,4]}"
  print -r -- "zmx-${win}-${tab}${nonce_tab}-${term}${nonce_term}"
}

_ghostty_zmx_reserve_session_name() {
  typeset base="$1" log="$(_ghostty_zmx_sessions_file)" lockdir candidate attempt variant_attempt
  _ghostty_zmx_valid_session_name "$base" || { _ghostty_zmx_debug "invalid session skipped action=reserve session=$base"; return 1; }
  mkdir -p "${log:h}" 2>/dev/null
  [[ -f "$log" ]] || : > "$log" 2>/dev/null || true
  lockdir="${log}.lock"
  for attempt in $(seq 1 80); do
    if mkdir "$lockdir" 2>/dev/null; then
      candidate="$base"
      for variant_attempt in $(seq 0 40); do
        if _ghostty_zmx_session_available_unlocked "$candidate"; then
          print -r -- "$candidate" >> "$log"
          rmdir "$lockdir" 2>/dev/null
          if [[ "$candidate" != "$base" ]]; then
            _ghostty_zmx_debug "session collision resolved base=$base session=$candidate"
          fi
          _ghostty_zmx_debug "session logged session=$candidate file=$log"
          print -r -- "$candidate"
          return 0
        fi
        candidate="$(_ghostty_zmx_collision_variant "$base")"
      done
      rmdir "$lockdir" 2>/dev/null
      return 1
    fi
    sleep 0.05
  done
  _ghostty_zmx_debug "session reserve failed session=$base lock=$lockdir"
  return 1
}

_ghostty_zmx_unlog_session() {
  typeset session="$1" log="$(_ghostty_zmx_sessions_file)"
  _ghostty_zmx_valid_session_name "$session" || { _ghostty_zmx_debug "invalid session skipped action=unlog session=$session"; return 1; }
  [[ -f "$log" ]] || return 0
  grep -vxF "$session" "$log" > "${log}.tmp.$$" 2>/dev/null || true
  mv "${log}.tmp.$$" "$log" 2>/dev/null
  _ghostty_zmx_unmap_session_tty "$session"
}

_ghostty_zmx_snapshot_history() {
  typeset session="$1"
  if ! _ghostty_zmx_valid_session_name "$session"; then
    _ghostty_zmx_debug "invalid session skipped action=snapshot session=$session"
    return 1
  fi
  mkdir -p "$GHOSTTY_ZMX_STATE_HOME/history" 2>/dev/null
  typeset history_file="$(_ghostty_zmx_session_history_file "$session")" || return 1
  typeset tmp_file="${history_file}.tmp.$$"
  rm -f "$tmp_file" "${history_file}.tmp.final.$$" 2>/dev/null
  if zmx history "$session" > "$tmp_file" 2>/dev/null; then
    if tail -n "$GHOSTTY_ZMX_SCROLLBACK_LINES" "$tmp_file" > "${history_file}.tmp.final.$$"; then
      mv "${history_file}.tmp.final.$$" "$history_file"
      _ghostty_zmx_debug "scrollback snapshot session=$session file=$history_file lines=$GHOSTTY_ZMX_SCROLLBACK_LINES"
    else
      rm -f "${history_file}.tmp.final.$$" 2>/dev/null
      _ghostty_zmx_debug "scrollback snapshot tail failed session=$session"
    fi
  else
    _ghostty_zmx_debug "scrollback snapshot failed session=$session"
  fi
  rm -f "$tmp_file" 2>/dev/null
}

_ghostty_zmx_restore_saved_scrollback() {
  typeset session="$1"
  if ! _ghostty_zmx_valid_session_name "$session"; then
    _ghostty_zmx_debug "invalid session skipped action=restore-scrollback session=$session"
    return 1
  fi
  typeset history_file="$(_ghostty_zmx_session_history_file "$session")" || return 1
  typeset runtime_dir="$(_ghostty_zmx_runtime_dir)" || return 1
  typeset list_file="$runtime_dir/list.short.${session}.$$"
  if ! zmx list --short > "$list_file" 2>/dev/null; then
    rm -f "$list_file" 2>/dev/null
    _ghostty_zmx_debug "zmx list --short failed session=$session"
    return 0
  fi
  if grep -qxF "$session" "$list_file"; then
    rm -f "$list_file" 2>/dev/null
    _ghostty_zmx_debug "fresh-session detection session=$session exists=1"
    return 0
  fi
  rm -f "$list_file" 2>/dev/null
  _ghostty_zmx_debug "fresh-session detection session=$session exists=0 snapshot=$history_file"
  [[ -s "$history_file" ]] || return 0
  (
    typeset attempt wait_file="$runtime_dir/list.short.restore-scrollback.${session}.$$"
    for attempt in $(seq 1 100); do
      if zmx list --short > "$wait_file" 2>/dev/null && grep -qxF "$session" "$wait_file" 2>/dev/null; then
        rm -f "$wait_file" 2>/dev/null
        typeset banner='[ghostty-zmx restored saved scrollback from a previous boot; process state was not restored]'
        if ! { print -r -- "$banner"; cat "$history_file"; } | zmx print "$session"; then
          _ghostty_zmx_debug "zmx print failed session=$session file=$history_file"
        else
          _ghostty_zmx_debug "zmx print restored scrollback session=$session file=$history_file"
        fi
        return 0
      fi
      sleep 0.1
    done
    rm -f "$wait_file" 2>/dev/null
    _ghostty_zmx_debug "zmx print skipped session=$session reason=session-not-created file=$history_file"
  ) &!
}

_ghostty_zmx_start_reaper() {
  typeset ghosttyPID="$1"
  [[ -n "$ghosttyPID" ]] || return 0
  typeset runtime_dir="$(_ghostty_zmx_runtime_dir)" || return 0
  typeset flag="$runtime_dir/reaper-${ghosttyPID}.lock"
  mkdir "$flag" 2>/dev/null || return 0
  _ghostty_zmx_debug "reaper start ghostty_pid=$ghosttyPID flag=$flag"

  typeset script="$runtime_dir/reaper-${ghosttyPID}.zsh"
  typeset reaper_log="$runtime_dir/reaper-${ghosttyPID}.log"
  typeset ghosttyElapsed="$(_ghostty_zmx_ghostty_elapsed_seconds "$ghosttyPID")"
  [[ -n "$ghosttyElapsed" ]] || ghosttyElapsed=0
  set -o noclobber
  { print '#!/bin/zsh' > "$script"; } 2>/dev/null || { set +o noclobber; rmdir "$flag" 2>/dev/null; return 0; }
  set +o noclobber
  cat >> "$script" <<'EOS'
#!/bin/zsh
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
log="$dataHome/sessions"
ttyMap="$dataHome/tty-map"
queue="$dataHome/restore-queue"
firstFile="$dataHome/restore-first"
restoring="$runtimeDir/restoring-${ghosttyPID}.lock"
attempted="$runtimeDir/restore-attempted-${ghosttyPID}.done"

# The generated reaper is standalone because it is executed by nohup after the
# attaching shell may have exited. Keep its helpers private and mirrored here.
valid_session_name() {
  local session="$1"
  [[ ${#session} -le 46 && "$session" =~ ^zmx-[A-Fa-f0-9]+-[A-Fa-f0-9]+-[A-Fa-f0-9]{8,}$ ]]
}

history_file_for_session() {
  local session="$1"
  valid_session_name "$session" || return 1
  print -r -- "$stateHome/history/${session}.txt"
}

debug_log() {
  [[ "$debugEnabled" == "1" ]] || return 0
  mkdir -p "$stateHome" 2>/dev/null
  print -r -- "$(date -u '+%Y-%m-%dT%H:%M:%SZ') reaper $*" >> "$stateHome/debug.log"
}

parse_elapsed_seconds() {
  local elapsed="$1" days=0 hours=0 minutes seconds
  local -a parts
  [[ -n "$elapsed" ]] || return 1
  if [[ "$elapsed" == *-* ]]; then
    days="${elapsed%%-*}"
    elapsed="${elapsed#*-}"
    [[ "$days" =~ ^[0-9]+$ ]] || return 1
  fi
  parts=("${(@s/:/)elapsed}")
  case ${#parts} in
    2)
      minutes="${parts[1]}"
      seconds="${parts[2]}"
      ;;
    3)
      hours="${parts[1]}"
      minutes="${parts[2]}"
      seconds="${parts[3]}"
      ;;
    *) return 1 ;;
  esac
  [[ "$hours" =~ ^[0-9]+$ && "$minutes" =~ ^[0-9]+$ && "$seconds" =~ ^[0-9]+$ ]] || return 1
  print $(( days * 86400 + 10#$hours * 3600 + 10#$minutes * 60 + 10#$seconds ))
}

elapsed_seconds() {
  local elapsed
  elapsed="$(ps -o etime= -p "$ghosttyPID" 2>/dev/null | tr -d ' ')" || return 1
  parse_elapsed_seconds "$elapsed"
}

debug_log "started ghostty_pid=$ghosttyPID sessions_file=$log"

cleanup_tty_map() {
  local session="$1"
  [[ -f "$ttyMap" ]] || return 0
  awk -F '\t' -v session="$session" '$2 != session { print }' "$ttyMap" > "${ttyMap}.tmp" 2>/dev/null || true
  mv "${ttyMap}.tmp" "$ttyMap" 2>/dev/null
}

cleanup_log() {
  local session="$1"
  if ! valid_session_name "$session"; then
    debug_log "invalid session skipped action=cleanup-log session=$session"
    return 1
  fi
  [[ -f "$log" ]] || { cleanup_tty_map "$session"; return 0; }
  grep -vxF "$session" "$log" > "${log}.tmp" 2>/dev/null || true
  mv "${log}.tmp" "$log" 2>/dev/null
  cleanup_tty_map "$session"
}

snapshot_history() {
  local session="$1"
  if ! valid_session_name "$session"; then
    debug_log "invalid session skipped action=snapshot session=$session"
    return 1
  fi
  mkdir -p "$stateHome/history" 2>/dev/null
  local historyFile="$(history_file_for_session "$session")" || return 1
  local tmpFile="${historyFile}.tmp.$$"
  local finalFile="${historyFile}.tmp.final.$$"
  rm -f "$tmpFile" "$finalFile" 2>/dev/null
  if zmx history "$session" > "$tmpFile" 2>/dev/null; then
    if tail -n "$scrollbackLines" "$tmpFile" > "$finalFile"; then
      mv "$finalFile" "$historyFile"
      debug_log "scrollback snapshot session=$session file=$historyFile lines=$scrollbackLines"
    else
      rm -f "$finalFile" 2>/dev/null
      debug_log "scrollback snapshot tail failed session=$session"
    fi
  else
    debug_log "scrollback snapshot failed session=$session"
  fi
  rm -f "$tmpFile" 2>/dev/null
}

forget_snapshot() {
  local session="$1"
  if ! valid_session_name "$session"; then
    debug_log "invalid session skipped action=forget-snapshot session=$session"
    return 1
  fi
  local historyFile="$(history_file_for_session "$session")" || return 1
  rm -f "$historyFile" 2>/dev/null
  debug_log "scrollback snapshot deleted session=$session"
}

managed_sessions_from_log() {
  [[ -f "$log" ]] || return 0
  while IFS= read -r managed; do
    [[ -n "$managed" ]] || continue
    if ! valid_session_name "$managed"; then
      debug_log "invalid session skipped action=managed-log session=$managed"
      continue
    fi
    print -r -- "$managed"
  done < "$log"
}

managed_detached_sessions() {
  zmx list 2>/dev/null | awk -F '\t' '$1 ~ /name=zmx-/ && $3=="clients=0" { sub(/^[→ ]*name=/, "", $1); print $1 }' |
  while IFS= read -r orphan; do
    [[ -n "$orphan" ]] || continue
    if ! valid_session_name "$orphan"; then
      debug_log "invalid session skipped action=managed-detached session=$orphan"
      continue
    fi
    grep -qxF "$orphan" "$log" 2>/dev/null || continue
    print -r -- "$orphan"
  done
}

current_terminal_ttys() {
  osascript <<SCRIPT 2>/dev/null
tell application "$ghosttyAppName"
  set out to ""
  repeat with w in windows
    repeat with tb in tabs of w
      repeat with tm in terminals of tb
        try
          set out to out & (tty of tm as string) & linefeed
        end try
      end repeat
    end repeat
  end repeat
  return out
end tell
SCRIPT
}

managed_disappeared_sessions() {
  [[ -f "$ttyMap" ]] || return 0
  local liveFile="$runtimeDir/terminal-ttys.$$" liveClean="$runtimeDir/terminal-ttys.clean.$$"
  current_terminal_ttys > "$liveFile" 2>/dev/null || { rm -f "$liveFile" "$liveClean" 2>/dev/null; return 0; }
  grep '^/dev/' "$liveFile" > "$liveClean" 2>/dev/null || true
  # If no live terminals remain, this is Cmd-Q / close-all shaped. Preserve.
  [[ -s "$liveClean" ]] || { rm -f "$liveFile" "$liveClean" 2>/dev/null; return 0; }
  while IFS=$'\t' read -r kind session ttyPath mappedPid; do
    [[ "$kind" == "S" && -n "$session" && -n "$ttyPath" ]] || continue
    valid_session_name "$session" || continue
    grep -qxF "$session" "$log" 2>/dev/null || continue
    if ! grep -qxF "$ttyPath" "$liveClean" 2>/dev/null; then
      debug_log "tty disappeared session=$session tty=$ttyPath pid=$mappedPid"
      print -r -- "$session"
    fi
  done < "$ttyMap"
  rm -f "$liveFile" "$liveClean" 2>/dev/null
}

managed_existing_sessions() {
  while IFS= read -r managed; do
    local listFile="$runtimeDir/list.short.${managed}.$$"
    if ! zmx list --short > "$listFile" 2>/dev/null; then
      rm -f "$listFile" 2>/dev/null
      debug_log "zmx list --short failed action=managed-existing session=$managed"
      continue
    fi
    if grep -qxF "$managed" "$listFile"; then
      print -r -- "$managed"
    fi
    rm -f "$listFile" 2>/dev/null
  done < <(managed_sessions_from_log)
}

snapshot_existing_sessions() {
  while IFS= read -r preserved; do
    snapshot_history "$preserved"
    debug_log "preserving session=$preserved reason=$1"
  done < <(managed_existing_sessions)
}

cleanup_detached_session() {
  local orphan="$1" reason="$2"
  valid_session_name "$orphan" || return 0
  snapshot_history "$orphan"
  debug_log "$reason session=$orphan"
  zmx kill "$orphan" >/dev/null 2>&1
  cleanup_log "$orphan"
  forget_snapshot "$orphan"
}

cleanup_detached_sessions() {
  local reason="$1"
  while IFS= read -r orphan; do
    cleanup_detached_session "$orphan" "$reason"
  done < <(managed_detached_sessions)
}

cleanup_seen_detached_sessions() {
  local reason="$1" orphan
  for orphan in ${(k)detachedSeen}; do
    cleanup_detached_session "$orphan" "$reason"
  done
}

sleep "$reaperStartupDelay"
zeroWindowsSeen=0
lastAttached=0
typeset -A detachedSeen
while kill -0 "$ghosttyPID" 2>/dev/null; do
  typeset currentElapsed
  currentElapsed="$(elapsed_seconds "$ghosttyPID")"
  if [[ -n "$currentElapsed" && "$currentElapsed" -lt "$ghosttyElapsed" ]]; then
    snapshot_existing_sessions "ghostty-pid-reuse"
    debug_log "stopped ghostty_pid=$ghosttyPID reason=pid-reuse"
    break
  fi
  if [[ -z "$currentElapsed" ]]; then
    snapshot_existing_sessions "ghostty-exit"
    debug_log "stopped ghostty_pid=$ghosttyPID reason=elapsed-check-failed"
    break
  fi

  windows=$(osascript -e "tell application \"$ghosttyAppName\" to count of windows" 2>/dev/null)
  [[ "$windows" =~ '^[0-9]+$' ]] || break

  if [[ "$windows" -eq 0 ]]; then
    zeroWindowsSeen=$((zeroWindowsSeen + interval))
    if [[ "$zeroWindowsSeen" -ge "$zeroWindowGrace" ]]; then
      cleanup_detached_sessions "zero-window cleanup"
    fi
    sleep "$interval"
    continue
  fi
  zeroWindowsSeen=0

  if [[ -f "$restoring" || -s "$queue" || -s "$firstFile" ]]; then
    debug_log "restore active; skipping cleanup"
    sleep "$interval"
    continue
  fi

  attached=0
  while IFS= read -r managed; do
    clients=$(zmx list 2>/dev/null | awk -F '\t' -v name="$managed" '$1 ~ "name="name"$" { sub(/^clients=/, "", $3); print $3; exit }')
    [[ "$clients" == "1" ]] && attached=$((attached + 1))
  done < <(managed_sessions_from_log)
  lastAttached=$attached
  if [[ "$attached" -eq 0 ]]; then
    snapshot_existing_sessions "all-detached"
    sleep "$interval"
    continue
  fi

  while IFS= read -r orphan; do
    cleanup_detached_session "$orphan" "tty-disappeared cleanup"
    unset "detachedSeen[$orphan]"
  done < <(managed_disappeared_sessions)

  while IFS= read -r orphan; do
    detachedSeen[$orphan]=$(( ${detachedSeen[$orphan]:-0} + interval ))
    if [[ "${detachedSeen[$orphan]}" -lt "$zeroWindowGrace" ]]; then
      snapshot_history "$orphan"
      debug_log "detached pending session=$orphan attached_managed=$attached stable_for=${detachedSeen[$orphan]}"
      continue
    fi
    snapshot_history "$orphan"
    debug_log "detached cleanup session=$orphan attached_managed=$attached stable_for=${detachedSeen[$orphan]}"
    zmx kill "$orphan" >/dev/null 2>&1
    cleanup_log "$orphan"
    forget_snapshot "$orphan"
    unset "detachedSeen[$orphan]"
  done < <(managed_detached_sessions)
  sleep "$interval"
done
if [[ "${#detachedSeen[@]}" -gt 0 && "$lastAttached" -gt 1 ]]; then
  cleanup_seen_detached_sessions "detached exit cleanup"
  snapshot_existing_sessions "ghostty-exit"
else
  snapshot_existing_sessions "ghostty-exit"
fi
debug_log "stopped ghostty_pid=$ghosttyPID"
rm -f "$attempted" 2>/dev/null
rmdir "$flag" 2>/dev/null
rm -f "$0" 2>/dev/null
EOS
  chmod +x "$script" 2>/dev/null
  nohup /bin/zsh "$script" "$ghosttyPID" "$flag" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_REAPER_INTERVAL" "$GHOSTTY_ZMX_ZERO_WINDOWS_GRACE" "$GHOSTTY_ZMX_STATE_HOME" "${GHOSTTY_ZMX_DEBUG:-0}" "$GHOSTTY_ZMX_SCROLLBACK_LINES" "$_ghostty_zmx_reaper_startup_delay" "$runtime_dir" "$ghosttyElapsed" "$_ghostty_app_name" >"$reaper_log" 2>&1 </dev/null &!
}

_ghostty_zmx_pop_restore_queue() {
  typeset queue="$GHOSTTY_ZMX_DATA_HOME/restore-queue"
  [[ -f "$queue" && -s "$queue" ]] || return 1
  typeset lockdir="${queue}.lock"
  typeset name
  for attempt in $(seq 1 $_ghostty_zmx_queue_lock_attempts); do
    if mkdir "$lockdir" 2>/dev/null; then
      [[ -s "$queue" ]] || { rmdir "$lockdir" 2>/dev/null; return 1; }
      IFS= read -r name < "$queue"
      tail -n +2 "$queue" > "${queue}.tmp" 2>/dev/null
      mv "${queue}.tmp" "$queue" 2>/dev/null
      rmdir "$lockdir" 2>/dev/null
      if [[ -n "$name" ]]; then
        if _ghostty_zmx_valid_session_name "$name"; then
          _ghostty_zmx_debug "queue pop session=$name queue=$queue"
          print -r -- "$name"
          return 0
        fi
        _ghostty_zmx_debug "invalid session skipped action=queue-pop session=$name"
      fi
      return 1
    fi
    sleep "$_ghostty_zmx_queue_lock_delay"
  done
  return 1
}

_ghostty_zmx_restore_runtime_lock() {
  typeset ghosttyPID="$1"
  typeset runtime_dir="$(_ghostty_zmx_runtime_dir)" || return 1
  print -r -- "$runtime_dir/restoring-${ghosttyPID}.lock"
}

_ghostty_zmx_restore_active() {
  typeset ghosttyPID="$1" restoreFlag="$2" restoreLock
  [[ -n "$restoreFlag" && -d "$restoreFlag" ]] && return 0
  restoreLock="$(_ghostty_zmx_restore_runtime_lock "$ghosttyPID")" || return 1
  [[ -d "$restoreLock" ]]
}

_ghostty_zmx_wait_restore_assignment() {
  typeset ghosttyPID="$1" restoreFlag="$2" sessionName restoreActive=0
  for attempt in $(seq 1 $_ghostty_zmx_restore_assignment_attempts); do
    sessionName="$(_ghostty_zmx_pop_restore_queue)"
    if [[ -n "$sessionName" ]]; then
      print -r -- "$sessionName"
      return 0
    fi
    if _ghostty_zmx_restore_active "$ghosttyPID" "$restoreFlag"; then
      restoreActive=1
      _ghostty_zmx_debug "restore assignment wait attempt=$attempt ghostty_pid=$ghosttyPID"
      sleep "$_ghostty_zmx_restore_assignment_delay"
      continue
    fi
    [[ "$restoreActive" -eq 1 ]] && _ghostty_zmx_debug "restore assignment wait ended ghostty_pid=$ghosttyPID attempts=$attempt"
    return 1
  done
  _ghostty_zmx_debug "restore assignment wait timed out ghostty_pid=$ghosttyPID"
  return 1
}

_ghostty_zmx_current_position() {
  typeset identity="$(_ghostty_zmx_current_surface_identity)" || return 1
  print -r -- "$identity" | awk '{print $1, $2, $3}'
}

_ghostty_zmx_apply_position_map() {
  typeset position="$1"
  typeset map="$GHOSTTY_ZMX_DATA_HOME/id-map"
  typeset curWin=$(print -r -- "$position" | awk '{print $1}')
  typeset curTab=$(print -r -- "$position" | awk '{print $2}')
  typeset termHash=$(print -r -- "$position" | awk '{print $3}')
  typeset winHash="$curWin"
  typeset tabHash="$curTab"
  if [[ -f "$map" ]]; then
    typeset mappedWin=$(awk -v w="$curWin" '$1=="W" && $2==w {print $3; exit}' "$map" 2>/dev/null)
    typeset mappedTab=$(awk -v w="$curWin" -v t="$curTab" '$1=="T" && $2==w && $3==t {print $5; exit}' "$map" 2>/dev/null)
    [[ -n "$mappedWin" ]] && winHash="$mappedWin"
    [[ -n "$mappedTab" ]] && tabHash="$mappedTab"
  fi
  _ghostty_zmx_debug "position map physical_window=$curWin physical_tab=$curTab logical_window=$winHash logical_tab=$tabHash terminal=$termHash"
  print -r -- "$winHash $tabHash $termHash"
}

_ghostty_zmx_write_id_map() {
  typeset logicalWin="$1" logicalTab="$2" curWin="$3" curTab="$4"
  [[ -n "$logicalWin" && -n "$logicalTab" && -n "$curWin" && -n "$curTab" ]] || return 0
  typeset map="$GHOSTTY_ZMX_DATA_HOME/id-map"
  if ! _ghostty_zmx_valid_physical_id "$logicalWin" || ! _ghostty_zmx_valid_physical_id "$logicalTab" || ! _ghostty_zmx_valid_physical_id "$curWin" || ! _ghostty_zmx_valid_physical_id "$curTab"; then
    _ghostty_zmx_debug "id-map write skipped invalid ids logical_window=$logicalWin logical_tab=$logicalTab physical_window=$curWin physical_tab=$curTab"
    return 0
  fi
  mkdir -p "${map:h}" 2>/dev/null
  { grep -v -E "^(W ${curWin} |T ${curWin} ${curTab} )" "$map" 2>/dev/null || true
    print -r -- "W ${curWin} ${logicalWin}"
    print -r -- "T ${curWin} ${curTab} ${logicalWin} ${logicalTab}"
  } > "${map}.tmp"
  mv "${map}.tmp" "$map" 2>/dev/null
  _ghostty_zmx_debug "id-map write physical_window=$curWin physical_tab=$curTab logical_window=$logicalWin logical_tab=$logicalTab"
}

_ghostty_zmx_record_position_map() {
  typeset session="$1"
  typeset position="$2"
  _ghostty_zmx_valid_session_name "$session" || { _ghostty_zmx_debug "invalid session skipped action=record-position session=$session"; return 1; }
  [[ -n "$position" ]] || return 0
  typeset rest="${session#zmx-}"
  typeset logicalWin="${rest%%-*}"
  rest="${rest#*-}"
  typeset logicalTab="${rest%%-*}"
  typeset curWin=$(print -r -- "$position" | awk '{print $1}')
  typeset curTab=$(print -r -- "$position" | awk '{print $2}')
  _ghostty_zmx_write_id_map "$logicalWin" "$logicalTab" "$curWin" "$curTab"
}

_ghostty_zmx_restore() {
  typeset log="$(_ghostty_zmx_sessions_file)"
  [[ -f "$log" ]] || return 1
  typeset -a sessions
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if _ghostty_zmx_valid_session_name "$line"; then
      sessions+=("$line")
    else
      _ghostty_zmx_debug "invalid session skipped action=restore-load session=$line"
    fi
  done < "$log"
  typeset count=${#sessions}
  [[ $count -gt 0 ]] || return 1
  _ghostty_zmx_debug "restore sessions loaded count=$count file=$log"

  typeset queue="$GHOSTTY_ZMX_DATA_HOME/restore-queue"
  typeset firstFile="$GHOSTTY_ZMX_DATA_HOME/restore-first"
  typeset map="$GHOSTTY_ZMX_DATA_HOME/id-map"
  mkdir -p "${queue:h}" 2>/dev/null
  : > "$map"
  : > "$queue"
  typeset runtime_dir="$(_ghostty_zmx_runtime_dir)"
  [[ -n "$ghosttyPID" && -n "$runtime_dir" ]] && mkdir "$runtime_dir/restoring-${ghosttyPID}.lock" 2>/dev/null

  typeset -a _keys=()
  typeset -a _winKeys=()
  typeset -A _tabPanes=()
  typeset -A _tabSessions=()
  typeset -A _seen=()
  typeset -A _seenWin=()
  typeset -A _tabsByWin=()
  typeset s rest winHex tabHex key
  for s in "${sessions[@]}"; do
    rest="${s#zmx-}"
    winHex="${rest%%-*}"
    rest="${rest#*-}"
    tabHex="${rest%%-*}"
    key="${winHex}:${tabHex}"
    if [[ -z "${_seen[$key]:-}" ]]; then
      _seen[$key]=1
      _keys+=("$key")
      _tabPanes[$key]=0
      _tabSessions[$key]=""
      if [[ -z "${_seenWin[$winHex]:-}" ]]; then
        _seenWin[$winHex]=1
        _winKeys+=("$winHex")
        _tabsByWin[$winHex]=""
      fi
      _tabsByWin[$winHex]="${_tabsByWin[$winHex]} ${key}"
    fi
    _tabPanes[$key]=$(( ${_tabPanes[$key]} + 1 ))
    _tabSessions[$key]="${_tabSessions[$key]} ${s}"
  done

  typeset -a _groupedKeys=()
  typeset w groupedKey
  for w in "${_winKeys[@]}"; do
    for groupedKey in ${=_tabsByWin[$w]}; do
      _groupedKeys+=("$groupedKey")
    done
  done
  _keys=("${_groupedKeys[@]}")

  typeset -a _layoutSessions=()
  typeset layoutSes
  for key in "${_keys[@]}"; do
    for layoutSes in ${=_tabSessions[$key]}; do
      _layoutSessions+=("$layoutSes")
    done
  done
  _ghostty_zmx_debug "session grouping windows=${#_winKeys} tabs=${#_keys} sessions=${#_layoutSessions}"
  print -r -- "${_layoutSessions[1]}" > "$firstFile"
  _ghostty_zmx_debug "restore first session=${_layoutSessions[1]} file=$firstFile"

  _ghostty_zmx_restore_ids_valid() {
    _ghostty_zmx_valid_physical_id "$1" && _ghostty_zmx_valid_physical_id "$2"
  }
  _ghostty_zmx_restore_queue_push() {
    typeset session="$1"
    _ghostty_zmx_valid_session_name "$session" || return 1
    print -r -- "$session" >> "$queue"
    _ghostty_zmx_debug "queue push session=$session queue=$queue"
  }
  _ghostty_zmx_restore_queue_remove() {
    typeset session="$1"
    [[ -f "$queue" ]] || return 0
    awk -v session="$session" '$0 != session { print }' "$queue" > "${queue}.tmp.$$" 2>/dev/null && mv "${queue}.tmp.$$" "$queue" 2>/dev/null
  }

  typeset restore_lock_delay=$(( ${#_layoutSessions} * GHOSTTY_ZMX_RESTORE_STEP_DELAY + _ghostty_zmx_restore_lock_margin ))
  typeset restore_failed=0
  typeset curWin="" curTab="" firstWindow=1 physWin="" physTab=""
  typeset paneCount queuedSession initialSession created createdWin createdTab splitTerm
  typeset -a keySessions
  for key in "${_keys[@]}"; do
    winHex="${key%%:*}"
    tabHex="${key#*:}"
    paneCount="${_tabPanes[$key]}"
    keySessions=(${=_tabSessions[$key]})
    initialSession="${keySessions[1]}"

    if [[ "$winHex" != "$curWin" ]]; then
      if [[ $firstWindow -eq 1 ]]; then
        firstWindow=0
        typeset pos=$(_ghostty_zmx_current_position)
        physWin=$(print -r -- "$pos" | awk '{print $1}')
        physTab=$(print -r -- "$pos" | awk '{print $2}')
        if _ghostty_zmx_restore_ids_valid "$physWin" "$physTab"; then
          _ghostty_zmx_write_id_map "$winHex" "$tabHex" "$physWin" "$physTab"
        else
          restore_failed=1
          _ghostty_zmx_debug "restore failed step=current-position logical_window=$winHex logical_tab=$tabHex result=$pos"
        fi
      else
        _ghostty_zmx_restore_queue_push "$initialSession"
        created="$(_ghostty_zmx_applescript_surface_ids "$(osascript <<SCRIPT 2>/dev/null
tell application "$_ghostty_app_name"
    set cfg to new surface configuration
    set w to new window with configuration cfg
    set tb to selected tab of w
    activate window w
    set winStr to id of w as string
    set tabStr to id of tb as string
    return winStr & " " & tabStr
end tell
SCRIPT
)")" || {
          restore_failed=1
          _ghostty_zmx_restore_queue_remove "$initialSession"
          _ghostty_zmx_debug "restore failed step=new-window logical_window=$winHex logical_tab=$tabHex"
          sleep "$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
          continue
        }
        physWin=$(print -r -- "$created" | awk '{print $1}')
        physTab=$(print -r -- "$created" | awk '{print $2}')
        if _ghostty_zmx_restore_ids_valid "$physWin" "$physTab"; then
          _ghostty_zmx_write_id_map "$winHex" "$tabHex" "$physWin" "$physTab"
          _ghostty_zmx_debug "AppleScript new-window logical_window=$winHex logical_tab=$tabHex physical_window=$physWin physical_tab=$physTab delay=$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
        else
          restore_failed=1
          _ghostty_zmx_restore_queue_remove "$initialSession"
          _ghostty_zmx_debug "restore failed step=new-window logical_window=$winHex logical_tab=$tabHex result=$created"
        fi
        sleep "$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
      fi
      curWin="$winHex"
      curTab=""
    fi

    if [[ "$tabHex" != "$curTab" ]]; then
      if [[ -n "$curTab" ]]; then
        _ghostty_zmx_restore_queue_push "$initialSession"
        created="$(_ghostty_zmx_applescript_surface_ids "$(osascript <<SCRIPT 2>/dev/null
tell application "$_ghostty_app_name"
    set targetWindow to missing value
    repeat with w in windows
      set winStr to id of w as string
      if winStr ends with "$physWin" then
        set targetWindow to w
        exit repeat
      end if
    end repeat
    if targetWindow is missing value then error "target window not found"
    activate window targetWindow
    set cfg to new surface configuration
    set tb to new tab in targetWindow with configuration cfg
    select tab tb
    set winStr to id of targetWindow as string
    set tabStr to id of tb as string
    return winStr & " " & tabStr
end tell
SCRIPT
)")" || {
          restore_failed=1
          _ghostty_zmx_restore_queue_remove "$initialSession"
          _ghostty_zmx_debug "restore failed step=new-tab logical_window=$winHex logical_tab=$tabHex expected_window=$physWin"
          sleep "$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
          continue
        }
        createdWin=$(print -r -- "$created" | awk '{print $1}')
        createdTab=$(print -r -- "$created" | awk '{print $2}')
        if [[ "$createdWin" == "$physWin" ]] && _ghostty_zmx_restore_ids_valid "$createdWin" "$createdTab"; then
          physTab="$createdTab"
          _ghostty_zmx_write_id_map "$winHex" "$tabHex" "$physWin" "$physTab"
          _ghostty_zmx_debug "AppleScript new-tab logical_window=$winHex logical_tab=$tabHex physical_window=$physWin physical_tab=$physTab delay=$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
        else
          restore_failed=1
          _ghostty_zmx_restore_queue_remove "$initialSession"
          _ghostty_zmx_debug "restore failed step=new-tab logical_window=$winHex logical_tab=$tabHex expected_window=$physWin result=$created"
        fi
        sleep "$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
      fi
      curTab="$tabHex"
    fi

    typeset -i p
    for ((p=2; p<=paneCount; p++)); do
      typeset d="right"
      [[ $((p % 2)) -eq 0 ]] && d="down"
      queuedSession="${keySessions[$p]}"
      _ghostty_zmx_restore_queue_push "$queuedSession"
      splitTerm="$(osascript <<SCRIPT 2>/dev/null
tell application "$_ghostty_app_name"
    set targetWindow to missing value
    repeat with w in windows
      set winStr to id of w as string
      if winStr ends with "$physWin" then
        set targetWindow to w
        exit repeat
      end if
    end repeat
    if targetWindow is missing value then error "target window not found"
    set targetTab to missing value
    repeat with tb in tabs of targetWindow
      set tabStr to id of tb as string
      if tabStr ends with "$physTab" then
        set targetTab to tb
        exit repeat
      end if
    end repeat
    if targetTab is missing value then error "target tab not found"
    select tab targetTab
    set cfg to new surface configuration
    set t to focused terminal of targetTab
    set newTerminal to split t direction ${d} with configuration cfg
    return id of newTerminal as string
end tell
SCRIPT
)" && _ghostty_zmx_terminal_hash "$splitTerm" >/dev/null 2>&1
      if [[ $? -eq 0 ]]; then
        _ghostty_zmx_debug "AppleScript split logical_window=$winHex logical_tab=$tabHex physical_window=$physWin physical_tab=$physTab pane_index=$p direction=$d delay=$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
      else
        restore_failed=1
        _ghostty_zmx_restore_queue_remove "$queuedSession"
        _ghostty_zmx_debug "restore failed step=split logical_window=$winHex logical_tab=$tabHex physical_window=$physWin physical_tab=$physTab pane_index=$p direction=$d"
      fi
      sleep "$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
    done
  done
  if [[ "$restore_failed" -eq 1 ]]; then
    _ghostty_zmx_debug "restore failed status=incomplete expected_sessions=${#_layoutSessions}"
  fi
  if [[ -n "$ghosttyPID" && -n "$runtime_dir" ]]; then
    ( sleep "$restore_lock_delay"; rmdir "$runtime_dir/restoring-${ghosttyPID}.lock" 2>/dev/null ) &!
    _ghostty_zmx_debug "restore flag cleanup scheduled ghostty_pid=$ghosttyPID delay=$restore_lock_delay"
  fi
  return $restore_failed
}




ghostty_zmx_client_id_file() {
  print -r -- "${GHOSTTY_ZMX_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx}/client-id"
}

ghostty_zmx_client_id() {
  emulate -L zsh
  local id_file="$(ghostty_zmx_client_id_file)" id
  if [[ -r "$id_file" ]]; then
    IFS= read -r id < "$id_file" 2>/dev/null
    [[ "$id" =~ ^[A-Za-z0-9]{8,32}$ ]] && { print -r -- "$id"; return 0 }
  fi
  mkdir -p "${id_file:h}" 2>/dev/null
  id="$(od -An -N8 -tx4 /dev/urandom 2>/dev/null | tr -d '[:space:]')"
  print -r -- "$id" > "${id_file}.tmp.$$" 2>/dev/null && mv "${id_file}.tmp.$$" "$id_file" 2>/dev/null
  print -r -- "$id"
}



# Scan live Ghostty terminals and return TSV rows of projections found for a
# given remote session. Output: <pid> <tty> <win-id> <tab-id> <args-marker>
# Uses AppleScript pid/tty per terminal, then ps args to match the session.
# Does not trust AppleScript pid alone: a login wrapper may sit between.
# Enumerate live Ghostty terminals as space-delimited `pid tty win tab` lines.

# Walk descendants of a pid (BFS, depth-limited) and return matching pids whose
# ps args contain the given needle. Used to find `ghostty-zmx projection
# --session <gzr>` or `zmx attach <gzr>` under a login/wrapper/ssh chain.

# Scan live Ghostty terminals and return TSV rows of projections found for a
# given remote session. Output: <terminal-pid>\t<tty>\t<win-id>\t<tab-id>\t<match-pid>
# The <match-pid> is the process whose args matched (wrapper or ssh), used for
# the projection row. The terminal pid is the Ghostty-reported surface pid.

# Return 0 if at least one live projection exists for host+session, 1 else.
# If found, sets globals _gzmx_found_pid (terminal pid) / _gzmx_found_match_pid
# (matched projection process) / _gzmx_found_tty / _gzmx_found_win / _gzmx_found_tab.

# Write/replace a single remote-projection row atomically (under the global
# projection-file lock). Caller passes all fields.

# Update a projection row to `attached` by scanning live Ghostty terminals.
# Returns 0 if a live projection was found and the row written, 1 otherwise.
# This is the authoritative adoption/repair path: it walks descendants so it
# matches the wrapper (`--session <gzr>`) or ssh (`zmx attach <gzr>`).
ghostty_zmx_update_remote_projection() {
  emulate -L zsh
  setopt local_options no_sh_word_split
  local host="$1" workspace="$2" session="$3" state="${4:-attached}"
  [[ -n "$host" && -n "$workspace" && -n "$session" ]] || return 1
  ghostty_zmx_find_live_projection "$host" "$session" || return 1
  local win="-" tab="-"
  [[ -n "$_gzmx_found_win" ]] && win="$(ghostty_zmx_hex_suffix "$_gzmx_found_win" 2>/dev/null || print -r -- "$_gzmx_found_win")"
  [[ -n "$_gzmx_found_tab" ]] && tab="$(ghostty_zmx_hex_suffix "$_gzmx_found_tab" 2>/dev/null || print -r -- "$_gzmx_found_tab")"
  ghostty_zmx_write_projection_row "$host" "$workspace" "$session" "$_gzmx_found_tty" "$_gzmx_found_match_pid" "$state" "$win" "$tab"
}

ghostty_zmx_wait_remote_projection() {
  emulate -L zsh
  local host="$1" workspace="$2" session="$3" attempts="${4:-60}" delay="${5:-0.25}" i
  for (( i=1; i<=attempts; i++ )); do
    if ghostty_zmx_update_remote_projection "$host" "$workspace" "$session" attached; then
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

ghostty_zmx_projection_known() {
  emulate -L zsh
  local host="$1" session="$2" projection_file="$(ghostty_zmx_remote_projections_file)"
  [[ -f "$projection_file" ]] || return 1
  awk -F '\t' -v host="$host" -v session="$session" '$1 == host && $3 == session && ($6 == "opening" || $6 == "attached" || $6 == "closing") { found=1 } END { exit(found ? 0 : 1) }' "$projection_file" 2>/dev/null
}

# Return 0 if the projection row for host+session is a non-stale opening (a
# fresh in-progress create owned by another actor), 1 if absent/stale.
ghostty_zmx_projection_opening_fresh() {
  emulate -L zsh
  local host="$1" session="$2" now row_time ttl="${GHOSTTY_ZMX_OPENING_TTL:-30}"
  local projection_file="$(ghostty_zmx_remote_projections_file)"
  [[ -f "$projection_file" ]] || return 1
  row_time="$(awk -F '\t' -v host="$host" -v session="$session" '$1==host && $3==session && $6=="opening" { print $7; exit }' "$projection_file" 2>/dev/null)"
  [[ "$row_time" =~ ^[0-9]+$ ]] || return 1
  now="$(date +%s)"
  (( now - row_time < ttl ))
}

# Return 0 if the local projection row for <host,session> is in `closing` state.
# Used by the grouped restore to SKIP re-opening a session whose close-txn is
# in progress — re-opening it would undo the close and is the root cause of the
# "window recreated after close" bug.
ghostty_zmx_projection_closing() {
  emulate -L zsh
  local host="$1" session="$2" projection_file="$(ghostty_zmx_remote_projections_file)"
  [[ -f "$projection_file" ]] || return 1
  awk -F '\t' -v host="$host" -v session="$session" '$1 == host && $3 == session && $6 == "closing" { found=1 } END { exit(found ? 0 : 1) }' "$projection_file" 2>/dev/null
}

ghostty_zmx_remove_remote_projection() {
  emulate -L zsh
  local host="$1" session="$2" projection_file="$(ghostty_zmx_remote_projections_file)" tmp pid
  [[ -f "$projection_file" ]] || return 0
  pid="$(awk -F '\t' -v host="$host" -v session="$session" '$1 == host && $3 == session { print $5; exit }' "$projection_file" 2>/dev/null)"
  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    kill "$pid" >/dev/null 2>&1 || true
  fi
  tmp="${projection_file}.tmp.$$"
  awk -F '\t' -v host="$host" -v session="$session" '!(($1 == host) && ($3 == session)) { print }' "$projection_file" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$projection_file" 2>/dev/null || true
}


# Convert a projection prefix (ssh -t ...) into a no-pty argv for
# non-interactive commands (version probe, layout read/write, close
# transaction). For ssh, -T disables pty allocation (avoids
# `Pseudo-terminal will not be allocated` noise). For tsh ssh, -T/-t are
# not supported flags — tsh ssh is non-interactive when a command arg is
# provided, so no flag is needed. Prints the argv as a space-joined string.

# Path to the server-side ghostty-zmx-remote-layout helper, as invoked over
# ssh. The helper is installed by install-server.sh to
# ~/.config/ghostty-zmx/ on the remote host. We invoke it as a bare-word argv
# ($HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout <sub> <args>) so the
# ssh command is simple and carries no awk/printf/tabs/lock-loop
# metacharacters. (A prior theory blamed such command shapes for surface
# multiplication; that was disproven — the cause was orphaned poller shells.
# The bare-word argv is kept because it is simpler and correct.) See
# changelog 2026-07-01-v0-2-multiplication-root-cause-orphaned-poller-shells.

ghostty_zmx_remote_close_transaction() {
  emulate -L zsh
  setopt local_options no_sh_word_split
  local host="$1" session="$2" prefix helper rc
  [[ -n "$host" && -n "$session" ]] || return 1
  prefix="$(ghostty_zmx_remote_prefix_for_host "$host")"
  [[ -n "$prefix" ]] || return 1
  prefix="$(ghostty_zmx_notty_prefix "$prefix")"
  helper="$(ghostty_zmx_remote_layout_helper_cmd)"
  # `close` is a full transaction on the server: closing -> zmx kill -> deleted,
  # with the lock released across the zmx kill. The ssh argv is bare words only.
  # Return the ssh exit status so callers can detect a failed close (host
  # unreachable, etc.) and avoid deleting the local projection row — which
  # would cause the next poll cycle to re-open the just-closed projection.
  ${(z)prefix} "$helper" close "$session" >/dev/null 2>&1
  rc=$?
  return $rc
}

# Verify that a server layout row has reached `deleted` state. Used after a
# close transaction to decide whether it's safe to remove the local
# projection row: if the server didn't confirm `deleted` (ssh failure, or the
# helper exited non-zero), the local row must stay so the next cycle retries
# rather than re-opening a fresh projection for the still-`present` row.
ghostty_zmx_server_confirmed_deleted() {
  emulate -L zsh
  setopt local_options no_sh_word_split
  local host="$1" session="$2" prefix helper layout state
  [[ -n "$host" && -n "$session" ]] || return 1
  prefix="$(ghostty_zmx_remote_prefix_for_host "$host")"
  [[ -n "$prefix" ]] || return 1
  prefix="$(ghostty_zmx_notty_prefix "$prefix")"
  helper="$(ghostty_zmx_remote_layout_helper_cmd)"
  layout="$("${(z)prefix}" "$helper" read 2>/dev/null)" || return 1
  state="$(print -r -- "$layout" | awk -F '\t' -v s="$session" '$5==s {print $9; exit}')"
  [[ "$state" == "deleted" ]]
}

ghostty_zmx_cleanup_closed_remote_projections() {
  emulate -L zsh
  local projection_file="$(ghostty_zmx_remote_projections_file)" windows host workspace session tty_path pid state updated
  [[ -f "$projection_file" ]] || return 0
  windows="$(osascript -e "tell application \"$_ghostty_app_name\" to count of windows" 2>/dev/null)" || return 0
  [[ "$windows" =~ ^[0-9]+$ && "$windows" -gt 0 ]] || return 0
  while IFS=$'\t' read -r host workspace session tty_path pid state updated; do
    [[ "$state" == "attached" && "$pid" =~ ^[0-9]+$ ]] || continue
    kill -0 "$pid" 2>/dev/null && continue
    ghostty_zmx_remote_close_transaction "$host" "$session" || true
    ghostty_zmx_remove_remote_projection "$host" "$session"
  done < "$projection_file"
}

# Absolute path to the ghostty-zmx CLI wrapper used for projection windows.

# Build the Ghostty `surface configuration command` string for a projection.
# Uses the ghostty-zmx wrapper so the projection is observable by `ps` args
# (`--session <gzr>` marker) and signal handling is deterministic.
ghostty_zmx_projection_command_string() {
  emulate -L zsh
  local host="$1" workspace="$2" session="$3" prefix="$4" zmx_path="${5:-}" wrapper remote_zmx
  wrapper="$(ghostty_zmx_wrapper_path)"
  # Use the absolute remote zmx path discovered by the prerequisite probe when
  # available. This preserves hosts where zmx is in ~/.local/bin without
  # sourcing remote ~/.zshrc during attach; remote prompt/plugins can emit
  # terminal queries whose responses leak into zmx scrollback.
  if [[ "$zmx_path" =~ '^/[A-Za-z0-9._~+@%/=-]+$' ]]; then
    remote_zmx="$zmx_path"
  else
    remote_zmx="$(ghostty_zmx_remote_zmx_for_host "$host")"
  fi
  # The `zmx attach <session>` substring is preserved for process-arg scanning
  # (find_live_projection), including when remote_zmx is an absolute path such
  # as /home/user/.local/bin/zmx.
  print -r -- "$wrapper projection --host $host --workspace $workspace --session $session -- $prefix '$remote_zmx attach $session'"
}

# Recreate the remote window/tab/split layout from the server remote-layout's
# `present` rows, instead of opening one flat window per session. Mirrors the
# local _ghostty_zmx_restore grouping: rows are grouped by workspace/window/tab,
# the first pane of each window becomes a new window, subsequent tabs become
# new tabs in that window, and subsequent panes in the same tab become splits
# (using split-axis from the server row). Each pane is opened with a surface
# configuration whose command is the ghostty-zmx projection wrapper, so the
# pane attaches to its own remote zmx session.
#
# Only sessions that need opening (no live local projection and no fresh
# opening row) are recreated; sessions already live are left untouched. This
# makes the restore idempotent and safe to call on every poll cycle.
#
# Args: host prefix layout(TSV from server remote-layout)
ghostty_zmx_restore_remote_layout() {
  emulate -L zsh
  setopt local_options no_sh_word_split
  local host="$1" prefix="$2" layout="$3"
  [[ -n "$host" && -n "$prefix" && -n "$layout" ]] || return 1

  # Collect present rows that need a projection opened. Skip rows that already
  # have a live local projection, a fresh opening row, OR a `closing` local row
  # (a closing row means the close-txn is in progress — re-opening it would
  # undo the close and is the root cause of the "window recreated after close"
  # bug). Those are reconciled separately by the dead-pid cleanup path.
  local -a rows=()
  local _TAB=$'\t'
  local s_ws s_win s_tab s_pane s_session s_parent s_axis s_ratio s_state s_updated s_rev
  while IFS=$'\t' read -r s_ws s_win s_tab s_pane s_session s_parent s_axis s_ratio s_state s_updated s_rev; do
    [[ -n "$s_session" && "$s_session" == gzr-* && "$s_state" == "present" ]] || continue
    # Skip if a live projection already exists for this session.
    if ghostty_zmx_find_live_projection "$host" "$s_session" 2>/dev/null; then
      local win="-" tab="-"
      [[ -n "$_gzmx_found_win" ]] && win="$(ghostty_zmx_hex_suffix "$_gzmx_found_win" 2>/dev/null || print -r -- "$_gzmx_found_win")"
      [[ -n "$_gzmx_found_tab" ]] && tab="$(ghostty_zmx_hex_suffix "$_gzmx_found_tab" 2>/dev/null || print -r -- "$_gzmx_found_tab")"
      ghostty_zmx_write_projection_row "$host" "$s_ws" "$s_session" "$_gzmx_found_tty" "$_gzmx_found_match_pid" attached "$win" "$tab"
      continue
    fi
    # Skip if ANY local projection row exists for this session (attached, opening,
    # or closing). The dead-pid cleanup path owns removing stale rows; if the
    # grouped restore re-opens a session that still has a local row, it races
    # the cleanup and creates a duplicate window (the "window recreated after
    # close" bug). Only open projections for sessions with NO local row at all.
    if ghostty_zmx_projection_known "$host" "$s_session" 2>/dev/null; then
      _ghostty_zmx_debug "restore-layout skip-known host=$host session=$s_session"
      continue
    fi
    # Skip if a fresh opening row exists for this session.
    if ghostty_zmx_projection_opening_fresh "$host" "$s_session" 2>/dev/null; then
      continue
    fi
    # Skip if a closing row exists — the close-txn is in progress; do NOT re-open.
    if ghostty_zmx_projection_closing "$host" "$s_session" 2>/dev/null; then
      _ghostty_zmx_debug "restore-layout skip-closing host=$host session=$s_session"
      continue
    fi
    rows+=("${s_ws}${_TAB}${s_win}${_TAB}${s_tab}${_TAB}${s_pane}${_TAB}${s_session}${_TAB}${s_parent}${_TAB}${s_axis}${_TAB}${s_ratio}")
  done <<< "$layout"
  (( ${#rows} > 0 )) || return 0

  # Group rows by window then tab, preserving server order within each group.
  local -a _winKeys=()
  local -A _seenWin=() _tabsByWin=()
  local r _ws _win _tab _pane _session _parent _axis _ratio _wkey
  for r in "${rows[@]}"; do
    _ws="${r%%$'\t'*}"; r="${r#*$'\t'}"
    _win="${r%%$'\t'*}"; r="${r#*$'\t'}"
    _tab="${r%%$'\t'*}"; r="${r#*$'\t'}"
    _pane="${r%%$'\t'*}"; r="${r#*$'\t'}"
    _session="${r%%$'\t'*}"; r="${r#*$'\t'}"
    _parent="${r%%$'\t'*}"; r="${r#*$'\t'}"
    _axis="${r%%$'\t'*}"
    _wkey="${_ws}:${_win}"
    if [[ -z "${_seenWin[$_wkey]:-}" ]]; then
      _seenWin[$_wkey]=1
      _winKeys+=("$_wkey")
      _tabsByWin[$_wkey]=""
    fi
    _tabsByWin[$_wkey]="${_tabsByWin[$_wkey]} ${_tab}"
  done

  local _restore_delay="${GHOSTTY_ZMX_RESTORE_STEP_DELAY:-1}"
  local _created_win="" _created_tab="" _first_in_win=1
  local _cur_wkey="" _cur_tab=""
  local _command_string _as_cmd _rc
  for _wkey in "${_winKeys[@]}"; do
    local -a _tabList=(${=_tabsByWin[$_wkey]})
    local _tkey _first_in_tab=1
    _first_in_win=1
    for _tkey in "${_tabList[@]}"; do
      # Collect full rows for this tab in server order.
      local -a _tabPanes=()
      for r in "${rows[@]}"; do
        # Peek at the ws/win/tab fields without mutating r.
        local _peek="$r" _pw _pi _pt
        _pw="${_peek%%$'\t'*}"; _peek="${_peek#*$'\t'}"
        _pi="${_peek%%$'\t'*}"; _peek="${_peek#*$'\t'}"
        _pt="${_peek%%$'\t'*}"
        if [[ "$_pi" == "${_wkey#*:}" && "$_pt" == "$_tkey" ]]; then
          _tabPanes+=("$r")
        fi
      done
      (( ${#_tabPanes} > 0 )) || continue

      local _pidx=1 _pane_row _p_ws _p_win _p_tab _p_pane _p_session _p_parent _p_axis _p_ratio
      for _pane_row in "${_tabPanes[@]}"; do
        _p_ws="${_pane_row%%$'\t'*}"; _pane_row="${_pane_row#*$'\t'}"
        _p_win="${_pane_row%%$'\t'*}"; _pane_row="${_pane_row#*$'\t'}"
        _p_tab="${_pane_row%%$'\t'*}"; _pane_row="${_pane_row#*$'\t'}"
        _p_pane="${_pane_row%%$'\t'*}"; _pane_row="${_pane_row#*$'\t'}"
        _p_session="${_pane_row%%$'\t'*}"; _pane_row="${_pane_row#*$'\t'}"
        _p_parent="${_pane_row%%$'\t'*}"; _pane_row="${_pane_row#*$'\t'}"
        _p_axis="${_pane_row%%$'\t'*}"

        # Re-check liveness under the per-session lock before opening.
        local _lock _acq=0 _i
        _lock="$(ghostty_zmx_projection_lock_path "$host" "$_p_session")" || { _pidx=$((_pidx+1)); continue; }
        mkdir -p "${_lock:h}" 2>/dev/null
        for (( _i=1; _i<=50; _i++ )); do
          mkdir "$_lock" 2>/dev/null && { _acq=1; break; }
          sleep 0.03
        done
        if [[ "$_acq" -ne 1 ]]; then
          _ghostty_zmx_debug "restore-layout lock-busy host=$host session=$_p_session"
          _pidx=$((_pidx+1)); continue
        fi
        # Under the lock, re-verify no live projection appeared.
        if ghostty_zmx_find_live_projection "$host" "$_p_session" 2>/dev/null; then
          local win="-" tab="-"
          [[ -n "$_gzmx_found_win" ]] && win="$(ghostty_zmx_hex_suffix "$_gzmx_found_win" 2>/dev/null || print -r -- "$_gzmx_found_win")"
          [[ -n "$_gzmx_found_tab" ]] && tab="$(ghostty_zmx_hex_suffix "$_gzmx_found_tab" 2>/dev/null || print -r -- "$_gzmx_found_tab")"
          ghostty_zmx_write_projection_row "$host" "$_p_ws" "$_p_session" "$_gzmx_found_tty" "$_gzmx_found_match_pid" attached "$win" "$tab"
          rmdir "$_lock" 2>/dev/null || true
          _pidx=$((_pidx+1)); continue
        fi
        ghostty_zmx_write_projection_row "$host" "$_p_ws" "$_p_session" "-" "-" opening "-" "-"
        _command_string="$(ghostty_zmx_projection_command_string "$host" "$_p_ws" "$_p_session" "$prefix")"
        _as_cmd="${_command_string//\\\\/\\\\\\\\}"
        _as_cmd="${_as_cmd//\"/\\\"}"
        _rc=0
        if (( _first_in_win == 1 && _pidx == 1 )); then
          # First pane of a new window: new window with the projection command.
          _ghostty_zmx_debug "restore-layout new-window host=$host session=$_p_session wkey=$_wkey"
          _created="$(_ghostty_zmx_applescript_surface_ids "$(osascript <<OSA 2>/dev/null
tell application "$_ghostty_app_name"
  set cfg to new surface configuration
  set command of cfg to "$_as_cmd"
  set w to new window with configuration cfg
  set tb to selected tab of w
  activate window w
  set winStr to id of w as string
  set tabStr to id of tb as string
  return winStr & " " & tabStr
end tell
OSA
)")" || _rc=$?
          if [[ "$_rc" -eq 0 ]]; then
            _created_win="$(print -r -- "$_created" | awk '{print $1}')"
            _created_tab="$(print -r -- "$_created" | awk '{print $2}')"
          fi
          # The first pane consumed the window's first tab; subsequent panes
          # in this tab must split, not open a new tab.
          _first_in_tab=0
        elif (( _first_in_tab == 1 )); then
          # First pane of a new tab in the current window.
          _ghostty_zmx_debug "restore-layout new-tab host=$host session=$_p_session wkey=$_wkey tab=$_tkey"
          _created="$(_ghostty_zmx_applescript_surface_ids "$(osascript <<OSA 2>/dev/null
tell application "$_ghostty_app_name"
  set targetWindow to missing value
  repeat with w in windows
    set winStr to id of w as string
    if winStr ends with "$_created_win" then
      set targetWindow to w
      exit repeat
    end if
  end repeat
  if targetWindow is missing value then error "target window not found"
  activate window targetWindow
  set cfg to new surface configuration
  set command of cfg to "$_as_cmd"
  set tb to new tab in targetWindow with configuration cfg
  select tab tb
  set tabStr to id of tb as string
  return "$_created_win" & " " & tabStr
end tell
OSA
)")" || _rc=$?
          if [[ "$_rc" -eq 0 ]]; then
            _created_tab="$(print -r -- "$_created" | awk '{print $2}')"
          fi
          _first_in_tab=0
        else
          # Subsequent pane in the same tab: split the focused terminal.
          local _dir="right"
          [[ "$_p_axis" == "vertical" ]] && _dir="down"
          _ghostty_zmx_debug "restore-layout split host=$host session=$_p_session wkey=$_wkey tab=$_tkey axis=$_p_axis dir=$_dir"
          osascript <<OSA 2>/dev/null || _rc=$?
tell application "$_ghostty_app_name"
  set targetWindow to missing value
  repeat with w in windows
    set winStr to id of w as string
    if winStr ends with "$_created_win" then
      set targetWindow to w
      exit repeat
    end if
  end repeat
  if targetWindow is missing value then error "target window not found"
  set targetTab to missing value
  repeat with tb in tabs of targetWindow
    set tabStr to id of tb as string
    if tabStr ends with "$_created_tab" then
      set targetTab to tb
      exit repeat
    end if
  end repeat
  if targetTab is missing value then error "target tab not found"
  select tab targetTab
  set cfg to new surface configuration
  set command of cfg to "$_as_cmd"
  set t to focused terminal of targetTab
  set newTerminal to split t direction $_dir with configuration cfg
end tell
OSA
        fi
        rmdir "$_lock" 2>/dev/null || true
        if [[ "$_rc" -ne 0 ]]; then
          _ghostty_zmx_debug "restore-layout open-failed host=$host session=$_p_session rc=$_rc"
        else
          ( ghostty_zmx_wait_remote_projection "$host" "$_p_ws" "$_p_session" 60 0.25 ) &!
        fi
        _pidx=$((_pidx+1))
        sleep "$_restore_delay"
      done
      _first_in_tab=0
    done
    _first_in_win=0
  done
}

# The single entry point for opening a remote projection. Idempotent:
# acquires a per-host+session lock, scans live projections first (adopting any
# found), skips if a non-stale opening row exists, and only otherwise opens a
# new projection window through the ghostty-zmx wrapper. Returns 0 if a
# projection is live/known after the call, 1 on failure to open.
ghostty_zmx_reconcile_remote_projection() {
  emulate -L zsh
  setopt local_options no_sh_word_split
  local host="$1" workspace="$2" session="$3" prefix="$4"
  local lock_path acquired=0 i now command_string applescript_command
  [[ -n "$host" && -n "$workspace" && -n "$session" && -n "$prefix" ]] || return 1
  lock_path="$(ghostty_zmx_projection_lock_path "$host" "$session")" || return 1
  mkdir -p "${lock_path:h}" 2>/dev/null
  for (( i=1; i<=50; i++ )); do
    if mkdir "$lock_path" 2>/dev/null; then acquired=1; break; fi
    sleep 0.03
  done
  if [[ "$acquired" -ne 1 ]]; then
    _ghostty_zmx_debug "reconcile lock-busy host=$host session=$session"
    return 1
  fi

  # 1. Scan live projections under the lock; adopt if found.
  if ghostty_zmx_find_live_projection "$host" "$session"; then
    local win="-" tab="-"
    [[ -n "$_gzmx_found_win" ]] && win="$(ghostty_zmx_hex_suffix "$_gzmx_found_win" 2>/dev/null || print -r -- "$_gzmx_found_win")"
    [[ -n "$_gzmx_found_tab" ]] && tab="$(ghostty_zmx_hex_suffix "$_gzmx_found_tab" 2>/dev/null || print -r -- "$_gzmx_found_tab")"
    ghostty_zmx_write_projection_row "$host" "$workspace" "$session" "$_gzmx_found_tty" "$_gzmx_found_match_pid" attached "$win" "$tab"
    _ghostty_zmx_debug "reconcile adopted host=$host session=$session tty=$_gzmx_found_tty pid=$_gzmx_found_match_pid"
    rmdir "$lock_path" 2>/dev/null || true
    return 0
  fi

  # 2. No live projection. Skip if a fresh (non-stale) opening row exists.
  if ghostty_zmx_projection_opening_fresh "$host" "$session"; then
    _ghostty_zmx_debug "reconcile skip-fresh-opening host=$host session=$session"
    rmdir "$lock_path" 2>/dev/null || true
    return 0
  fi

  # 3. No live projection and no fresh opening: open a new projection.
  now="$(date +%s)"
  ghostty_zmx_write_projection_row "$host" "$workspace" "$session" "-" "-" opening "-" "-"
  command_string="$(ghostty_zmx_projection_command_string "$host" "$workspace" "$session" "$prefix")"
  _ghostty_zmx_debug "reconcile opening host=$host session=$session cmd=$command_string"
  # Open the projection window via AppleScript `new window with configuration`
  # targeting the hosting app by name. This delivers the window to the
  # already-running Ghostty process (the one that hosts the local shell),
  # unlike `open -na --config-file` which can spawn a NEW Ghostty process
  # under macOS background-app management, causing stray processes and
  # non-deterministic window counts. See changelog
  # 2026-06-30-v0-2-multiplication-open-na-spawns-stray-processes.
  local _open_rc=0
  osascript <<OSA 2>/dev/null || _open_rc=$?
tell application "$_ghostty_app_name"
  set cfg to new surface configuration
  set command of cfg to "$command_string"
  set w to new window with configuration cfg
  activate window w
end tell
OSA
  if [[ "$_open_rc" -ne 0 ]]; then
    rmdir "$lock_path" 2>/dev/null || true
    _ghostty_zmx_debug "reconcile open-failed host=$host session=$session rc=$_open_rc"
    return 1
  fi
  rmdir "$lock_path" 2>/dev/null || true
  ( ghostty_zmx_wait_remote_projection "$host" "$workspace" "$session" 60 0.25 ) &!
  return 0
}

# Back-compat shim: callers that reserved externally now delegate to reconcile.

ghostty_zmx_detect_ghostty_pid() {
  emulate -L zsh
  local p=$$ cmd
  while [[ $p -gt 1 ]]; do
    cmd="$(ps -o comm= -p $p 2>/dev/null)"
    if [[ "${cmd:l}" == *ghostty* ]]; then
      print -r -- "$p"
      return 0
    fi
    p=$(ps -o ppid= -p $p 2>/dev/null | tr -d ' ')
  done
  return 1
}

# Snapshot a single remote session's scrollback over ssh into the lazy
# history store. Used on Cmd-Q (ghostty-exit) so a later reopen/restore can
# inject the saved scrollback into a fresh remote session if the remote zmx
# daemon/session was lost (remote reboot). The zmx history call runs over ssh
# -T (no pty) and the result is namespaced by host. Failures are logged and
# non-fatal: an unreachable host leaves the prior snapshot (if any).
ghostty_zmx_snapshot_remote_session() {
  emulate -L zsh
  local host="$1" session="$2" prefix notty dir hist_file tmp remote_zmx scrollback="${GHOSTTY_ZMX_SCROLLBACK_LINES:-1000}"
  prefix="$(ghostty_zmx_remote_prefix_for_host "$host")"
  [[ -n "$prefix" ]] || return 1
  prefix="$(ghostty_zmx_notty_prefix "$prefix")"
  dir="${GHOSTTY_ZMX_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-zmx}/history/$host"
  mkdir -p "$dir" 2>/dev/null || return 1
  hist_file="$dir/${session}.txt"
  tmp="${hist_file}.tmp.$$"
  # Fetch remote scrollback (no pty) and truncate to the configured line count.
  # ssh concatenates trailing args into the remote command string, so inline the
  # session name (hex+dashes — shell-safe) rather than using $0. Use the probed
  # absolute zmx path when available; do not source remote ~/.zshrc here.
  # A failure (host down, session gone) leaves the prior snapshot in place.
  remote_zmx="$(ghostty_zmx_remote_zmx_for_host "$host")"
  if ${(z)prefix} "$remote_zmx history $session 2>/dev/null" | tail -n "$scrollback" > "$tmp" 2>/dev/null; then
    [[ -s "$tmp" ]] && mv "$tmp" "$hist_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    _ghostty_zmx_debug "remote snapshot host=$host session=$session file=$hist_file"
  else
    rm -f "$tmp" 2>/dev/null
    _ghostty_zmx_debug "remote snapshot failed host=$host session=$session (left prior)"
  fi
}

# Snapshot all currently-attached remote projections. Called on ghostty-exit
# (Cmd-Q) so the lazy remote scrollback store is refreshed before the poller
# stops. Each session is snapshotted independently; a single failure does not
# abort the rest.
ghostty_zmx_snapshot_remote_sessions() {
  emulate -L zsh
  local projection_file="$(ghostty_zmx_remote_projections_file)"
  [[ -f "$projection_file" ]] || return 0
  local p_host p_workspace p_session p_tty p_pid p_state p_updated p_win p_tab
  while IFS=$'\t' read -r p_host p_workspace p_session p_tty p_pid p_state p_updated p_win p_tab; do
    [[ "$p_state" == "attached" && "$p_session" == gzr-* ]] || continue
    ghostty_zmx_snapshot_remote_session "$p_host" "$p_session" || true
  done < "$projection_file"
}

# One poll cycle: read server remote-layout for each active host and reconcile
# local projections (adopt live, open missing present rows, remove
# closing/deleted, clean up dead-pid rows). $1=1 means startup_grace (first
# cycle after reopen — don't close-txn dead pids). $2=owning Ghostty pid (used
# to detect Cmd-Q: if the owning Ghostty is dead/dying, preserve remote
# sessions instead of close-txn'ing them). Shared by the standalone poller via
# the GHOSTTY_ZMX_INTERNAL_POLLER guard so it cannot diverge from the
# manager's other projection helpers.
ghostty_zmx_poll_once() {
  emulate -L zsh
  setopt local_options no_sh_word_split
  local startup_grace="${1:-0}"
  local ghostty_pid="${2:-}"
  local hosts_file="$(ghostty_zmx_remote_hosts_file)"
  local projection_file="$(ghostty_zmx_remote_projections_file)"
  local host transport version mode prefix
  [[ -f "$hosts_file" ]] || return 0
  while IFS=$'\t' read -r host transport version mode prefix; do
    [[ -n "$host" && "$mode" == "active" && -n "$prefix" ]] || continue

    # 1. Read the server-authoritative remote-layout for this host.
    local notty="$(ghostty_zmx_notty_prefix "$prefix")"
    local helper='$HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout'
    local layout
    layout="$("${(z)notty}" "$helper" read 2>/dev/null)" || layout=""

    # 2. Local-side cleanup FIRST: close-txn dead-pid projections before
    #    opening missing ones. This ordering is critical: if a user just closed
    #    a pane, the server row is still `present`. If we opened missing
    #    projections first, we'd re-open the just-closed pane before the
    #    close transaction had a chance to transition the server row to
    #    `deleted`. Running close-txn first ensures the server row is deleted
    #    by the time we reconcile `present` rows below.
    if [[ -f "$projection_file" ]]; then
      local _wc
      _wc="$(osascript -e "tell application \"$_ghostty_app_name\" to count of windows" 2>/dev/null || echo '?')"
      local _app_alive=0
      [[ "$_wc" =~ ^[0-9]+$ && "$_wc" -gt 0 ]] && _app_alive=1
      local p_host p_workspace p_session p_tty p_pid p_state p_updated p_win p_tab
      while IFS=$'\t' read -r p_host p_workspace p_session p_tty p_pid p_state p_updated p_win p_tab; do
        [[ "$p_host" == "$host" && ( "$p_state" == "attached" || "$p_state" == "opening" || "$p_state" == "closing" ) ]] || continue
        if [[ "$p_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$p_pid" 2>/dev/null; then
          if ghostty_zmx_find_live_projection "$p_host" "$p_session" 2>/dev/null; then
            local win="-" tab="-"
            [[ -n "$_gzmx_found_win" ]] && win="$(ghostty_zmx_hex_suffix "$_gzmx_found_win" 2>/dev/null || print -r -- "$_gzmx_found_win")"
            [[ -n "$_gzmx_found_tab" ]] && tab="$(ghostty_zmx_hex_suffix "$_gzmx_found_tab" 2>/dev/null || print -r -- "$_gzmx_found_tab")"
            ghostty_zmx_write_projection_row "$p_host" "$p_workspace" "$p_session" "$_gzmx_found_tty" "$_gzmx_found_match_pid" attached "$win" "$tab"
            _ghostty_zmx_debug "poller adopted-dead-owner host=$p_host session=$p_session pid=$_gzmx_found_match_pid"
          elif [[ "$p_state" == "opening" ]] && ghostty_zmx_projection_opening_fresh "$p_host" "$p_session" 2>/dev/null; then
            _ghostty_zmx_debug "poller skip-fresh-opening-dead-owner host=$p_host session=$p_session pid=$p_pid"
          elif [[ "$_app_alive" -eq 1 ]] && [[ "$startup_grace" -ne 1 ]] && { [[ -z "$ghostty_pid" ]] || kill -0 "$ghostty_pid" 2>/dev/null; }; then
            # Pane close: run the server close transaction. Only remove the
            # local projection row if the server confirmed `deleted` — if the
            # close-txn failed (ssh timeout, host unreachable), the server
            # row stays `present` and removing the local row would cause the
            # next poll cycle's grouped restore to re-open the just-closed
            # projection (the "reopen after close" bug). Keep the row as
            # `closing` so the next cycle retries the close-txn.
            if ghostty_zmx_remote_close_transaction "$p_host" "$p_session" 2>/dev/null && ghostty_zmx_server_confirmed_deleted "$p_host" "$p_session" 2>/dev/null; then
              ghostty_zmx_remove_remote_projection "$p_host" "$p_session"
              _ghostty_zmx_debug "poller close-txn host=$p_host session=$p_session pid=$p_pid server=deleted"
            else
              # Close-txn failed (or server still not deleted). Mark the row
              # `closing` so the next cycle retries; do NOT remove it, which
              # would trigger a re-open. Also kill the dead ssh pid's entry so
              # it's not mistaken for a live projection.
              ghostty_zmx_write_projection_row "$p_host" "$p_workspace" "$p_session" "$p_tty" "$p_pid" closing "$p_win" "$p_tab"
              _ghostty_zmx_debug "poller close-txn-failed host=$p_host session=$p_session pid=$p_pid retry-next-cycle"
            fi
          else
            # startup_grace (first poll cycle after Ghostty launch): the dead
            # pid may be a stale leftover from a prior session (Cmd-Q+reopen)
            # OR a genuine pane close that happened before the first poll. We
            # cannot distinguish them, so PRESERVE the row as-is (do NOT remove
            # it, do NOT run close-txn). The next cycle (startup_grace=0) will
            # either: (a) if it was a stale pid from a prior session, the live
            # projection will have appeared and we adopt it; or (b) if it was a
            # genuine close, the pid stays dead and we run the close-txn then.
            # Removing the row here would cause the grouped restore to re-open
            # the projection (the "window recreated after close" bug).
            _ghostty_zmx_debug "poller preserve-on-quit host=$p_host session=$p_session pid=$p_pid startup_grace=$startup_grace"
          fi
        elif ghostty_zmx_find_live_projection "$p_host" "$p_session" 2>/dev/null; then
          local win="-" tab="-"
          [[ -n "$_gzmx_found_win" ]] && win="$(ghostty_zmx_hex_suffix "$_gzmx_found_win" 2>/dev/null || print -r -- "$_gzmx_found_win")"
          [[ -n "$_gzmx_found_tab" ]] && tab="$(ghostty_zmx_hex_suffix "$_gzmx_found_tab" 2>/dev/null || print -r -- "$_gzmx_found_tab")"
          ghostty_zmx_write_projection_row "$p_host" "$p_workspace" "$p_session" "$_gzmx_found_tty" "$_gzmx_found_match_pid" attached "$win" "$tab"
          [[ "$p_state" == "opening" ]] && _ghostty_zmx_debug "poller adopted host=$p_host session=$p_session pid=$_gzmx_found_match_pid"
        fi
      done < "$projection_file"
    fi

    # 3. Re-read the server layout (the close-txn above may have mutated it)
    #    and reconcile each server row: adopt live projections, remove
    #    closing/deleted, and open missing `present` rows as a grouped
    #    window/tab/split layout.
    layout="$("${(z)notty}" "$helper" read 2>/dev/null)" || layout=""
    local s_ws s_win s_tab s_pane s_session s_parent s_axis s_ratio s_state s_updated s_rev
    local _need_grouped_restore=0
    while IFS=$'\t' read -r s_ws s_win s_tab s_pane s_session s_parent s_axis s_ratio s_state s_updated s_rev; do
      [[ -n "$s_session" && "$s_session" == gzr-* ]] || continue
      case "$s_state" in
        present)
          if ghostty_zmx_find_live_projection "$host" "$s_session" 2>/dev/null; then
            local win="-" tab="-"
            [[ -n "$_gzmx_found_win" ]] && win="$(ghostty_zmx_hex_suffix "$_gzmx_found_win" 2>/dev/null || print -r -- "$_gzmx_found_win")"
            [[ -n "$_gzmx_found_tab" ]] && tab="$(ghostty_zmx_hex_suffix "$_gzmx_found_tab" 2>/dev/null || print -r -- "$_gzmx_found_tab")"
            ghostty_zmx_write_projection_row "$host" "$s_ws" "$s_session" "$_gzmx_found_tty" "$_gzmx_found_match_pid" attached "$win" "$tab"
          elif ghostty_zmx_projection_opening_fresh "$host" "$s_session" 2>/dev/null; then
            _ghostty_zmx_debug "poller skip-fresh-opening host=$host session=$s_session"
          elif ghostty_zmx_projection_closing "$host" "$s_session" 2>/dev/null; then
            :  # close-txn in progress — do NOT re-open; the dead-pid cleanup
               # will retry the close next cycle. Re-opening here would undo
               # the close (the "window recreated after close" bug).
          elif ghostty_zmx_projection_known "$host" "$s_session" 2>/dev/null; then
            :  # A local row exists (attached/opening/closing). The dead-pid
               # cleanup path owns removing stale rows; the grouped restore
               # skips known rows to avoid racing the cleanup. Do NOT set
               # _need_grouped_restore here — that would re-open a session
               # whose local row is being cleaned up.
          else
            _need_grouped_restore=1
          fi
          ;;
        closing|deleted)
          # Only log/act if a local projection still exists for this session.
          # Once the local row is removed, this is a no-op — the deleted
          # tombstone will be compacted by the periodic `compact` call below.
          if ghostty_zmx_projection_known "$host" "$s_session" 2>/dev/null; then
            ghostty_zmx_remove_remote_projection "$host" "$s_session"
            _ghostty_zmx_debug "poller server-removed host=$host session=$s_session state=$s_state"
          fi
          ;;
      esac
    done <<< "$layout"

    # Recreate missing present projections as a grouped window/tab/split layout
    # so the restored shape matches the server remote-layout. The grouped
    # restore is idempotent (skips live/fresh-opening/closing rows under
    # per-session locks), so it is safe to call on every poll cycle.
    (( _need_grouped_restore == 1 )) && ghostty_zmx_restore_remote_layout "$host" "$prefix" "$layout"

    # Compact deleted tombstones periodically so the server layout doesn't
    # grow unboundedly and the poller doesn't log `server-removed` for already-
    # removed projections every cycle. The helper's `compact` subcommand
    # removes deleted rows older than GHOSTTY_ZMX_TOMBSTONE_TTL (default 3600s).
    # Run it roughly every 60 poll cycles (~3min at 3s interval) to amortize
    # the ssh cost. Uses a counter persisted in the runtime dir.
    local _compact_flag="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ghostty-zmx-${UID:-$(id -u)}/compact-counter"
    local _cc=0
    [[ -r "$_compact_flag" ]] && read -r _cc < "$_compact_flag" 2>/dev/null || _cc=0
    _cc=$((_cc + 1))
    print -r -- "$_cc" > "$_compact_flag" 2>/dev/null || true
    (( _cc % 60 == 0 )) && { ${(z)notty} "$helper" compact >/dev/null 2>&1 || true }
  done < "$hosts_file"
}

# Kill orphaned remote-poller scripts whose owning Ghostty PID is dead or
# PID-reused. Called at the top of start_remote_poller so a fresh shell
# self-heals leftover pollers from crashed/killed Ghostty instances instead
# of accumulating them (the stray-poller root cause). Never kills the poller
# for the current $exclude_pid (the live owner).
ghostty_zmx_kill_orphaned_pollers() {
  emulate -L zsh
  local exclude_pid="$1" runtime="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ghostty-zmx-${UID:-$(id -u)}"
  [[ -d "$runtime" ]] || return 0
  local script ppid_from_name owner_elapsed
  for script in "$runtime"/remote-poller-*.zsh(N); do
    # Extract the ghostty pid from the script filename: remote-poller-<pid>.zsh
    ppid_from_name="${script:t}"
    ppid_from_name="${ppid_from_name#remote-poller-}"
    ppid_from_name="${ppid_from_name%.zsh}"
    [[ "$ppid_from_name" =~ ^[0-9]+$ ]] || continue
    [[ "$ppid_from_name" == "$exclude_pid" ]] && continue
    # Is that Ghostty PID still alive? If not, the poller is orphaned.
    if ! kill -0 "$ppid_from_name" 2>/dev/null; then
      # Find the actual zsh process running this script and kill it.
      local _zpid
      for _zpid in $(pgrep -f "remote-poller-${ppid_from_name}\.zsh" 2>/dev/null); do
        kill -9 "$_zpid" 2>/dev/null || true
      done
      # Clean up its lock dir too. Use nullglob (N) so a non-matching glob is
      # empty instead of erroring with "no matches found" under nomatch.
      local _oldlock
      for _oldlock in "$runtime"/remote-poller-*-${ppid_from_name}.lock(N); do
        rm -rf "$_oldlock" 2>/dev/null || true
      done
      _ghostty_zmx_debug "poller killed-orphan ghostty_pid=$ppid_from_name script=${script:t}"
      continue
    fi
    # PID alive — but is it a reused (younger) PID? If the owning Ghostty's
    # current elapsed is less than a nominal threshold, the PID was reused.
    owner_elapsed="$(_ghostty_zmx_ghostty_elapsed_seconds "$ppid_from_name" 2>/dev/null)" || owner_elapsed=""
    # Heuristic: a real Ghostty process has elapsed > 0. A reused PID for a
    # short-lived process will have a very small elapsed. We can't compare
    # against a saved token here (the orphan may predate the token fix), so
    # only treat as orphan if the lock dir has NO elapsed file (pre-fix style).
    local _lock="$runtime/remote-poller-${_ghostty_app_name}-${ppid_from_name}.lock"
    if [[ -d "$_lock" && ! -f "$_lock/elapsed" ]]; then
      local _zpid
      for _zpid in $(pgrep -f "remote-poller-${ppid_from_name}\.zsh" 2>/dev/null); do
        kill -9 "$_zpid" 2>/dev/null || true
      done
      rm -rf "$_lock" 2>/dev/null || true
      _ghostty_zmx_debug "poller killed-pre-fix-orphan ghostty_pid=$ppid_from_name script=${script:t}"
    fi
  done
}

ghostty_zmx_start_remote_poller() {
  emulate -L zsh
  local force=0 ghostty_pid="${1:-}" runtime="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ghostty-zmx-${UID:-$(id -u)}" flag interval="${GHOSTTY_ZMX_REMOTE_POLL_INTERVAL:-3}" oldpid="" old_elapsed="" cur_elapsed=""
  if [[ "$ghostty_pid" == "force" ]]; then
    force=1
    ghostty_pid=""
  fi
  [[ "$force" -eq 1 || ( -z "${ZMX_SESSION:-}" && -z "${TMUX:-}" ) ]] || return 0
  [[ -n "$ghostty_pid" ]] || ghostty_pid="$(ghostty_zmx_detect_ghostty_pid)" || return 0
  [[ "$ghostty_pid" =~ ^[0-9]+$ ]] || return 0
  # Self-heal orphaned pollers before starting a new one. This kills leftover
  # poller scripts whose owning Ghostty PID is dead or was a pre-fix orphan
  # (no elapsed token). Without this, a fresh shell stacks alongside the
  # orphans, and each orphan independently polls the server layout and re-opens
  # projections — the stray-poller root cause.
  ghostty_zmx_kill_orphaned_pollers "$ghostty_pid"
  # PID-reuse-safe token: capture the owning Ghostty's elapsed-seconds at
  # startup. The poller loop re-derives current elapsed and exits if the
  # owning PID is reused by a younger process (current < saved) or gone
  # (empty). Mirrors the reaper's _ghostty_zmx_ghostty_elapsed_seconds check.
  # See changelog
  # 2026-07-01-v0-2-multiplication-root-cause-orphaned-poller-shells.
  local ghostty_elapsed=""
  ghostty_elapsed="$(_ghostty_zmx_ghostty_elapsed_seconds "$ghostty_pid" 2>/dev/null)" || ghostty_elapsed=0
  mkdir -p "$runtime" 2>/dev/null || return 0
  flag="$runtime/remote-poller-${_ghostty_app_name}-${ghostty_pid}.lock"
  if ! mkdir "$flag" 2>/dev/null; then
    # Stale-owner check is PID-reuse-safe: verify the recorded owner is alive
    # AND its current elapsed is >= the recorded elapsed (same process). A
    # bare `kill -0 $oldpid` succeeds against a reused PID and lets a second
    # poller stack on a dead lock's owner — the root cause of the orphaned-
    # poller multiplication.
    [[ -f "$flag/pid" ]] && read -r oldpid < "$flag/pid" 2>/dev/null || oldpid=""
    [[ -f "$flag/elapsed" ]] && read -r old_elapsed < "$flag/elapsed" 2>/dev/null || old_elapsed=""
    if [[ -n "$oldpid" && "$oldpid" =~ ^[0-9]+$ ]] && kill -0 "$oldpid" 2>/dev/null; then
      cur_elapsed="$(_ghostty_zmx_ghostty_elapsed_seconds "$oldpid" 2>/dev/null)" || cur_elapsed=""
      if [[ -z "$old_elapsed" || -z "$cur_elapsed" || "$cur_elapsed" -lt "$old_elapsed" ]]; then
        _ghostty_zmx_debug "poller stale-owner reuse owner=$oldpid saved_elapsed=$old_elapsed cur_elapsed=$cur_elapsed; reclaiming"
      else
        # Live owner, same process. Keep it.
        return 0
      fi
    fi
    rm -rf "$flag" 2>/dev/null || return 0
    mkdir "$flag" 2>/dev/null || return 0
  fi
  # Generate a thin poller script that SOURCES the manager (with the
  # GHOSTTY_ZMX_INTERNAL_POLLER=1 guard so it defines all functions then
  # returns — no widget install, no auto-attach, no nested poller start).
  # The poller then calls the shared manager functions (ghostty_zmx_poll_once,
  # ghostty_zmx_snapshot_remote_sessions). This eliminates the prior ~400-line
  # inlined duplicate of find_live_projection/write_projection_row/etc., which
  # had diverged from the manager copies and caused the leading-space-pid bug
  # (the inlined find_live_projection used string-concatenation BFS under
  # no_sh_word_split; the manager's ghostty_zmx_descendants_matching used arrays).
  # See changelog 2026-07-02-v0-2-remote-split-tab-restore-e2e-docker-tsh and
  # 2026-07-01-v0-2-multiplication-root-cause-orphaned-poller-shells.
  local script="$runtime/remote-poller-${ghostty_pid}.zsh"
  local poller_log="$runtime/remote-poller-${ghostty_pid}.log"
  local manager_src="${GHOSTTY_ZMX_INSTALL_DIR:-$HOME/.config/ghostty-zmx}/session-manager.zsh"
  set -o noclobber
  { print '#!/bin/zsh' > "$script"; } 2>/dev/null || { set +o noclobber; return 0; }
  set +o noclobber
  cat >> "$script" <<'EOS'
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
GHOSTTY_ZMX_INTERNAL_POLLER=1 source "$manager_src" 2>/dev/null || exit 70

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
EOS
  chmod +x "$script" 2>/dev/null
  # Re-parent the poller to launchd AND detach its controlling tty via
  # os.setsid(). Detaching the tty is hygiene: it keeps the poller from
  # receiving terminal-driven signals (SIGHUP) if the originating surface
  # closes, so the poller dies only when its owning Ghostty PID exits (per
  # the elapsed-token loop above). macOS has no `setsid`, so use python3 to
  # call os.setsid() (new session, no controlling tty) before execing the
  # poller. Fall back to the nohup double-fork (re-parents to launchd but
  # does not detach the tty) if python3 is unavailable.
  if command -v python3 >/dev/null 2>&1; then
    # Detach the poller's controlling tty AND re-parent to launchd. zsh's
    # background job control puts the child in a new process group (making it
    # a pgrp leader, which blocks os.setsid() with EPERM). To get a non-leader
    # child, python3 forks first; the forked child is not a pgrp leader and
    # can call os.setsid() to create a new session with no controlling tty.
    python3 -c 'import os, sys
if os.fork() != 0:
    os._exit(0)
os.setsid()
os.execvp("/bin/zsh", ["/bin/zsh", sys.argv[1]] + sys.argv[2:])' "$script" "$ghostty_pid" "$flag" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$interval" "${GHOSTTY_ZMX_DEBUG:-0}" "$_ghostty_app_name" "${GHOSTTY_ZMX_INSTALL_DIR:-$HOME/.config/ghostty-zmx}" "$ghostty_elapsed" "${GHOSTTY_ZMX_SCROLLBACK_LINES:-1000}" "$manager_src" </dev/null >"$poller_log" 2>&1 &!
  else
    nohup /bin/zsh -c 'nohup "/bin/zsh" "$0" "$@" </dev/null >"'$poller_log'" 2>&1 & disown; exit' "$script" "$ghostty_pid" "$flag" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$interval" "${GHOSTTY_ZMX_DEBUG:-0}" "$_ghostty_app_name" "${GHOSTTY_ZMX_INSTALL_DIR:-$HOME/.config/ghostty-zmx}" "$ghostty_elapsed" "${GHOSTTY_ZMX_SCROLLBACK_LINES:-1000}" "$manager_src" </dev/null >/dev/null 2>&1 &!
  fi
}

# Pure decision function for the remote zmx probe. Takes (host, probe_out,
# probe_rc) and either:
#   - returns 0 and prints the parsed version on stdout (probe ok), or
#   - returns 1 and prints a user-facing error message on stdout (with leading
#     and trailing newlines so it renders on its own line in the pane).
#
# Extracted from the accept-line widget so the decision logic is unit-testable
# without a Ghostty/zle context. The widget calls this and, on failure, prints
# the message, clears BUFFER, and resets the prompt.
#
# probe_out encoding (from the remote `exit 0` probe command):
#   "zmx:<version line>"                         — legacy zmx present encoding
#   "zmx-path:<absolute path>\nzmx:<version line>" — zmx present + probed path
#   "no-zmx"                                      — zmx not on the remote PATH
#   "" (empty) + probe_rc!=0                      — ssh connection itself failed (host down/refused/auth)
ghostty_zmx_probe_result() {
  emulate -L zsh
  local host="$1" probe_out="$2" probe_rc="$3" version_value
  if [[ "$probe_rc" -ne 0 ]]; then
    print -P "\nghostty-zmx: could not reach $host (ssh exit $probe_rc). Is the host online and your ssh config/certs valid?\n"
    return 1
  fi
  if [[ "$probe_out" == "no-zmx" ]]; then
    print -P "\nghostty-zmx: remote host $host needs zmx 0.6.x on PATH; install zmx on $host and retry.\n"
    return 1
  fi
  # probe_out is either legacy "zmx:<version line>" or a multi-line payload
  # with "zmx-path:<absolute path>" plus "zmx:<version line>".
  version_value="$(print -r -- "$probe_out" | awk -F ':' '$1 == "zmx" { sub(/^zmx:/, ""); print; exit }' | awk '{print $2}')"
  if [[ "$version_value" != 0.6.* ]]; then
    print -P "\nghostty-zmx: remote host $host has zmx $version_value; ghostty-zmx needs zmx 0.6.x. Update zmx on $host and retry.\n"
    return 1
  fi
  print -r -- "$version_value"
  return 0
}

ghostty_zmx_probe_zmx_path() {
  emulate -L zsh
  local probe_out="$1" zmx_path
  zmx_path="$(print -r -- "$probe_out" | awk -F ':' '$1 == "zmx-path" { sub(/^zmx-path:/, ""); print; exit }')"
  if [[ "$zmx_path" =~ '^/[A-Za-z0-9._~+@%/=-]+$' ]]; then
    print -r -- "$zmx_path"
  else
    print -r -- ""
  fi
}

ghostty_zmx_accept_line() {
  emulate -L zsh
  setopt local_options no_sh_word_split
  local _gzmx_widget_log="${GHOSTTY_ZMX_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-zmx}/debug.log"
  local _gzmx_widget_debug() { [[ "${GHOSTTY_ZMX_DEBUG:-0}" == "1" ]] || return 0; mkdir -p "${_gzmx_widget_log:h}" 2>/dev/null; print -r -- "$(date -u '+%Y-%m-%dT%H:%M:%SZ') widget $*" >> "$_gzmx_widget_log"; }
  [[ -n "${BUFFER:-}" ]] || { zle .accept-line; return }
  [[ "${GHOSTTY_ZMX_AUTO_ATTACH:-}" == "1" && "${TERM_PROGRAM:-}" == "ghostty" && -n "${ZMX_SESSION:-}" ]] || { _gzmx_widget_debug "fallthrough reason=not-managed buffer=$BUFFER"; zle .accept-line; return }
  # Bisection kill switch: disable the widget interception entirely.
  [[ "${GHOSTTY_ZMX_DISABLE_WIDGET:-0}" != "1" ]] || { _gzmx_widget_debug "fallthrough reason=widget-disabled buffer=$BUFFER"; zle .accept-line; return }


  _gzmx_widget_debug "inspect buffer=$BUFFER"
  # Fail open on complex shell syntax. v0.2 intercepts only simple interactive ssh forms.
  if [[ "$BUFFER" == *[';|&<>`$()']* ]]; then
    _gzmx_widget_debug "fallthrough reason=complex-syntax buffer=$BUFFER"
    zle .accept-line
    return
  fi

  local original_buffer="$BUFFER"
  local -a words prefix projection
  words=(${(z)BUFFER})
  local transport="" start=0 host_index=0 host_target="" host_key="" expect_arg=0 saw_tty=0
  if [[ "${words[1]:-}" == "ssh" ]]; then
    transport="ssh"
    start=2
    prefix=(ssh)
  elif [[ "${words[1]:-}" == "tsh" && "${words[2]:-}" == "ssh" ]]; then
    transport="tsh"
    start=3
    prefix=(tsh ssh)
  else
    zle .accept-line
    return
  fi

  local i token
  for (( i=start; i<=${#words}; i++ )); do
    token="${words[$i]}"
    if (( expect_arg )); then
      expect_arg=0
      continue
    fi
    case "$token" in
      --)
        zle .accept-line
        return
        ;;
      -t|-tt|--tty)
        saw_tty=1
        continue
        ;;
      -l|-p|-J|-o|-i|-F|-S|-b|-c|-m|-W|-L|-R|-D|--login|--proxy|--user|--port|--identity)
        expect_arg=1
        continue
        ;;
      --login=*|--proxy=*|--user=*|--port=*|--identity=*)
        continue
        ;;
      -*)
        zle .accept-line
        return
        ;;
      *)
        host_index=$i
        host_target="$token"
        break
        ;;
    esac
  done

  [[ -n "$host_target" ]] || { zle .accept-line; return }
  # Extra words after the host mean a one-shot remote command. Do not hijack.
  (( host_index == ${#words} )) || { zle .accept-line; return }

  host_key="${host_target##*@}"
  [[ -n "$host_key" ]] || { zle .accept-line; return }

  # The widget intercepts the line instead of calling zle .accept-line, so zsh
  # would not add the typed ssh/tsh command to history. Explicitly push it so
  # Up-arrow and zsh-autosuggestions behave as if the user had executed it.
  # Unsupported/one-shot commands fall through to normal accept-line and are
  # recorded by zsh itself, so only do this for confirmed interactive handoffs.
  print -s -- "$original_buffer" 2>/dev/null || true

  local -a probe
  projection=(${words[@]})
  probe=(${words[@]})
  for (( i=${#probe}; i>=1; i-- )); do
    [[ "${probe[$i]}" == "-t" || "${probe[$i]}" == "-tt" || "${probe[$i]}" == "--tty" ]] && probe[$i]=()
  done
  if (( ! saw_tty )); then
    if [[ "$transport" == "ssh" ]]; then
      projection=(ssh -t ${words[@]:1})
    else
      projection=(tsh ssh -t ${words[@]:2})
    fi
  fi

  # Generate the remote logical ids + compact gzr- session name now.
  # Inline the /dev/urandom expression instead of defining an inner `rand()`
  # function: zsh function definitions are global (even inside `emulate -L`),
  # so a `rand` helper here would clobber (and be clobbered by) any user
  # plugin that also defines `rand`. If a plugin's `rand` returned non-hex,
  # the resulting `gzr-*` session name would silently violate the server-side
  # session-name validation and the projection open would fail with no
  # clear error. Inlining removes the collision surface.
  local workspace window tab pane session _gzmx_rand
  _gzmx_rand="$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d '[:space:]')"
  workspace="${_gzmx_rand[1,8]}"
  _gzmx_rand="$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d '[:space:]')"
  window="${_gzmx_rand[1,8]}"
  _gzmx_rand="$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d '[:space:]')"
  tab="${_gzmx_rand[1,6]}"
  _gzmx_rand="$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d '[:space:]')"
  pane="${_gzmx_rand[1,6]}"
  session="gzr-${workspace}-${window}-${tab}-${pane}"

  local prefix_string="${(j: :)projection}"
  mkdir -p "$GHOSTTY_ZMX_DATA_HOME" 2>/dev/null

  # The widget opens the projection window; the ghostty-zmx wrapper (the
  # surface command) writes the remote-layout `state=present` row when it
  # starts, then execs ssh. This split keeps osascript `new window` in the
  # surface-shell (zle) context and the remote-layout write in the surface's
  # own command tree. (An earlier revision feared a `state=present` row
  # triggered a Ghostty tip-build multiplication bug; that was disproven —
  # the cause was surviving orphaned poller shells. See changelog
  # 2026-07-01-v0-2-multiplication-root-cause-orphaned-poller-shells.)
  local -a probe_argv=()
  local _have_t=0 _w _is_tsh=0
  if [[ "${projection[1]}" == "tsh" && "${projection[2]:-}" == "ssh" ]]; then
    _is_tsh=1
  fi
  for _w in "${projection[@]}"; do
    case "$_w" in
      -t|-tt|--tty) ;;
      -T) [[ "$_is_tsh" -eq 0 ]] && { probe_argv+=(-T); _have_t=1 } ;;
      *) probe_argv+=("$_w") ;;
    esac
  done
  [[ "$_is_tsh" -eq 1 || "$_have_t" -eq 1 ]] || probe_argv+=(-T)
  _gzmx_widget_debug "widget probe host=$host_key session=$session argv=${probe_argv[*]}"
  local probe_out probe_rc probe_msg version_value zmx_path
  # Source .zshrc so zmx is found even when it's only on the interactive PATH
  # (some users add ~/.local/bin to PATH in .zshrc, which is not sourced for
  # non-interactive `ssh -T host 'cmd'`). The projection itself runs with -t
  # (interactive) so .zshrc is sourced and zmx is on PATH there.
  #
  # The remote probe always `exit 0`s when the ssh connection itself succeeds,
  # so a non-zero rc unambiguously means the connection failed (host down,
  # refused, auth/cert failure) — not a zmx problem. zmx availability is
  # encoded in the stdout line ("zmx:<version>" or "no-zmx"), so we can tell
  # "host reachable but zmx missing" apart from "host unreachable".
  #
  # `ssh -T` writes its diagnostics to stderr; suppress it so it does not
  # clutter the pane.
  probe_out="$("${probe_argv[@]}" 'source ~/.zshrc 2>/dev/null; if zmx_path=$(command -v zmx 2>/dev/null); then printf "zmx-path:%s\nzmx:%s\n" "$zmx_path" "$($zmx_path version | head -1)"; else echo no-zmx; fi; exit 0' 2>/dev/null)"
  probe_rc=$?
  probe_msg="$(ghostty_zmx_probe_result "$host_key" "$probe_out" "$probe_rc")"
  if [[ $? -ne 0 ]]; then
    print -r -- "$probe_msg"
    BUFFER=""
    zle reset-prompt
    return
  fi
  version_value="$probe_msg"
  zmx_path="$(ghostty_zmx_probe_zmx_path "$probe_out")"
  _gzmx_widget_debug "widget probe-ok host=$host_key version=$version_value zmx_path=${zmx_path:-zmx}"

  # Open the projection window from THIS surface-shell (zle) context. The
  # ghostty-zmx wrapper (the surface's own command) writes the remote-layout
  # `state=present` row when it starts; the widget does not write the layout
  # row. See changelog
  # 2026-07-01-v0-2-multiplication-root-cause-orphaned-poller-shells.
  local command_string applescript_command
  command_string="$(ghostty_zmx_projection_command_string "$host_key" "$workspace" "$session" "$prefix_string" "$zmx_path")"
  applescript_command="${command_string//\\\\/\\\\\\\\}"
  applescript_command="${applescript_command//\"/\\\"}"
  _gzmx_widget_debug "widget opening host=$host_key session=$session cmd=$command_string"
  osascript <<OSA 2>/dev/null || true
tell application "$_ghostty_app_name"
  set cfg to new surface configuration
  set command of cfg to "$applescript_command"
  set w to new window with configuration cfg
  activate window w
end tell
OSA
  _gzmx_widget_debug "widget opened host=$host_key session=$session"

  # Write a local `opening` projection row under the per-host+session lock so
  # the poller knows a projection is in flight for this session and does not
  # open a duplicate. The poller upgrades it to `attached` once it scans the
  # live Ghostty terminal. (The wrapper writes the server remote-layout
  # `state=present` row when it starts; this local row is the client-side
  # projection ledger.)
  local _wl _wacq=0 _wi
  _wl="$(ghostty_zmx_projection_lock_path "$host_key" "$session")" 2>/dev/null || _wl=""
  if [[ -n "$_wl" ]]; then
    mkdir -p "${_wl:h}" 2>/dev/null
    for (( _wi=1; _wi<=50; _wi++ )); do
      mkdir "$_wl" 2>/dev/null && { _wacq=1; break; }
      sleep 0.02
    done
    [[ "$_wacq" -eq 1 ]] && ghostty_zmx_write_projection_row "$host_key" "$workspace" "$session" "-" "-" opening "-" "-" 2>/dev/null
    rmdir "$_wl" 2>/dev/null || true
  fi

  # The remote-layout `add` is NOT done here: the projection wrapper writes
  # the `state=present` row when it starts (the wrapper is the surface's own
  # command tree). The widget only records host metadata here and starts the
  # poller. See changelog
  # 2026-07-01-v0-2-multiplication-root-cause-orphaned-poller-shells.
  { awk -F '\t' -v h="$host_key" '$1 != h { print }' "$GHOSTTY_ZMX_DATA_HOME/remote-hosts" 2>/dev/null || true
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$host_key" "$transport" "$version_value" active "$prefix_string" "$zmx_path"
  } > "$GHOSTTY_ZMX_DATA_HOME/remote-hosts.tmp.$$" 2>/dev/null && mv "$GHOSTTY_ZMX_DATA_HOME/remote-hosts.tmp.$$" "$GHOSTTY_ZMX_DATA_HOME/remote-hosts" 2>/dev/null

  # Start the poller (detached) so server-side layout changes (new present
  # rows from other clients, closing/deleted from another client) are
  # reflected locally. The poller reads the server remote-layout over ssh
  # (bare-word helper argv), reconciles local projections (adopt/open/remove),
  # and is PID-reuse-safe (elapsed-seconds token). See changelog
  # 2026-07-01-v0-2-multiplication-root-cause-orphaned-poller-shells.
  [[ "${GHOSTTY_ZMX_DISABLE_POLLER:-0}" != "1" ]] && ghostty_zmx_start_remote_poller force
  print -P "\nghostty-zmx: opened remote $host_key ($session)\n"
  BUFFER=""
  zle reset-prompt
}


_ghostty_zmx_install_accept_line_widget() {
  [[ -o interactive ]] || return 0
  [[ "${TERM_PROGRAM:-}" == "ghostty" ]] || return 0
  [[ "${GHOSTTY_ZMX_AUTO_ATTACH:-}" == "1" ]] || return 0
  zle -N ghostty_zmx_accept_line 2>/dev/null || return 0
  bindkey '^M' ghostty_zmx_accept_line 2>/dev/null || true
  bindkey '^J' ghostty_zmx_accept_line 2>/dev/null || true
}

_ghostty_zmx_auto_attach() {
  if [[ ! -o interactive ]]; then
    _ghostty_zmx_debug "auto-attach skipped reason=non-interactive"
    return 0
  fi
  if [[ "${GHOSTTY_ZMX_AUTO_ATTACH:-}" != "1" ]]; then
    _ghostty_zmx_debug "auto-attach skipped reason=disabled value=${GHOSTTY_ZMX_AUTO_ATTACH:-}"
    return 0
  fi
  # Never auto-attach inside a projection surface. The ghostty-zmx wrapper sets
  # GHOSTTY_ZMX_PROJECTION=1; if .zprofile sources this manager inside a
  # projection pane (Ghostty runs `command` via `login -c "exec -l ..."`, which
  # sources .zprofile), auto-attach would attach to a LOCAL zmx session
  # instead of letting the wrapper exec the transport ssh.
  if [[ "${GHOSTTY_ZMX_PROJECTION:-}" == "1" ]]; then
    _ghostty_zmx_debug "auto-attach skipped reason=projection-surface"
    return 0
  fi
  if [[ -n "$ZMX_SESSION" || -n "$TMUX" ]]; then
    _ghostty_zmx_debug "auto-attach skipped reason=nested zmx=${ZMX_SESSION:-0} tmux=${TMUX:-0}"
    return 0
  fi
  if ! command -v zmx >/dev/null 2>&1; then
    _ghostty_zmx_debug "auto-attach skipped reason=zmx-missing"
    return 0
  fi

  typeset -i asReady=0
  typeset -i attempt=0
  typeset ghosttyPID=""
  for attempt in $(seq 1 $_ghostty_zmx_ghostty_ready_attempts); do
    typeset p=$$
    while [[ $p -gt 1 ]]; do
      typeset cmd=$(ps -o comm= -p $p 2>/dev/null)
      if [[ "${cmd:l}" == *ghostty* ]]; then
        ghosttyPID=$p
        break
      fi
      p=$(ps -o ppid= -p $p 2>/dev/null | tr -d ' ')
    done
    if [[ -n "$ghosttyPID" ]] && osascript -e "tell application \"$_ghostty_app_name\" to get version" >/dev/null 2>&1; then
      _ghostty_zmx_debug "Ghostty PID detected ghostty_pid=$ghosttyPID attempt=$attempt"
      asReady=1
      break
    fi
    ghosttyPID=""
    sleep "$_ghostty_zmx_ghostty_ready_delay"
  done
  [[ "$asReady" -eq 0 ]] && { _ghostty_zmx_debug "Ghostty PID detection failed"; return 0; }

  # Native split/tab inheritance: if this surface was created by splitting
  # a remote-projection window, exec into a new projection for the same host.
  # If session-manager-early.zsh already ran from .zprofile, it made this
  # decision before .zshrc and we must not repeat it here (doing so would
  # reintroduce the late .zshrc inherit path and its terminal-query leakage).
  if [[ "${GHOSTTY_ZMX_EARLY_INHERIT_RAN:-0}" != "1" ]]; then
    # The new split terminal's AppleScript registration can lag shell init by a
    # few hundred ms, so retry the identity lookup a few times before falling
    # through to local auto-attach.
    typeset earlySurfaceIdentity=""
    typeset _inh_attempt
    for (( _inh_attempt=1; _inh_attempt<=8; _inh_attempt++ )); do
      earlySurfaceIdentity="$(_ghostty_zmx_current_surface_identity)"
      if [[ -n "$earlySurfaceIdentity" ]]; then
        break
      fi
      _ghostty_zmx_debug "auto-attach pre-inherit identity-not-ready attempt=$_inh_attempt"
      sleep 0.25
    done
    _ghostty_zmx_debug "auto-attach pre-inherit attempt=$_inh_attempt"
    if [[ -n "$earlySurfaceIdentity" ]] && ghostty_zmx_inherit_remote_context_if_any "$earlySurfaceIdentity"; then
      return 0
    fi
  else
    _ghostty_zmx_debug "auto-attach pre-inherit skipped reason=early-inherit-ran"
  fi

  typeset restoreFlag="$(_ghostty_zmx_runtime_path "restore-${ghosttyPID}.lock")"
  typeset restoreAttemptedFlag="$(_ghostty_zmx_runtime_path "restore-attempted-${ghosttyPID}.done")"
  typeset restoreProcessToken="$(_ghostty_zmx_ghostty_process_token "$ghosttyPID")"
  typeset restoreDriver=0
  typeset sessionName=""
  typeset sessionFromRestore=0
  if [[ -n "$ghosttyPID" && -n "$restoreFlag" && -n "$restoreAttemptedFlag" && -f "$restoreAttemptedFlag" ]]; then
    _ghostty_zmx_debug "restore-driver skipped reason=already-attempted ghostty_pid=$ghosttyPID flag=$restoreAttemptedFlag"
  elif [[ -n "$ghosttyPID" && -n "$restoreFlag" ]] && mkdir "$restoreFlag" 2>/dev/null; then
    restoreDriver=1
    _ghostty_zmx_mark_restore_attempted "$restoreAttemptedFlag" "$restoreProcessToken"
    _ghostty_zmx_debug "restore-driver elected ghostty_pid=$ghosttyPID flag=$restoreFlag"
    _ghostty_zmx_restore
    _ghostty_zmx_debug "restore-driver post-restore"
    typeset firstFile="$GHOSTTY_ZMX_DATA_HOME/restore-first"
    if [[ -s "$firstFile" ]]; then
      IFS= read -r sessionName < "$firstFile"
      rm -f "$firstFile" 2>/dev/null
      if _ghostty_zmx_valid_session_name "$sessionName"; then
        sessionFromRestore=1
      else
        _ghostty_zmx_debug "invalid session skipped action=restore-first session=$sessionName"
        sessionName=""
      fi
    fi
  fi
  if [[ "$restoreDriver" -eq 1 ]]; then
    rmdir "$restoreFlag" 2>/dev/null
    _ghostty_zmx_debug "restore-driver released ghostty_pid=$ghosttyPID flag=$restoreFlag"
  fi

  if [[ -z "$sessionName" && "$restoreDriver" -eq 0 ]]; then
    sessionName=$(_ghostty_zmx_wait_restore_assignment "$ghosttyPID" "$restoreFlag")
    if [[ -n "$sessionName" ]]; then
      sessionFromRestore=1
    elif _ghostty_zmx_restore_active "$ghosttyPID" "$restoreFlag"; then
      _ghostty_zmx_debug "auto-attach skipped reason=restore-unassigned ghostty_pid=$ghosttyPID"
      return 0
    fi
  fi

  typeset position=$(_ghostty_zmx_current_position)
  _ghostty_zmx_debug "current position result=${position:-missing}"
  if [[ -z "$sessionName" && -n "$position" ]]; then
    position=$(_ghostty_zmx_apply_position_map "$position")
    typeset winHash=$(print -r -- "$position" | awk '{print $1}')
    typeset tabHash=$(print -r -- "$position" | awk '{print $2}')
    typeset termId=$(print -r -- "$position" | awk '{print $3}')
    sessionName="zmx-${winHash}-${tabHash}-${termId}"
    _ghostty_zmx_debug "session generated session=$sessionName position=$position"
    _ghostty_zmx_valid_session_name "$sessionName" || { _ghostty_zmx_debug "invalid session skipped action=generated session=$sessionName"; sessionName=""; }
  fi

  if [[ -z "$sessionName" ]]; then
    _ghostty_zmx_debug "auto-attach skipped reason=no-session"
    return 0
  fi

  if [[ -n "$sessionName" ]]; then
    typeset surfaceIdentity="$(_ghostty_zmx_current_surface_identity)"
    if [[ "$sessionFromRestore" -eq 0 ]]; then
      sessionName="$(_ghostty_zmx_reserve_session_name "$sessionName")" || { _ghostty_zmx_debug "auto-attach skipped reason=reserve-failed"; return 0; }
      _ghostty_zmx_record_position_map "$sessionName" "$(_ghostty_zmx_current_position)"
    else
      _ghostty_zmx_log_session "$sessionName"
    fi
    _ghostty_zmx_record_tty_map "$sessionName" "$surfaceIdentity" || _ghostty_zmx_debug "tty-map write failed session=$sessionName"
    [[ "${GHOSTTY_ZMX_DISABLE_REAPER:-0}" != "1" ]] && _ghostty_zmx_start_reaper "$ghosttyPID"
    _ghostty_zmx_restore_saved_scrollback "$sessionName"
    _ghostty_zmx_debug "attach session=$sessionName from_restore=$sessionFromRestore"
    typeset attachStatus=0 ttyPath="$(print -r -- "$surfaceIdentity" | awk '{print $5}')"
    zmx attach "$sessionName" || attachStatus=$?
    [[ "$attachStatus" -ne 0 ]] && _ghostty_zmx_debug "zmx attach failed session=$sessionName status=$attachStatus"
    _ghostty_zmx_cleanup_closed_surface "$sessionName" "$ttyPath"
  fi
}

# When sourced by the standalone remote poller (GHOSTTY_ZMX_INTERNAL_POLLER=1),
# define all functions then return: no widget install, no auto-attach, no
# nested poller start, no unfunction. The poller script drives the loop itself.
if [[ "${GHOSTTY_ZMX_INTERNAL_POLLER:-0}" == "1" ]]; then
  return 0
fi

_ghostty_zmx_install_accept_line_widget
# E2E harness hook: if the harness wrote a PATH snippet into the data home,
# source it here (after the user's .zshrc PATH manipulations) so the widget
# finds the mock tsh. No-op in production (the file does not exist).
[[ -r "${GHOSTTY_ZMX_DATA_HOME:-$HOME/.local/share/ghostty-zmx}/e2e-path.zsh" ]] && \
  source "${GHOSTTY_ZMX_DATA_HOME:-$HOME/.local/share/ghostty-zmx}/e2e-path.zsh"
# Always self-heal orphaned pollers on shell init, even when no remote-hosts
# file exists yet. Leftover poller scripts from crashed/killed Ghostty
# instances survive `pkill -f Ghostty-tip` (reparented to launchd) and
# independently poll the server layout, re-opening projections. Killing
# them here on every new shell prevents accumulation. Only run when inside
# a Ghostty surface and a Ghostty PID can be detected.
if [[ "${GHOSTTY_ZMX_DISABLE_POLLER:-0}" != "1" && "${TERM_PROGRAM:-}" == "ghostty" ]]; then
  typeset _gzmx_self_pid="$(ghostty_zmx_detect_ghostty_pid 2>/dev/null)" && [[ -n "$_gzmx_self_pid" ]] && ghostty_zmx_kill_orphaned_pollers "$_gzmx_self_pid" 2>/dev/null
fi
[[ "${GHOSTTY_ZMX_DISABLE_POLLER:-0}" != "1" ]] && [[ -f "$(ghostty_zmx_remote_hosts_file 2>/dev/null)" ]] && ghostty_zmx_start_remote_poller
_ghostty_zmx_auto_attach
# v0.2: do NOT unfunction the _ghostty_zmx_* private helpers. The remote
# projection functions (reconcile, poller, projection lock/state) are invoked
# after init by the accept-line widget and the standalone poller, and they depend
# on private helpers such as _ghostty_zmx_runtime_dir and _ghostty_zmx_debug.
# Removing the helpers would break those call sites with "command not found".
# GHOSTTY_ZMX_KEEP_HELPERS is retained for compatibility but now a no-op.
