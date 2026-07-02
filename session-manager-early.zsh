# ghostty-zmx early inherit hook (Prototype A: .zprofile early-exec).
#
# Sourced from ~/.zprofile BEFORE ~/.zshrc, so the split pane execs the
# projection wrapper before any oh-my-zsh / zsh-autosuggestions / prompt
# plugin runs. This kills the OSC 11 / CSI 6n terminal-query response leak
# into split-pane scrollback (the queries are emitted by .zshrc plugins;
# if we exec before .zshrc, no queries are emitted in the split pane).
#
# This file is SELF-CONTAINED: it defines only the minimal helpers the
# inherit path needs, so sourcing it from .zprofile does NOT run the full
# v0.2 auto-attach/widget/poller setup (that stays in session-manager.zsh,
# sourced from .zshrc). If a projection ancestor is found, this file execs
# the ghostty-zmx wrapper in-place and the shell process is replaced; .zshrc
# never runs for this surface. If no ancestor is found, this file returns
# silently and .zshrc sources the full manager as usual.
#
# Coordination with session-manager.zsh: the full manager's auto-attach
# inherit block checks GHOSTTY_ZMX_EARLY_INHERIT_RAN=1 and skips its own
# inherit attempt (the early hook already decided). We set that marker
# whenever we run the inherit check, regardless of outcome, so the .zshrc
# path never double-fires (and never re-tries the 8x identity loop).

# Bail unless we're in an interactive Ghostty surface with auto-attach on.
[[ "${TERM_PROGRAM:-}" == "ghostty" ]] || return 0
[[ "${GHOSTTY_ZMX_AUTO_ATTACH:-}" == "1" ]] || return 0
# Never run inside a projection surface (the wrapper sets
# GHOSTTY_ZMX_PROJECTION=1); re-inheriting would cascade.
[[ "${GHOSTTY_ZMX_PROJECTION:-}" == "1" ]] && return 0
# Bisection kill switch.
[[ "${GHOSTTY_ZMX_DISABLE_INHERIT:-0}" != "1" ]] || return 0
# If the early hook already ran for this process (defensive; .zprofile should
# only source once), don't re-run.
[[ "${GHOSTTY_ZMX_EARLY_INHERIT_RAN:-}" != "1" ]] || return 0
export GHOSTTY_ZMX_EARLY_INHERIT_RAN=1

# --- minimal helpers (copies of the manager's, kept in sync manually) -----

_gzmx_early_debug() {
  [[ "${GHOSTTY_ZMX_DEBUG:-0}" == "1" ]] || return 0
  local _d="${GHOSTTY_ZMX_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-zmx}"
  mkdir -p "$_d" 2>/dev/null
  print -r -- "$(date -u '+%Y-%m-%dT%H:%M:%SZ') early $*" >> "$_d/debug.log"
}

_gzmx_early_data_home() {
  print -r -- "${GHOSTTY_ZMX_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx}"
}

_gzmx_early_hex_suffix() {
  local id="$1" suffix="" i ch
  [[ -n "$id" ]] || return 1
  for (( i=${#id}; i>=1; i-- )); do
    ch="${id:$((i-1)):1}"
    [[ "$ch" == [0-9a-fA-F] ]] || break
    suffix="${ch}${suffix}"
  done
  [[ -n "$suffix" ]] || return 1
  print -r -- "$suffix"
}

# Derive the hosting Ghostty AppleScript app name from GHOSTTY_RESOURCES_DIR
# (bundle leaf). Mirrors the manager's derivation.
_gzmx_early_app_name() {
  local app_name="Ghostty"
  if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
    local bundle="${GHOSTTY_RESOURCES_DIR%/Contents/Resources/ghostty}"
    app_name="${bundle##*/}"
    app_name="${app_name%.app}"
  fi
  print -r -- "$app_name"
}

# Shell's controlling tty (zsh sets $TTY; fall back to the `tty` command).
_gzmx_early_shell_tty() {
  if [[ -n "${TTY:-}" && "${TTY}""x" == /dev/* ]]; then
    print -r -- "$TTY"
    return 0
  fi
  tty 2>/dev/null
}

# Return the current surface identity as "win-hex tab-hex term-id pid tty",
# matched by the shell's tty against `tty of every terminal`. Empty on miss.
_gzmx_early_current_surface_identity() {
  local shell_tty raw ids pid tty_path
  shell_tty="$(_gzmx_early_shell_tty)" || return 1
  [[ -n "$shell_tty" ]] || return 1
  local app="$(_gzmx_early_app_name)"
  raw="$(osascript <<EOF 2>/dev/null
tell application "$app"
  repeat with w in windows
    set winStr to id of w as string
    repeat with tb in tabs of w
      set tabStr to id of tb as string
      repeat with tm in terminals of tb
        try
          set ttyStr to tty of tm as string
          if ttyStr is "$shell_tty" then
            set termStr to id of tm as string
            set pidStr to pid of tm as string
            return winStr & " " & tabStr & " " & termStr & " " & pidStr & " " & ttyStr
          end if
        end try
      end repeat
    end repeat
  end repeat
  error "terminal tty not found: $shell_tty"
end tell
EOF
)" || return 1
  # Normalize win/tab to hex suffixes (the projections file stores hex
  # suffixes; AppleScript ids are like "tab-group-6000020060a0").
  local win_hex tab_hex
  win_hex="$(_gzmx_early_hex_suffix "$(print -r -- "$raw" | awk '{print $1}')")" || return 1
  tab_hex="$(_gzmx_early_hex_suffix "$(print -r -- "$raw" | awk '{print $2}')")" || return 1
  pid="$(print -r -- "$raw" | awk '{print $4}')"
  tty_path="$(print -r -- "$raw" | awk '{print $5}')"
  [[ "$pid" =~ ^[0-9]+$ && "$tty_path" == /dev/* ]] || return 1
  print -r -- "${win_hex} ${tab_hex} $(print -r -- "$raw" | awk '{print $3}') ${pid} ${tty_path}"
}

_gzmx_early_remote_projections_file() {
  print -r -- "$(_gzmx_early_data_home)/remote-projections"
}

_gzmx_early_remote_hosts_file() {
  print -r -- "$(_gzmx_early_data_home)/remote-hosts"
}

# Look up the transport prefix for a host from remote-hosts (5th field).
_gzmx_early_remote_prefix_for_host() {
  local host="$1" line prefix
  [[ -n "$host" ]] || return 1
  [[ -f "$(_gzmx_early_remote_hosts_file)" ]] || return 1
  while IFS=$'\t' read -r line; do
    [[ "${line%%$'\t'*}" == "$host" ]] || continue
    prefix="$(print -r -- "$line" | awk -F '\t' '{print $5}')"
    [[ -n "$prefix" ]] && { print -r -- "$prefix"; return 0; }
  done < "$(_gzmx_early_remote_hosts_file)"
  return 1
}

# Build a no-pty ssh argv (drop -t/-tt/--tty, add -T) from a prefix string.
_gzmx_early_notty_prefix() {
  local prefix="$1" -a notty=() have_t=0 is_tsh=0 w
  notty=(${(z)prefix})
  if [[ "${notty[1]:-}" == "tsh" && "${notty[2]:-}" == "ssh" ]]; then
    is_tsh=1
  fi
  local -a out=()
  for w in "${notty[@]}"; do
    case "$w" in
      -t|-tt|--tty) ;;
      -T) [[ "$is_tsh" -eq 0 ]] && { out+=(-T); have_t=1 } ;;
      *) out+=("$w") ;;
    esac
  done
  [[ "$is_tsh" -eq 1 || "$have_t" -eq 1 ]] || out+=(-T)
  print -r -- "${out[*]}"
}

_gzmx_early_wrapper_path() {
  print -r -- "${GHOSTTY_ZMX_INSTALL_DIR:-$HOME/.config/ghostty-zmx}/ghostty-zmx"
}

_gzmx_early_projection_lock_path() {
  local host="$1" session="$2" runtime dir hash
  [[ -n "$host" && -n "$session" ]] || return 1
  runtime="${GHOSTTY_ZMX_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}}/ghostty-zmx-${UID:-$(id -u)}"
  dir="$runtime/projection-locks"
  hash="$(print -r -- "${host}	${session}" | cksum | tr -d ' ' | cut -c1-12)"
  print -r -- "$dir/${hash}.lock"
}

_gzmx_early_write_projection_row() {
  local host="$1" workspace="$2" session="$3" tty="$4" pid="$5" state="$6" win="$7" tab="$8"
  local file tmp now
  file="$(_gzmx_early_remote_projections_file)"
  mkdir -p "${file:h}" 2>/dev/null
  now="$(date +%s)"
  tmp="${file}.tmp.$$"
  {
    awk -F '\t' -v h="$host" -v s="$session" '$1 != h || $3 != s { print }' "$file" 2>/dev/null || true
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$host" "$workspace" "$session" "$tty" "$pid" "$state" "$now" "$win" "$tab" \
      "${GHOSTTY_ZMX_CLIENT_ID:-local}" "-" "$pid" "-" "-" "$now" "-"
  } > "$tmp" && mv "$tmp" "$file" 2>/dev/null
}

# Scan live Ghostty terminals for an existing projection of a session and
# return its win/tab ids. Sets _gzmx_early_found_win / _gzmx_early_found_tab.
_gzmx_early_found_win="" _gzmx_early_found_tab=""
_gzmx_early_find_live_projection() {
  local host="$1" parent_session="$2" app raw pid tty_path win_id tab_id match_pid
  _gzmx_early_found_win="" _gzmx_early_found_tab=""
  app="$(_gzmx_early_app_name)"
  raw="$(osascript <<EOF 2>/dev/null
tell application "$app"
  set out to ""
  repeat with w in windows
    set winStr to id of w as string
    repeat with tb in tabs of w
      set tabStr to id of tb as string
      repeat with tm in terminals of tb
        try
          set out to out & (pid of tm as string) & " " & (tty of tm as string) & " " & winStr & " " & tabStr & linefeed
        end try
      end repeat
    end repeat
  end repeat
  return out
end tell
EOF
)" || return 1
  local p args
  while read -r pid tty_path win_id tab_id; do
    [[ "$pid" =~ ^[0-9]+$ && "$tty_path" == /dev/* ]] || continue
    # Walk descendants looking for the session marker in args.
    local queue=("$pid") depth=0 found=0
    while (( ${#queue} > 0 )) && (( depth < 6 )); do
      local next=()
      for p in "${queue[@]}"; do
        args="$(ps -o args= -p "$p" 2>/dev/null)" || continue
        if [[ "$args" == *"--session ${parent_session}"* || "$args" == *"zmx attach ${parent_session}"* ]]; then
          found=1
          break 2
        fi
        next+=($(pgrep -P "$p" 2>/dev/null))
      done
      queue=("${next[@]}")
      depth=$(( depth + 1 ))
    done
    if (( found == 1 )); then
      _gzmx_early_found_win="$(_gzmx_early_hex_suffix "$win_id" 2>/dev/null || print -r -- "$win_id")"
      _gzmx_early_found_tab="$(_gzmx_early_hex_suffix "$tab_id" 2>/dev/null || print -r -- "$tab_id")"
      return 0
    fi
  done <<< "$raw"
  return 1
}

# --- the inherit check + exec (mirrors ghostty_zmx_inherit_remote_context_if_any) ---

_gzmx_early_inherit() {
  local identity="$1" projections_file cur_win cur_tab cur_tty
  projections_file="$(_gzmx_early_remote_projections_file)"
  [[ -f "$projections_file" && -n "$identity" ]] || return 1
  cur_win="$(print -r -- "$identity" | awk '{print $1}')"
  cur_tab="$(print -r -- "$identity" | awk '{print $2}')"
  cur_tty="$(print -r -- "$identity" | awk '{print $5}')"
  [[ -n "$cur_win" && -n "$cur_tab" && "$cur_tty" == /dev/* ]] || return 1
  local host workspace parent_session tty_path pid state updated local_win local_tab norm_win norm_tab prefix
  while IFS=$'\t' read -r host workspace parent_session tty_path pid state updated local_win local_tab; do
    [[ "$state" == "attached" || "$state" == "opening" ]] || continue
    if [[ "$local_win" == "-" ]]; then
      if _gzmx_early_find_live_projection "$host" "$parent_session" 2>/dev/null; then
        local_win="$_gzmx_early_found_win"
        local_tab="$_gzmx_early_found_tab"
      fi
    fi
    norm_win="$(_gzmx_early_hex_suffix "$local_win" 2>/dev/null || print -r -- "$local_win")"
    norm_tab="$(_gzmx_early_hex_suffix "$local_tab" 2>/dev/null || print -r -- "$local_tab")"
    [[ "$norm_win" == "$cur_win" ]] || continue
    _gzmx_early_debug "early-inherit match host=$host parent_session=$parent_session cur_win=$cur_win cur_tab=$cur_tab"
    prefix="$(_gzmx_early_remote_prefix_for_host "$host")"
    [[ -n "$prefix" ]] || continue
    local -a parts
    parts=(${(@s:-:)parent_session})
    [[ "${parts[1]:-}" == "gzr" && ${#parts} -ge 5 ]] || continue
    local workspace_id="${parts[2]}" remote_win="${parts[3]}" remote_tab parent_pane pane session axis ratio
    if [[ "$norm_tab" == "$cur_tab" ]]; then
      remote_tab="${parts[4]}"
      parent_pane="${parts[5]}"
      axis="horizontal"
      ratio="0.5"
    else
      remote_tab="${$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d '[:space:]')[1,6]}"
      parent_pane="-"
      axis="root"
      ratio="1"
    fi
    pane="${$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d '[:space:]')[1,6]}"
    session="gzr-${workspace_id}-${remote_win}-${remote_tab}-${pane}"
    local notty="$(_gzmx_early_notty_prefix "$prefix")"
    local helper_cmd="$HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout"
    # Write the server layout row (state=present) via the helper, no-pty ssh.
    ${(z)notty} "$helper_cmd" add "$workspace_id" "$remote_win" "$remote_tab" "$pane" "$session" "$parent_pane" "$axis" "$ratio" present >/dev/null 2>&1 || return 1
    # Write the local opening projection row under the per-host+session lock.
    local inh_lock inh_acquired=0 inh_i
    inh_lock="$(_gzmx_early_projection_lock_path "$host" "$session")" || return 1
    mkdir -p "${inh_lock:h}" 2>/dev/null
    for (( inh_i=1; inh_i<=50; inh_i++ )); do
      mkdir "$inh_lock" 2>/dev/null && { inh_acquired=1; break; }
      sleep 0.03
    done
    if [[ "$inh_acquired" -ne 1 ]]; then
      _gzmx_early_debug "early-inherit lock-busy host=$host session=$session"
      return 1
    fi
    _gzmx_early_write_projection_row "$host" "$workspace_id" "$session" "$cur_tty" "$$" opening "$cur_win" "$cur_tab"
    rmdir "$inh_lock" 2>/dev/null || true
    local wrapper_path="$(_gzmx_early_wrapper_path)"
    local -a notty_prefix
    notty_prefix=(${(z)prefix})
    _gzmx_early_debug "early-inherit exec host=$host session=$session cur_win=$cur_win cur_tab=$cur_tab tty=$cur_tty"
    # exec the wrapper in-place; the wrapper writes the present row (above we
    # wrote opening) and execs ssh. fds pointed at the tty so ssh -t gets a pty.
    exec "$wrapper_path" projection --host "$host" --workspace "$workspace_id" --session "$session" -- "${notty_prefix[@]}" "source ~/.zshrc 2>/dev/null; zmx attach $session" <"$cur_tty" >"$cur_tty" 2>&1
  done < "$projections_file"
  return 1
}

# --- run the inherit check (retries identity a few times for AppleScript lag) ---

{
  local _early_identity="" _early_attempt
  for (( _early_attempt=1; _early_attempt<=8; _early_attempt++ )); do
    _early_identity="$(_gzmx_early_current_surface_identity)"
    if [[ -n "$_early_identity" ]]; then
      break
    fi
    _gzmx_early_debug "early-inherit identity-not-ready attempt=$_early_attempt"
    sleep 0.25
  done
  if [[ -n "$_early_identity" ]]; then
    _gzmx_early_debug "early-inherit attempt=$_early_attempt identity=$_early_identity"
    _gzmx_early_inherit "$_early_identity" && return 0
  else
    _gzmx_early_debug "early-inherit no-identity after $_early_attempt attempts"
  fi
} 2>/dev/null

# No projection ancestor found (or inherit skipped). Fall through to .zshrc,
# which sources the full session-manager.zsh for normal auto-attach/restore.
return 0
