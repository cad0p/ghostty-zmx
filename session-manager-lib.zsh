# ghostty-zmx shared session-manager library for zsh.
#
# This file is sourced by both:
# - session-manager-early.zsh from ~/.zprofile (minimal early inherit hook)
# - session-manager.zsh from ~/.zshrc (full interactive manager)
#
# It intentionally contains function definitions plus minimal environment/app
# derivation only. Do not add widget installation, auto-attach, poller, reaper,
# restore, or v0.1 fallback side effects here.

[[ "${_GHOSTTY_ZMX_LIB_SOURCED:-0}" == "1" ]] && return 0
_GHOSTTY_ZMX_LIB_SOURCED=1

# Default AppleScript app name; overridden by the hosting-bundle derivation below
# when running inside a Ghostty surface. Non-Ghostty surfaces never reach the
# v0.2 osascript call sites, so this default is only a safety net.
typeset _ghostty_app_name="Ghostty"
if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
  typeset _gzmx_bundle="${GHOSTTY_RESOURCES_DIR%/Contents/Resources/ghostty}"
  _ghostty_app_name="${_gzmx_bundle##*/}"
  _ghostty_app_name="${_ghostty_app_name%.app}"
fi

: ${GHOSTTY_ZMX_DATA_HOME:=${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx}
: ${GHOSTTY_ZMX_STATE_HOME:=${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-zmx}

ghostty_zmx_has_tty_capability() {
  [[ "${TERM_PROGRAM:-}" == "ghostty" && -n "${GHOSTTY_RESOURCES_DIR:-}" ]] || return 1
  osascript -e "tell application \"$_ghostty_app_name\" to get tty of focused terminal of selected tab of front window" >/dev/null 2>&1
}

_ghostty_zmx_hex_suffix() {
  typeset id="$1" suffix="" i ch
  [[ -n "$id" ]] || return 1
  for (( i=${#id}; i>=1; i-- )); do
    ch="${id:$((i-1)):1}"
    [[ "$ch" == [0-9a-fA-F] ]] || break
    suffix="${ch}${suffix}"
  done
  [[ -n "$suffix" ]] || return 1
  print -r -- "$suffix"
}

_ghostty_zmx_terminal_hash() {
  typeset suffix="$(_ghostty_zmx_hex_suffix "$1")" || return 1
  if [[ ${#suffix} -ge 8 ]]; then
    print -r -- "${suffix[1,8]}"
  else
    print -r -- "$suffix"
  fi
}

_ghostty_zmx_applescript_ids() {
  typeset raw="$1" win tab term
  win="$(_ghostty_zmx_hex_suffix "$(print -r -- "$raw" | awk '{print $1}')")" || return 1
  tab="$(_ghostty_zmx_hex_suffix "$(print -r -- "$raw" | awk '{print $2}')")" || return 1
  term="$(_ghostty_zmx_terminal_hash "$(print -r -- "$raw" | awk '{print $3}')")" || return 1
  print -r -- "$win $tab $term"
}

_ghostty_zmx_applescript_surface_ids() {
  typeset raw="$1" win tab
  win="$(_ghostty_zmx_hex_suffix "$(print -r -- "$raw" | awk '{print $1}')")" || return 1
  tab="$(_ghostty_zmx_hex_suffix "$(print -r -- "$raw" | awk '{print $2}')")" || return 1
  print -r -- "$win $tab"
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

_ghostty_zmx_shell_tty() {
  # Return the current shell's controlling tty. The result is interpolated
  # into an AppleScript heredoc downstream, so we tighten the shape to
  # /dev/<safe-chars>+ to make an adversarial `TTY=..." then return "...`
  # env var un-injectable. macOS ttys always match /dev/ttys### so this is
  # a defensive belt-and-braces check, not a behavior change.
  typeset shell_tty="${TTY:-}"
  [[ -n "$shell_tty" ]] || shell_tty="$(tty 2>/dev/null)" || return 1
  [[ "$shell_tty" == /dev/* ]] || return 1
  [[ "$shell_tty" =~ '^/dev/[A-Za-z0-9._/-]+$' ]] || return 1
  print -r -- "$shell_tty"
}

_ghostty_zmx_current_surface_identity() {
  typeset shell_tty="$(_ghostty_zmx_shell_tty)" raw ids pid tty_path
  [[ -n "$shell_tty" ]] || return 1
  raw="$(osascript <<EOF 2>/dev/null
tell application "$_ghostty_app_name"
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
  ids="$(_ghostty_zmx_applescript_ids "$raw")" || return 1
  pid="$(print -r -- "$raw" | awk '{print $4}')"
  tty_path="$(print -r -- "$raw" | awk '{print $5}')"
  [[ "$pid" =~ ^[0-9]+$ && "$tty_path" == /dev/* ]] || return 1
  print -r -- "$ids $pid $tty_path"
}

ghostty_zmx_hex_suffix() {
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

ghostty_zmx_remote_hosts_file() {
  print -r -- "${GHOSTTY_ZMX_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx}/remote-hosts"
}

ghostty_zmx_remote_projections_file() {
  print -r -- "${GHOSTTY_ZMX_DATA_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx}/remote-projections"
}

ghostty_zmx_projection_locks_dir() {
  local runtime="$(_ghostty_zmx_runtime_dir 2>/dev/null)" || return 1
  print -r -- "$runtime/projection-locks"
}

ghostty_zmx_projection_lock_path() {
  local host="$1" session="$2" dir hash
  [[ -n "$host" && -n "$session" ]] || return 1
  dir="$(ghostty_zmx_projection_locks_dir)" || return 1
  hash="$(print -r -- "${host}	${session}" | cksum | tr -d ' ' | cut -c1-12)"
  print -r -- "$dir/${hash}.lock"
}

ghostty_zmx_enumerate_terminals() {
  emulate -L zsh
  osascript <<EOF 2>/dev/null
tell application "$_ghostty_app_name"
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
}

ghostty_zmx_descendants_matching() {
  emulate -L zsh
  local root="$1" needle="$2" depth=0 maxdepth=6 queue=() p args
  [[ "$root" =~ ^[0-9]+$ && -n "$needle" ]] || return 1
  queue=("$root")
  while (( ${#queue} > 0 )) && (( depth < maxdepth )); do
    local next=()
    for p in "${queue[@]}"; do
      args="$(ps -o args= -p "$p" 2>/dev/null)" || continue
      if [[ "$args" == *"--session ${needle}"* || "$args" == *"zmx attach ${needle}"* ]]; then
        print -r -- "$p"
        return 0
      fi
      next+=($(pgrep -P "$p" 2>/dev/null))
    done
    queue=("${next[@]}")
    depth=$(( depth + 1 ))
  done
  return 1
}

ghostty_zmx_scan_live_projections() {
  emulate -L zsh
  local session="$1" raw pid tty_path win_id tab_id match_pid
  [[ -n "$session" ]] || return 1
  raw="$(ghostty_zmx_enumerate_terminals)" || return 1
  while read -r pid tty_path win_id tab_id; do
    [[ "$pid" =~ ^[0-9]+$ && "$tty_path" == /dev/* ]] || continue
    match_pid="$(ghostty_zmx_descendants_matching "$pid" "$session")" || continue
    print -r -- "${pid}	${tty_path}	${win_id}	${tab_id}	${match_pid}"
  done <<< "$raw"
}


ghostty_zmx_find_live_projection() {
  emulate -L zsh
  local host="$1" session="$2" row rest
  _gzmx_found_pid="" _gzmx_found_match_pid="" _gzmx_found_tty="" _gzmx_found_win="" _gzmx_found_tab=""
  while IFS=$'\t' read -r row; do
    [[ -n "$row" ]] || continue
    _gzmx_found_pid="${row%%$'\t'*}"
    rest="${row#*$'\t'}"
    _gzmx_found_tty="${rest%%$'\t'*}"
    rest="${rest#*$'\t'}"
    _gzmx_found_win="${rest%%$'\t'*}"
    rest="${rest#*$'\t'}"
    _gzmx_found_tab="${rest%%$'\t'*}"
    _gzmx_found_match_pid="${rest#*$'\t'}"
    return 0
  done < <(ghostty_zmx_scan_live_projections "$session")
  return 1
}

ghostty_zmx_write_projection_row() {
  emulate -L zsh
  local host="$1" workspace="$2" session="$3" tty_path="$4" match_pid="$5" state="$6" win="$7" tab="$8"
  local projection_file="$(ghostty_zmx_remote_projections_file)" tmp now lock acquired=0 i rc=0
  [[ -n "$host" && -n "$session" && -n "$state" ]] || return 1
  [[ -n "$tty_path" ]] || tty_path="-"
  [[ -n "$match_pid" ]] || match_pid="-"
  [[ -n "$win" ]] || win="-"
  [[ -n "$tab" ]] || tab="-"
  mkdir -p "${projection_file:h}" 2>/dev/null || return 1
  lock="${projection_file}.lock"
  for (( i=1; i<=50; i++ )); do
    if mkdir "$lock" 2>/dev/null; then acquired=1; break; fi
    sleep 0.02
  done
  [[ "$acquired" -eq 1 ]] || return 1
  now="$(date +%s)"
  tmp="${projection_file}.tmp.$$"
  if ! { awk -F '\t' -v host="$host" -v session="$session" '!(($1 == host) && ($3 == session)) { print }' "$projection_file" 2>/dev/null || true
         print -r -- "${host}	${workspace}	${session}	${tty_path}	${match_pid}	${state}	${now}	${win}	${tab}"
       } > "$tmp" || ! mv "$tmp" "$projection_file" 2>/dev/null; then
    rc=1
    rm -f "$tmp" 2>/dev/null || true
  fi
  rmdir "$lock" 2>/dev/null || true
  return "$rc"
}

ghostty_zmx_remote_prefix_for_host() {
  emulate -L zsh
  local host="$1" hosts_file="$(ghostty_zmx_remote_hosts_file)"
  [[ -f "$hosts_file" ]] || return 1
  awk -F '\t' -v host="$host" '$1 == host { print $5; exit }' "$hosts_file" 2>/dev/null
}

ghostty_zmx_notty_prefix() {
  emulate -L zsh
  local prefix_string="$1" _w expect_arg=0
  local -a probe=(${(z)prefix_string}) notty=()
  local inserted_t=0
  local i=1
  local is_tsh=0
  if [[ "${probe[1]}" == "tsh" && "${probe[2]:-}" == "ssh" ]]; then
    notty+=(tsh ssh)
    i=3
    is_tsh=1
  else
    notty+=("${probe[1]}")
    i=2
  fi
  for (( ; i <= ${#probe}; i++ )); do
    _w="${probe[$i]}"
    if [[ "$expect_arg" -eq 1 ]]; then
      notty+=("$_w")
      expect_arg=0
      continue
    fi
    case "$_w" in
      -t|-tt|--tty)
        ;;  # drop forced pty
      -T)
        [[ "$is_tsh" -eq 0 ]] && { notty+=(-T); inserted_t=1; }
        ;;
      -l|-p|-J|-o|-i|-F|-S|-b|-c|-m|-W|-L|-R|-D|--login|--proxy|--user|--port|--identity)
        notty+=("$_w")
        expect_arg=1
        ;;
      --login=*|--proxy=*|--user=*|--port=*|--identity=*)
        notty+=("$_w")
        ;;
      --)
        [[ "$is_tsh" -eq 0 && "$inserted_t" -eq 0 ]] && { notty+=(-T); inserted_t=1; }
        notty+=(--)
        ;;
      -*)
        notty+=("$_w")
        ;;
      *)
        # For OpenSSH, -T must appear before the destination. Appending it at
        # the end turns it into the remote command (`ssh host -T ...`). Insert
        # it immediately before the first non-option word (the destination),
        # preserving option arguments such as `ssh -F config host`.
        [[ "$is_tsh" -eq 0 && "$inserted_t" -eq 0 ]] && { notty+=(-T); inserted_t=1; }
        notty+=("$_w")
        ;;
    esac
  done
  [[ "$is_tsh" -eq 0 && "$inserted_t" -eq 0 ]] && notty+=(-T)
  print -r -- "${(j: :)notty}"
}

ghostty_zmx_remote_layout_helper_cmd() {
  print -r -- "\$HOME/.config/ghostty-zmx/ghostty-zmx-remote-layout"
}

ghostty_zmx_wrapper_path() {
  print -r -- "${GHOSTTY_ZMX_INSTALL_DIR:-$HOME/.config/ghostty-zmx}/ghostty-zmx"
}

ghostty_zmx_inherit_remote_context_if_any() {
  emulate -L zsh
  setopt local_options no_sh_word_split
  local identity="$1" projections_file="$(ghostty_zmx_remote_projections_file)" cur_win cur_tab cur_tty now
  # Bisection kill switch: disable the inherit hook entirely.
  [[ "${GHOSTTY_ZMX_DISABLE_INHERIT:-0}" != "1" ]] || { _ghostty_zmx_debug "inherit skipped reason=inherit-disabled"; return 1 }
  # Never inherit inside a projection surface. The projection wrapper sets
  # GHOSTTY_ZMX_PROJECTION=1; if a newly-opened projection window's shell runs
  # auto_attach, it must NOT re-inherit (which would cascade: each new
  # projection window opens another, ad infinitum).
  [[ "${GHOSTTY_ZMX_PROJECTION:-}" == "1" ]] && { _ghostty_zmx_debug "inherit skipped reason=projection-surface"; return 1 }
  [[ -f "$projections_file" && -n "$identity" ]] || return 1
  cur_win="$(print -r -- "$identity" | awk '{print $1}')"
  cur_tab="$(print -r -- "$identity" | awk '{print $2}')"
  cur_tty="$(print -r -- "$identity" | awk '{print $5}')"
  [[ -n "$cur_win" && -n "$cur_tab" && "$cur_tty" == /dev/* ]] || return 1
  # Avoid mutating remote layout/projection state if the tty has disappeared or
  # is not usable for the final exec redirections. In that case the early hook
  # must fail open so the later ~/.zshrc manager can retry the legacy path.
  [[ -r "$cur_tty" && -w "$cur_tty" ]] || return 1
  local host workspace parent_session tty_path pid state updated local_win local_tab norm_win norm_tab prefix session workspace_id remote_win remote_tab parent_pane pane parent axis ratio helper
  while IFS=$'\t' read -r host workspace parent_session tty_path pid state updated local_win local_tab; do
    [[ "$state" == "attached" || "$state" == "opening" ]] || continue
    # The poller/manager store raw AppleScript window/tab ids (e.g.
    # `tab-group-6000020060a0`); cur_win/cur_tab are hex-suffixes (e.g.
    # `6000020060a0`). Normalize both sides through hex_suffix so the
    # comparison matches regardless of which writer produced the row.
    # An `opening` row may have local_win="-" (widget hasn't recorded the
    # real window id yet). In that case scan live terminals for the parent
    # session's projection and use its window id — this closes the timing
    # window where a split happens before the poller upgrades the row to
    # `attached`, which previously caused the split to miss the match and
    # start a local zmx session instead of inheriting the remote context.
    if [[ "$local_win" == "-" ]]; then
      if ghostty_zmx_find_live_projection "$host" "$parent_session" 2>/dev/null; then
        local_win="$_gzmx_found_win"
        local_tab="$_gzmx_found_tab"
      fi
    fi
    norm_win="$(ghostty_zmx_hex_suffix "$local_win" 2>/dev/null || print -r -- "$local_win")"
    norm_tab="$(ghostty_zmx_hex_suffix "$local_tab" 2>/dev/null || print -r -- "$local_tab")"
    [[ "$norm_win" == "$cur_win" ]] || continue
    _ghostty_zmx_debug "inherit match host=$host parent_session=$parent_session cur_win=$cur_win cur_tab=$cur_tab norm_win=$norm_win norm_tab=$norm_tab"
    prefix="$(ghostty_zmx_remote_prefix_for_host "$host")"
    [[ -n "$prefix" ]] || continue
    local wrapper_path="$(ghostty_zmx_wrapper_path)"
    # Wrapper existence is pre-checked here so we can fail-open before any
    # remote/local state mutation. It is re-checked immediately before exec
    # to shrink the TOCTOU window (see below).
    [[ -x "$wrapper_path" ]] || { _ghostty_zmx_debug "inherit skipped reason=wrapper-missing path=$wrapper_path"; return 1 }
    local -a parts
    parts=(${(@s:-:)parent_session})
    [[ "${parts[1]:-}" == "gzr" && ${#parts} -ge 5 ]] || continue
    workspace_id="${parts[2]}"
    remote_win="${parts[3]}"
    if [[ "$norm_tab" == "$cur_tab" ]]; then
      remote_tab="${parts[4]}"
      parent_pane="${parts[5]}"
      # Ghostty's AppleScript does not expose per-terminal frame/position, so
      # the inherit hook cannot detect whether the user split right (horizontal)
      # or down (vertical). Default to `horizontal` (right), which is Ghostty's
      # default split direction (Ctrl+Shift+D). Exact split-direction restore is
      # a known limitation; the design doc notes ratio/axis fidelity can improve
      # later. The parent-pane id IS recorded correctly so the restore knows the
      # nesting tree, just not the exact direction of each split.
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
    helper="$(ghostty_zmx_remote_layout_helper_cmd)"
    # Transactional ordering (see e2e round 6 report): acquire the local
    # per-host+session lock BEFORE mutating remote layout. If any pre-exec
    # step fails after the remote `add` succeeds, best-effort roll the
    # remote row back with `transition <session> deleted` so a later poller
    # cannot resurrect an orphan projection.
    local -a notty_prefix
    notty_prefix=(${(z)prefix})
    local -a rollback_argv
    rollback_argv=(${(z)$(ghostty_zmx_notty_prefix "$prefix")} "$helper" transition "$session" deleted)
    _gzmx_inherit_rollback() {
      # Fire and forget: server helper transitions the row to `deleted`.
      # Failure to reach the server is logged but not surfaced — the poller/
      # reaper close-txn path will eventually converge; the important part
      # is that we do NOT leave a `present` row that another client may open.
      "${rollback_argv[@]}" >/dev/null 2>&1 || _ghostty_zmx_debug "inherit rollback failed host=$host session=$session"
    }
    local inh_lock inh_acquired=0 inh_i
    inh_lock="$(ghostty_zmx_projection_lock_path "$host" "$session")" || return 1
    mkdir -p "${inh_lock:h}" 2>/dev/null
    for (( inh_i=1; inh_i<=50; inh_i++ )); do
      mkdir "$inh_lock" 2>/dev/null && { inh_acquired=1; break; }
      sleep 0.03
    done
    if [[ "$inh_acquired" -ne 1 ]]; then
      _ghostty_zmx_debug "inherit lock-busy host=$host session=$session"
      return 1
    fi
    # The helper generates updated-at and a monotonic rev server-side under the
    # remote lock; the ssh argv is bare words only (no awk/printf/tabs).
    # Use no-pty ssh (-T) for the non-interactive layout write.
    if ! ${(z)$(ghostty_zmx_notty_prefix "$prefix")} "$helper" add "$workspace_id" "$remote_win" "$remote_tab" "$pane" "$session" "$parent_pane" "$axis" "$ratio" present >/dev/null 2>&1; then
      rmdir "$inh_lock" 2>/dev/null || true
      _ghostty_zmx_debug "inherit remote-add-failed host=$host session=$session"
      return 1
    fi
    # Write the local projection row (under the same per-session lock) so the
    # poller sees an opening row and skips.
    if ! ghostty_zmx_write_projection_row "$host" "$workspace_id" "$session" "$cur_tty" "$$" opening "$cur_win" "$cur_tab"; then
      _ghostty_zmx_debug "inherit local-write-failed host=$host session=$session"
      _gzmx_inherit_rollback
      rmdir "$inh_lock" 2>/dev/null || true
      return 1
    fi
    rmdir "$inh_lock" 2>/dev/null || true
    # Re-check wrapper executability immediately before exec to shrink the
    # TOCTOU window between the earlier check and the exec. A short window
    # remains (exec itself may fail e.g. ENOEXEC/permission race), for which
    # the reaper's close-txn path is the final line of defense.
    if [[ ! -x "$wrapper_path" ]]; then
      _ghostty_zmx_debug "inherit wrapper-vanished host=$host session=$session path=$wrapper_path"
      _gzmx_inherit_rollback
      # Best-effort local cleanup so the poller does not adopt a stale row.
      local _proj_file="$(ghostty_zmx_remote_projections_file)" _tmp="${projections_file}.tmp.$$"
      awk -F '\t' -v h="$host" -v s="$session" '!(($1 == h) && ($3 == s)) { print }' "$_proj_file" > "$_tmp" 2>/dev/null && mv "$_tmp" "$_proj_file" 2>/dev/null
      return 1
    fi
    _ghostty_zmx_debug "inherit exec host=$host session=$session cur_win=$cur_win cur_tab=$cur_tab tty=$cur_tty"
    # If this function was reached from the ~/.zprofile early hook, mark the
    # current shell as handled immediately before exec. Do not set this marker
    # earlier: transient identity/projection-row races should fall back to the
    # later ~/.zshrc inherit attempt rather than starting a wrong local pane.
    # Do not export it: it is meaningful only for this startup shell.
    GHOSTTY_ZMX_EARLY_INHERIT_RAN=1
    # Native split/tab inheritance (per design): exec the projection wrapper
    # in-place so the split pane BECOMES the remote projection. The wrapper
    # writes the server layout row then execs the transport ssh. fds must be
    # pointed at the tty so the transport's `ssh -t ... zmx attach` gets a
    # real interactive pty; otherwise zmx attach exits and Ghostty reaps the
    # surface.
    #
    # Build the argv directly (not via ${(z)} on a string) so the remote
    # command `zmx attach <session>` is a single clean word — ${(z)} on a
    # string with single quotes preserves the quotes as literal characters,
    # which ssh passes through and the remote shell mis-parses, causing
    # `zmx attach` to exit without creating the session.
    # Source ~/.zshrc on the remote so zmx is found when it's only on the
    # interactive PATH (see ghostty_zmx_projection_command_string rationale).
    #
    # When called from the ~/.zprofile early hook, this exec happens before the
    # split shell sources ~/.zshrc, preventing local prompt/plugin terminal
    # queries from being emitted. If the early hook cannot decide and the later
    # ~/.zshrc manager reaches this path instead, it preserves the legacy
    # behavior (and therefore the older query-response leak limitation).
    exec "$wrapper_path" projection --host "$host" --workspace "$workspace_id" --session "$session" -- "${notty_prefix[@]}" "source ~/.zshrc 2>/dev/null; zmx attach $session" <"$cur_tty" >"$cur_tty" 2>&1
  done < "$projections_file"
  return 1
}
