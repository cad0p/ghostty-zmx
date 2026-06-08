# ghostty-zmx session manager for zsh.
# Source this file from an interactive zsh launched by Ghostty.

: ${GHOSTTY_ZMX_DATA_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx}
: ${GHOSTTY_ZMX_STATE_HOME:=${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-zmx}
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
_ghostty_zmx_restore_flag_cleanup_delay=5

_ghostty_zmx_valid_session_name() {
  typeset session="$1"
  [[ "$session" =~ '^zmx-[[:alnum:]]+-[[:alnum:]]+-[[:alnum:]]{8}$' ]]
}

_ghostty_zmx_session_history_file() {
  typeset session="$1"
  _ghostty_zmx_valid_session_name "$session" || return 1
  print -r -- "$GHOSTTY_ZMX_STATE_HOME/history/${session}.txt"
}

_ghostty_zmx_runtime_dir() {
  typeset root="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
  typeset dir="$root/ghostty-zmx-${UID:-$(id -u)}"
  if [[ -e "$dir" && ! -d "$dir" ]]; then
    _ghostty_zmx_debug "runtime dir unsafe path=$dir"
    return 1
  fi
  umask 077
  mkdir -p "$dir" 2>/dev/null || return 1
  chmod 700 "$dir" 2>/dev/null || return 1
  if command -v stat >/dev/null 2>&1; then
    typeset owner="$(stat -f %u "$dir" 2>/dev/null || stat -c %u "$dir" 2>/dev/null)"
    [[ -z "$owner" || "$owner" == "${UID:-$(id -u)}" ]] || return 1
  fi
  print -r -- "$dir"
}

_ghostty_zmx_runtime_path() {
  typeset name="$1"
  [[ "$name" =~ '^[A-Za-z0-9._-]+$' ]] || return 1
  typeset dir="$(_ghostty_zmx_runtime_dir)" || return 1
  print -r -- "$dir/$name"
}

_ghostty_zmx_debug() {
  [[ "${GHOSTTY_ZMX_DEBUG:-0}" == "1" ]] || return 0
  mkdir -p "$GHOSTTY_ZMX_STATE_HOME" 2>/dev/null
  print -r -- "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*" >> "$GHOSTTY_ZMX_STATE_HOME/debug.log"
}

_ghostty_zmx_debug "shell init data_home=$GHOSTTY_ZMX_DATA_HOME state_home=$GHOSTTY_ZMX_STATE_HOME"

_ghostty_zmx_sessions_file() {
  print -r -- "$GHOSTTY_ZMX_DATA_HOME/sessions"
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

_ghostty_zmx_unlog_session() {
  typeset session="$1"
  if ! _ghostty_zmx_valid_session_name "$session"; then
    _ghostty_zmx_debug "invalid session skipped action=unlog session=$session"
    return 1
  fi
  typeset log="$(_ghostty_zmx_sessions_file)"
  [[ -f "$log" ]] || return 0
  grep -vxF "$session" "$log" > "${log}.tmp" 2>/dev/null || true
  mv "${log}.tmp" "$log" 2>/dev/null
  _ghostty_zmx_debug "session unlogged session=$session file=$log"
}

_ghostty_zmx_cleanup_after_detach() {
  return 0
}

_ghostty_zmx_snapshot_history() {
  typeset session="$1"
  if ! _ghostty_zmx_valid_session_name "$session"; then
    _ghostty_zmx_debug "invalid session skipped action=snapshot session=$session"
    return 1
  fi
  mkdir -p "$GHOSTTY_ZMX_STATE_HOME/history" 2>/dev/null
  typeset history_file="$(_ghostty_zmx_session_history_file "$session")" || return 1
  if zmx history "$session" 2>/dev/null | tail -n "$GHOSTTY_ZMX_SCROLLBACK_LINES" > "${history_file}.tmp"; then
    mv "${history_file}.tmp" "$history_file"
    _ghostty_zmx_debug "scrollback snapshot session=$session file=$history_file lines=$GHOSTTY_ZMX_SCROLLBACK_LINES"
  else
    rm -f "${history_file}.tmp" 2>/dev/null
    _ghostty_zmx_debug "scrollback snapshot failed session=$session"
  fi
}

_ghostty_zmx_restore_saved_scrollback() {
  typeset session="$1"
  if ! _ghostty_zmx_valid_session_name "$session"; then
    _ghostty_zmx_debug "invalid session skipped action=restore-scrollback session=$session"
    return 1
  fi
  typeset history_file="$(_ghostty_zmx_session_history_file "$session")" || return 1
  if zmx list --short 2>/dev/null | grep -qxF "$session"; then
    _ghostty_zmx_debug "fresh-session detection session=$session exists=1"
    return 0
  fi
  _ghostty_zmx_debug "fresh-session detection session=$session exists=0 snapshot=$history_file"
  [[ -s "$history_file" ]] || return 0
  if ! zmx run "$session" true >/dev/null 2>&1; then
    _ghostty_zmx_debug "zmx run failed session=$session"
  fi
  typeset banner='[ghostty-zmx restored saved scrollback from a previous boot; process state was not restored]'
  if ! { print -r -- "$banner"; cat "$history_file"; } | zmx print "$session"; then
    _ghostty_zmx_debug "zmx print failed session=$session file=$history_file"
  else
    _ghostty_zmx_debug "zmx print restored scrollback session=$session file=$history_file"
  fi
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
log="$dataHome/sessions"
queue="$dataHome/restore-queue"
firstFile="$dataHome/restore-first"
restoring="$runtimeDir/restoring-${ghosttyPID}.lock"

valid_session_name() {
  local session="$1"
  [[ "$session" =~ '^zmx-[[:alnum:]]+-[[:alnum:]]+-[[:alnum:]]{8}$' ]]
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

debug_log "started ghostty_pid=$ghosttyPID sessions_file=$log"

cleanup_log() {
  local session="$1"
  if ! valid_session_name "$session"; then
    debug_log "invalid session skipped action=cleanup-log session=$session"
    return 1
  fi
  [[ -f "$log" ]] || return 0
  grep -vxF "$session" "$log" > "${log}.tmp" 2>/dev/null || true
  mv "${log}.tmp" "$log" 2>/dev/null
}

snapshot_history() {
  local session="$1"
  if ! valid_session_name "$session"; then
    debug_log "invalid session skipped action=snapshot session=$session"
    return 1
  fi
  mkdir -p "$stateHome/history" 2>/dev/null
  local historyFile="$(history_file_for_session "$session")" || return 1
  if zmx history "$session" 2>/dev/null | tail -n "$scrollbackLines" > "${historyFile}.tmp"; then
    mv "${historyFile}.tmp" "$historyFile"
    debug_log "scrollback snapshot session=$session file=$historyFile lines=$scrollbackLines"
  else
    rm -f "${historyFile}.tmp" 2>/dev/null
    debug_log "scrollback snapshot failed session=$session"
  fi
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

managed_detached_sessions() {
  [[ -f "$log" ]] || return 0
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

sleep "$reaperStartupDelay"
zeroWindowsSeen=0
while kill -0 "$ghosttyPID" 2>/dev/null; do
  windows=$(osascript -e 'tell application "Ghostty" to count of windows' 2>/dev/null)
  [[ "$windows" =~ '^[0-9]+$' ]] || break

  if [[ "$windows" -eq 0 ]]; then
    zeroWindowsSeen=$((zeroWindowsSeen + interval))
    if [[ "$zeroWindowsSeen" -ge "$zeroWindowGrace" ]]; then
      managed_detached_sessions | while IFS= read -r orphan; do
        snapshot_history "$orphan"
        debug_log "zero-window cleanup session=$orphan"
        zmx kill "$orphan" >/dev/null 2>&1
        cleanup_log "$orphan"
        forget_snapshot "$orphan"
      done
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
  if [[ -f "$log" ]]; then
    while IFS= read -r managed; do
      [[ -n "$managed" ]] || continue
      if ! valid_session_name "$managed"; then
        debug_log "invalid session skipped action=attached-count session=$managed"
        continue
      fi
      clients=$(zmx list 2>/dev/null | awk -F '\t' -v name="$managed" '$1 ~ "name="name"$" { sub(/^clients=/, "", $3); print $3; exit }')
      [[ "$clients" == "1" ]] && attached=$((attached + 1))
    done < "$log"
  fi
  if [[ "$attached" -eq 0 ]]; then
    managed_detached_sessions | while IFS= read -r preserved; do
      snapshot_history "$preserved"
      debug_log "preserving detached session=$preserved"
    done
    sleep "$interval"
    continue
  fi

  managed_detached_sessions | while IFS= read -r orphan; do
    snapshot_history "$orphan"
    debug_log "detached cleanup session=$orphan attached_managed=$attached"
    zmx kill "$orphan" >/dev/null 2>&1
    cleanup_log "$orphan"
    forget_snapshot "$orphan"
  done
  sleep "$interval"
done
debug_log "stopped ghostty_pid=$ghosttyPID"
rmdir "$flag" 2>/dev/null
rm -f "$0" 2>/dev/null
EOS
  chmod +x "$script" 2>/dev/null
  nohup /bin/zsh "$script" "$ghosttyPID" "$flag" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_REAPER_INTERVAL" "$GHOSTTY_ZMX_ZERO_WINDOWS_GRACE" "$GHOSTTY_ZMX_STATE_HOME" "${GHOSTTY_ZMX_DEBUG:-0}" "$GHOSTTY_ZMX_SCROLLBACK_LINES" "$_ghostty_zmx_reaper_startup_delay" "$runtime_dir" >"$reaper_log" 2>&1 </dev/null &!
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

_ghostty_zmx_current_position() {
  osascript <<'EOF' 2>/dev/null
tell application "Ghostty"
  set fw to front window
  set winUID to id of fw
  set uidStr to winUID as string
  set uidLen to count of characters of uidStr
  if uidLen > 10 then
    set winHash to text 11 thru uidLen of uidStr
  else
    set winHash to uidStr
  end if
  set tabObj to selected tab of fw
  set tabUID to id of tabObj
  set tabStr to tabUID as string
  set tabLen to count of characters of tabStr
  if tabLen > 4 then
    set tabHash to text 5 thru tabLen of tabStr
  else
    set tabHash to tabStr
  end if
  set termUID to id of (focused terminal of tabObj)
  set termStr to termUID as string
  set termLen to count of characters of termStr
  if termLen >= 8 then
    set termHash to text 1 thru 8 of termStr
  else
    set termHash to termStr
  end if
  return winHash & " " & tabHash & " " & termHash
end tell
EOF
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
    if [[ -z "${_seen[$key]}" ]]; then
      _seen[$key]=1
      _keys+=("$key")
      _tabPanes[$key]=0
      _tabSessions[$key]=""
      if [[ -z "${_seenWin[$winHex]}" ]]; then
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
  : > "$queue"
  typeset i
  for ((i=2; i<=${#_layoutSessions}; i++)); do
    print -r -- "${_layoutSessions[$i]}" >> "$queue"
    _ghostty_zmx_debug "queue push session=${_layoutSessions[$i]} queue=$queue"
  done

  typeset curWin="" curTab="" firstWindow=1 physWin="" physTab=""
  typeset paneCount
  for key in "${_keys[@]}"; do
    winHex="${key%%:*}"
    tabHex="${key#*:}"
    paneCount="${_tabPanes[$key]}"

    if [[ "$winHex" != "$curWin" ]]; then
      if [[ $firstWindow -eq 1 ]]; then
        firstWindow=0
        typeset pos=$(_ghostty_zmx_current_position)
        physWin=$(print -r -- "$pos" | awk '{print $1}')
        physTab=$(print -r -- "$pos" | awk '{print $2}')
        _ghostty_zmx_write_id_map "$winHex" "$tabHex" "$physWin" "$physTab"
      else
        typeset created=$(osascript <<'SCRIPT' 2>/dev/null
tell application "Ghostty"
    set cfg to new surface configuration
    set w to new window with configuration cfg
    set tb to selected tab of w
    set winStr to id of w as string
    set tabStr to id of tb as string
    return (text 11 thru (count of characters of winStr) of winStr) & " " & (text 5 thru (count of characters of tabStr) of tabStr)
end tell
SCRIPT
)
        physWin=$(print -r -- "$created" | awk '{print $1}')
        physTab=$(print -r -- "$created" | awk '{print $2}')
        _ghostty_zmx_write_id_map "$winHex" "$tabHex" "$physWin" "$physTab"
        _ghostty_zmx_debug "AppleScript new-window logical_window=$winHex logical_tab=$tabHex physical_window=$physWin physical_tab=$physTab delay=$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
        sleep "$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
      fi
      curWin="$winHex"
      curTab=""
    fi

    if [[ "$tabHex" != "$curTab" ]]; then
      if [[ -n "$curTab" ]]; then
        typeset created=$(osascript <<'SCRIPT' 2>/dev/null
tell application "Ghostty"
    set cfg to new surface configuration
    set tb to new tab in front window with configuration cfg
    set w to front window
    set winStr to id of w as string
    set tabStr to id of tb as string
    return (text 11 thru (count of characters of winStr) of winStr) & " " & (text 5 thru (count of characters of tabStr) of tabStr)
end tell
SCRIPT
)
        physWin=$(print -r -- "$created" | awk '{print $1}')
        physTab=$(print -r -- "$created" | awk '{print $2}')
        _ghostty_zmx_write_id_map "$winHex" "$tabHex" "$physWin" "$physTab"
        _ghostty_zmx_debug "AppleScript new-tab logical_window=$winHex logical_tab=$tabHex physical_window=$physWin physical_tab=$physTab delay=$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
        sleep "$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
      fi
      curTab="$tabHex"
    fi

    typeset p
    for ((p=2; p<=paneCount; p++)); do
      typeset d="right"
      [[ $((p % 2)) -eq 0 ]] && d="down"
      osascript >/dev/null 2>&1 <<SCRIPT
tell application "Ghostty"
    set cfg to new surface configuration
    set t to focused terminal of selected tab of front window
    split t direction ${d} with configuration cfg
end tell
SCRIPT
      _ghostty_zmx_debug "AppleScript split logical_window=$winHex logical_tab=$tabHex pane_index=$p direction=$d delay=$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
      sleep "$GHOSTTY_ZMX_RESTORE_STEP_DELAY"
    done
  done
  if [[ -n "$ghosttyPID" && -n "$runtime_dir" ]]; then
    ( sleep "$_ghostty_zmx_restore_flag_cleanup_delay"; rmdir "$runtime_dir/restoring-${ghosttyPID}.lock" 2>/dev/null ) &!
    _ghostty_zmx_debug "restore flag cleanup scheduled ghostty_pid=$ghosttyPID"
  fi
  return 0
}

if [[ -o interactive ]] \
   && [[ "${GHOSTTY_ZMX_AUTO_ATTACH:-}" == "1" ]] \
   && [[ -z "$ZMX_SESSION" ]] \
   && [[ -z "$TMUX" ]] \
   && command -v zmx >/dev/null 2>&1; then

  typeset -i asReady=0
  typeset -i attempt=0
  typeset ghosttyPID=""
  for attempt in $(seq 1 $_ghostty_zmx_ghostty_ready_attempts); do
    typeset p=$$
    while [[ $p -gt 1 ]]; do
      typeset cmd=$(ps -o comm= -p $p 2>/dev/null)
      if [[ "$cmd" == *ghostty* ]]; then
        ghosttyPID=$p
        break
      fi
      p=$(ps -o ppid= -p $p 2>/dev/null | tr -d ' ')
    done
    if [[ -n "$ghosttyPID" ]] && osascript -e 'tell application "Ghostty" to get version' >/dev/null 2>&1; then
      _ghostty_zmx_debug "Ghostty PID detected ghostty_pid=$ghosttyPID attempt=$attempt"
      asReady=1
      break
    fi
    ghosttyPID=""
    sleep "$_ghostty_zmx_ghostty_ready_delay"
  done
  [[ "$asReady" -eq 0 ]] && { _ghostty_zmx_debug "Ghostty PID detection failed"; return 0; }

  typeset restoreFlag="$(_ghostty_zmx_runtime_path "restore-${ghosttyPID}.lock")"
  typeset SESSION_NAME=""
  typeset sessionFromRestore=0
  if [[ -n "$ghosttyPID" && -n "$restoreFlag" ]] && mkdir "$restoreFlag" 2>/dev/null; then
    _ghostty_zmx_debug "restore-driver elected ghostty_pid=$ghosttyPID flag=$restoreFlag"
    _ghostty_zmx_restore
    typeset firstFile="$GHOSTTY_ZMX_DATA_HOME/restore-first"
    if [[ -s "$firstFile" ]]; then
      IFS= read -r SESSION_NAME < "$firstFile"
      rm -f "$firstFile" 2>/dev/null
      if _ghostty_zmx_valid_session_name "$SESSION_NAME"; then
        sessionFromRestore=1
      else
        _ghostty_zmx_debug "invalid session skipped action=restore-first session=$SESSION_NAME"
        SESSION_NAME=""
      fi
    fi
  fi

  if [[ -z "$SESSION_NAME" ]]; then
    SESSION_NAME=$(_ghostty_zmx_pop_restore_queue)
    [[ -n "$SESSION_NAME" ]] && sessionFromRestore=1
  fi

  typeset POSITION=$(_ghostty_zmx_current_position)
  if [[ -z "$SESSION_NAME" && -n "$POSITION" ]]; then
    POSITION=$(_ghostty_zmx_apply_position_map "$POSITION")
    typeset WIN_HASH=$(print -r -- "$POSITION" | awk '{print $1}')
    typeset TAB_HASH=$(print -r -- "$POSITION" | awk '{print $2}')
    typeset TERM_ID=$(print -r -- "$POSITION" | awk '{print $3}')
    SESSION_NAME="zmx-${WIN_HASH}-${TAB_HASH}-${TERM_ID}"
    _ghostty_zmx_valid_session_name "$SESSION_NAME" || { _ghostty_zmx_debug "invalid session skipped action=generated session=$SESSION_NAME"; SESSION_NAME=""; }
  fi

  if [[ -n "$SESSION_NAME" ]]; then
    [[ "$sessionFromRestore" -eq 0 ]] && _ghostty_zmx_record_position_map "$SESSION_NAME" "$(_ghostty_zmx_current_position)"
    _ghostty_zmx_log_session "$SESSION_NAME"
    _ghostty_zmx_start_reaper "$ghosttyPID"
    _ghostty_zmx_restore_saved_scrollback "$SESSION_NAME"
    _ghostty_zmx_debug "attach session=$SESSION_NAME from_restore=$sessionFromRestore"
    if ! zmx attach "$SESSION_NAME"; then
      _ghostty_zmx_debug "zmx attach failed session=$SESSION_NAME status=$?"
    fi
    _ghostty_zmx_cleanup_after_detach "$SESSION_NAME"
  fi
fi
