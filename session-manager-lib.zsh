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

# Find the tty of a SIBLING projection pane in the same window+tab as the
# newly-created split pane (cur_win/cur_tab), other than the new pane itself
# (cur_tty). When the user splits a pane, Ghostty creates a new terminal
# (cur_tty) as a sibling of the previously-focused pane. The previously-
# focused pane is the TRUE parent of the split — its remote cwd is what the
# new pane should inherit, not the first pane in the tab (which may be at a
# different cwd, e.g. the window's root pane still at ~ while the user
# split a pane that had cd'd into a project).
#
# When multiple siblings exist (3+ panes in a tab), the parent is the most
# recently CREATED sibling — i.e. the pane the user was most likely focused
# on when they split. We cannot query Ghostty for "previous focus", but the
# remote zmx `created` timestamp is a reliable recency signal: the pane being
# split was created after its older siblings. The caller passes the remote
# zmx binary so we can query `zmx list` for created times. If the query
# fails, we fall back to the first sibling (legacy behavior).
#
# Returns 0 and prints the best sibling tty on stdout if found, 1 otherwise.
ghostty_zmx_find_sibling_tty() {
  emulate -L zsh
  local cur_win="$1" cur_tab="$2" cur_tty="$3" raw pid tty_path win_id tab_id
  [[ -n "$cur_win" && -n "$cur_tab" && "$cur_tty" == /dev/* ]] || return 1
  raw="$(ghostty_zmx_enumerate_terminals)" || return 1
  local -a sib_ttys
  while read -r pid tty_path win_id tab_id; do
    [[ "$tty_path" == /dev/* && "$tty_path" != "$cur_tty" ]] || continue
    local sw="$(ghostty_zmx_hex_suffix "$win_id" 2>/dev/null || print -r -- "$win_id")"
    local st="$(ghostty_zmx_hex_suffix "$tab_id" 2>/dev/null || print -r -- "$tab_id")"
    if [[ "$sw" == "$cur_win" && "$st" == "$cur_tab" ]]; then
      sib_ttys+=("$tty_path")
    fi
  done <<< "$raw"
  (( ${#sib_ttys} > 0 )) || return 1
  # One sibling: return it directly.
  if (( ${#sib_ttys} == 1 )); then
    print -r -- "${sib_ttys[1]}"
    return 0
  fi
  # Multiple siblings: return all, newline-separated. The caller picks the
  # best parent (newest remote created) among matching projection rows.
  printf '%s\n' "${sib_ttys[@]}"
  return 0
}

# Among multiple sibling panes in a tab, pick the one that was most likely
# focused when the user hit Cmd+D — i.e. the pane whose remote zmx session was
# MOST RECENTLY created. We cannot query Ghostty for "previous focus" (native
# new_split moves focus to the new pane), and AppleScript exposes no parent
# surface property. The `created` timestamp from the remote `zmx list` is a
# reliable recency proxy: the pane the user split is the one they most recently
# created or were interacting with.
#
# Args: cur_win cur_tab sibling_ttys (newline-separated). Reads the local
# remote-projections file to map each sibling tty -> its gzr-* session, then
# queries the remote host's zmx list for each session's `created` time.
# Returns: the sibling tty with the newest created timestamp (or, if the
# remote query fails for all, the first sibling — preserving legacy behavior).
ghostty_zmx_select_parent_by_recency() {
  emulate -L zsh
  setopt local_options no_sh_word_split
  local cur_win="$1" cur_tab="$2" sibling_ttys="$3"
  local projections_file host workspace parent_session tty_path pid state updated local_win local_tab norm_win norm_tab
  [[ -n "$sibling_ttys" ]] || return 1
  projections_file="$(ghostty_zmx_remote_projections_file)"
  [[ -f "$projections_file" ]] || return 1
  # The parent is the sibling whose local projection wrapper has the HIGHEST
  # pid — pids are monotonic per boot, so the most-recently-created wrapper
  # is the pane the user most recently split. This is a LOCAL file lookup
  # (no remote ssh round-trip), avoiding both latency and the 1-second
  # resolution of the remote `zmx list created` field.
  local best_tty="" best_pid=0 first_tty=""
  while IFS=$'\t' read -r host workspace parent_session tty_path pid state updated local_win local_tab; do
    [[ "$state" == "attached" || "$state" == "opening" ]] || continue
    norm_win="$(ghostty_zmx_hex_suffix "$local_win" 2>/dev/null || print -r -- "$local_win")"
    [[ "$norm_win" == "$cur_win" ]] || continue
    [[ -n "$tty_path" && "$tty_path" == /dev/* ]] || continue
    # Is this row's tty one of the siblings?
    print -r -- "$sibling_ttys" | grep -qF -- "$tty_path" || continue
    [[ -z "$first_tty" ]] && first_tty="$tty_path"
    # match_pid is the 5th field (the local wrapper process pid).
    if [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > best_pid )); then
      best_pid=$pid
      best_tty="$tty_path"
    fi
  done < "$projections_file"
  if [[ -n "$best_tty" ]]; then
    print -r -- "$best_tty"
    return 0
  fi
  # No pid-based winner (all rows had non-numeric pids) — fall back to first.
  [[ -n "$first_tty" ]] || return 1
  print -r -- "$first_tty"
  return 0
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

ghostty_zmx_remote_zmx_for_host() {
  emulate -L zsh
  local host="$1" hosts_file="$(ghostty_zmx_remote_hosts_file)" zmx_path
  [[ -f "$hosts_file" ]] || { print -r -- "zmx"; return 0; }
  zmx_path="$(awk -F '\t' -v host="$host" '$1 == host { print $6; exit }' "$hosts_file" 2>/dev/null)"
  if [[ "$zmx_path" =~ '^/[A-Za-z0-9._~+@%/=-]+$' ]]; then
    print -r -- "$zmx_path"
  else
    print -r -- "zmx"
  fi
}

# Resolve a transport binary (tsh/ssh) to an absolute path. The projection
# wrapper runs under `#!/bin/zsh -f` as a Ghostty surface command, inheriting
# Ghostty's launchd PATH — which does NOT include /usr/local/bin on macOS
# (where tsh lives). A bare `tsh` in the projection prefix thus fails with
# `command not found: tsh`. Resolve to an absolute path up front (same pattern
# as ghostty_zmx_remote_zmx_for_host for the remote zmx binary). Falls back to
# the bare name (not empty) when the binary is not on PATH, so the error is
# honest ("command not found: tsh") rather than a silent empty exec.

# Is the given argv a `tsh ssh ...` invocation? Detects tsh by the BASENAME
# of the first word, so both bare `tsh` and an absolute path
# (e.g. /usr/local/bin/tsh, as the widget builds after transport-path
# resolution) are detected. tsh does not accept ssh's `-T` (no-pty) flag,
# so callers use this to avoid inserting `-T` into tsh commands. Returns 0
# (true) if the argv is `tsh ssh ...`, 1 otherwise.
ghostty_zmx_is_tsh_ssh() {
  emulate -L zsh
  local bin="${1:-}"
  [[ "${bin:t}" == "tsh" && "${2:-}" == "ssh" ]]
}

ghostty_zmx_resolve_transport_path() {
  emulate -L zsh
  local bin="$1" resolved
  [[ -n "$bin" ]] || { print -r -- "$bin"; return 0; }
  resolved="$(command -v "$bin" 2>/dev/null)" || { print -r -- "$bin"; return 0; }
  if [[ "$resolved" == /* ]]; then
    print -r -- "$resolved"
  else
    print -r -- "$bin"
  fi
}

ghostty_zmx_notty_prefix() {
  emulate -L zsh
  local prefix_string="$1" _w expect_arg=0
  local -a probe=(${(z)prefix_string}) notty=()
  local inserted_t=0
  local i=1
  local is_tsh=0
  # Detect tsh transport by the basename of probe[1], so an absolute path
  # (e.g. /usr/local/bin/tsh, as the widget builds after transport-path
  # resolution) is still detected as tsh. tsh does not accept ssh's `-T`
  # flag, so we must not insert it for tsh commands.
  if ghostty_zmx_is_tsh_ssh "${probe[1]}" "${probe[2]:-}"; then
    notty+=("${probe[1]}" ssh)
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
  # When the user splits a pane in a tab that already has multiple projection
  # panes (e.g. they cd'd in one and split it), the inherit loop must identify
  # the TRUE parent — the pane that was focused when Cmd+D was hit — not the
  # first projection row that matches the window. Ghostty's native `new_split`
  # moves focus to the NEW pane, so at .zprofile time `focused terminal` is the
  # new pane (cur_tty), not the parent. We cannot query Ghostty for "previous
  # focus", and AppleScript exposes no `parent surface` property.
  #
  # The reliable proxy: the parent is the sibling whose REMOTE zmx session was
  # MOST RECENTLY created. The pane the user was focused on is the one they
  # most recently created/used — its remote session has the newest `created`
  # timestamp among siblings. We enumerate the sibling ttys in the same tab
  # (other than cur_tty), then for each, map the sibling tty -> its remote
  # `gzr-*` session (via the projection row's tty field) -> the remote zmx
  # `created` timestamp, and pick the newest.
  #
  # If only one sibling exists, it is trivially the parent. If the remote
  # `created` query fails or siblings can't be mapped to sessions, fall back
  # to the legacy first-matching-row behavior so single-pane / race cases
  # still inherit correctly.
  local _sibling_ttys=""
  _sibling_ttys="$(ghostty_zmx_find_sibling_tty "$cur_win" "$cur_tab" "$cur_tty" 2>/dev/null)" || _sibling_ttys=""
  local _sib_count=0
  if [[ -n "$_sibling_ttys" ]]; then
    _sib_count=$(print -r -- "$_sibling_ttys" | wc -l | tr -d ' ')
    _ghostty_zmx_debug "inherit sibling-tty cur_win=$cur_win cur_tab=$cur_tab cur_tty=$cur_tty count=$_sib_count ttys=$(print -r -- "$_sibling_ttys" | tr '\n' ',')"
  fi
  # When multiple siblings exist, the parent is the one whose remote zmx
  # session was MOST RECENTLY created (the pane the user was focused on is
  # the one they most recently created/used). Query each candidate's remote
  # `created` and pin the best parent tty so the loop below picks it. With a
  # single sibling, that sibling IS the parent — no remote query needed.
  local _best_parent_tty=""
  if (( _sib_count > 1 )); then
    _best_parent_tty="$(ghostty_zmx_select_parent_by_recency "$cur_win" "$cur_tab" "$_sibling_ttys" 2>/dev/null)" || _best_parent_tty=""
    _ghostty_zmx_debug "inherit best-parent-tty=$_best_parent_tty"
  elif (( _sib_count == 1 )); then
    _best_parent_tty="$_sibling_ttys"
  fi
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
    # Disambiguate multi-pane tabs: if we found a best parent tty (single or
    # selected), require this row's tty to match it. This picks the TRUE parent
    # (the pane that was focused when Cmd+D was hit) even when multiple
    # projection rows share the window. If no sibling was found (race / single
    # pane not yet in projections), fall back to the legacy first-match behavior
    # so the common case still inherits.
    if [[ -n "$_best_parent_tty" && "$tty_path" != "$_best_parent_tty" ]]; then
      _ghostty_zmx_debug "inherit skip-nonbest tty=$tty_path best=$_best_parent_tty session=$parent_session"
      continue
    fi
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
    # Use the probed absolute remote zmx path when available so attach does not
    # source the remote ~/.zshrc (remote prompt/plugins can emit terminal queries
    # whose responses leak into zmx scrollback).
    #
    # When called from the ~/.zprofile early hook, this exec happens before the
    # split shell sources ~/.zshrc, preventing local prompt/plugin terminal
    # queries from being emitted. If the early hook cannot decide and the later
    # ~/.zshrc manager reaches this path instead, it preserves the legacy
    # behavior (and therefore the older query-response leak limitation).
    local _remote_zmx="$(ghostty_zmx_remote_zmx_for_host "$host")"
    # Inherit the parent remote session's cwd so the new split/tab remote
    # session starts in the same directory (matches Ghostty's
    # split-inherit-working-directory / tab-inherit-working-directory for
    # remote panes). zmx's spawned shell inherits the caller's cwd as
    # start_dir, so we `cd` to the parent's cwd before attaching.
    #
    # The reliable way to query the LIVE cwd on Linux is to read
    # /proc/<pid>/cwd: `zmx list` exposes the session pid, and readlink on
    # the /proc/<pid>/cwd symlink yields the current cwd (not the initial
    # start_dir). This avoids the unreliable `zmx run <parent> pwd` path
    # (whose stdout over `ssh -T` is the remote-shell echo / zmx binary
    # path, not the PTY output — see e2e scenario 10 investigation).
    # If the pid is missing or readlink fails (non-Linux host, session
    # gone), fall back to the remote home (zmx's default) — do not block.
    local _parent_pid="" _parent_cwd=""
    _parent_pid="$( { ${(z)$(ghostty_zmx_notty_prefix "$prefix")} "$_remote_zmx list" ; } 2>/dev/null )"
    _parent_pid="$(print -r -- "$_parent_pid" | tr -d '\r' | awk -v n="$parent_session" '
      { for (i=1; i<=NF; i++) if ($i ~ "^name=" n "$") {
        for (j=i; j<=NF; j++) if ($j ~ /^pid=/) { sub(/^pid=/, "", $j); print $j; exit }
      } }')"
    if [[ "$_parent_pid" =~ ^[0-9]+$ ]]; then
      _parent_cwd="$( { ${(z)$(ghostty_zmx_notty_prefix "$prefix")} "readlink /proc/$_parent_pid/cwd" ; } 2>/dev/null )"
      _parent_cwd="$(print -r -- "$_parent_cwd" | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    fi
    local _remote_cmd
    if [[ "$_parent_cwd" == /* ]]; then
      _ghostty_zmx_debug "inherit cwd host=$host session=$session parent=$parent_session pid=$_parent_pid cwd=$_parent_cwd"
      _remote_cmd="cd -P '$_parent_cwd' && $_remote_zmx attach $session"
    else
      _ghostty_zmx_debug "inherit cwd host=$host session=$session parent=$parent_session pid=${_parent_pid:-unknown} cwd=unknown (using default)"
      _remote_cmd="$_remote_zmx attach $session"
    fi
    exec "$wrapper_path" projection --host "$host" --workspace "$workspace_id" --session "$session" -- "${notty_prefix[@]}" "$_remote_cmd" <"$cur_tty" >"$cur_tty" 2>&1
  done < "$projections_file"
  return 1
}
