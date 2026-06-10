#!/bin/zsh
set -u
setopt NULL_GLOB

REPO="/Users/piercarlocadoppi/Documents/open-source/github/cad0p/ghostty-zmx"
CFG="$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"
INST_DIR="$HOME/.config/ghostty-zmx"
INST_MANAGER="$INST_DIR/session-manager.zsh"
INST_UNINSTALL="$INST_DIR/uninstall.sh"
RUN_ID="ghostty-zmx-e2e-rerun-$(date +%s)"
TMPROOT="${TMPDIR:-/tmp}/${RUN_ID}"
DATA_HOME="$TMPROOT/data"
STATE_HOME="$TMPROOT/state"
ZMX_DIR="/tmp/gzmx-$$"
export ZMX_DIR
LOG="$TMPROOT/e2e.log"
REPORT="$REPO/features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-results.md"
CFG_BAK="$TMPROOT/config.ghostty.bak"
MANAGER_BAK="$TMPROOT/session-manager.zsh.bak"
UNINSTALL_BAK="$TMPROOT/uninstall.sh.bak"
ORIG_CFG_HASH=""
ORIG_MANAGER_HASH=""
ORIG_UNINSTALL_HASH=""
RESTORED=0
mkdir -p "$TMPROOT" "$DATA_HOME" "$STATE_HOME" "$INST_DIR"
: > "$LOG"

log() { print -r -- "$*" | tee -a "$LOG"; }
section() { log "\n===== $* ====="; }
hash_file() { [[ -f "$1" ]] && shasum -a 256 "$1" | awk '{print $1}' || print MISSING; }

restore_real_files() {
  [[ "$RESTORED" == 1 ]] && return 0
  RESTORED=1
  if [[ -f "$CFG_BAK" ]]; then cp -p "$CFG_BAK" "$CFG"; fi
  if [[ -f "$MANAGER_BAK" ]]; then cp -p "$MANAGER_BAK" "$INST_MANAGER"; else rm -f "$INST_MANAGER"; fi
  if [[ -f "$UNINSTALL_BAK" ]]; then cp -p "$UNINSTALL_BAK" "$INST_UNINSTALL"; else rm -f "$INST_UNINSTALL"; fi
  print -r -- "RESTORE config hash after=$(hash_file "$CFG") expected=$ORIG_CFG_HASH" >> "$LOG"
  print -r -- "RESTORE manager hash after=$(hash_file "$INST_MANAGER") expected=$ORIG_MANAGER_HASH" >> "$LOG"
  print -r -- "RESTORE uninstall hash after=$(hash_file "$INST_UNINSTALL") expected=$ORIG_UNINSTALL_HASH" >> "$LOG"
}
trap restore_real_files EXIT INT TERM

scenario_result() { log "SCENARIO_RESULT $1 $2 $3"; }

wait_windows_at_least() {
  local want="$1" max="${2:-30}" i out
  for i in $(seq 1 "$max"); do
    out=$(osascript -e 'tell application "Ghostty" to count of windows' 2>/dev/null || print 0)
    [[ "$out" =~ '^[0-9]+$' && "$out" -ge "$want" ]] && return 0
    sleep 1
  done
  return 1
}
wait_windows_exact() {
  local want="$1" max="${2:-30}" i out
  for i in $(seq 1 "$max"); do
    out=$(osascript -e 'tell application "Ghostty" to count of windows' 2>/dev/null || print 0)
    [[ "$out" =~ '^[0-9]+$' && "$out" -eq "$want" ]] && return 0
    sleep 1
  done
  return 1
}
sessions_file() { print -r -- "$DATA_HOME/sessions"; }
read_sessions() { [[ -f "$(sessions_file)" ]] && grep -E '^zmx-' "$(sessions_file)" || true; }
wait_sessions_count() {
  local want="$1" max="${2:-40}" i count
  for i in $(seq 1 "$max"); do
    count=$(read_sessions | wc -l | tr -d ' ')
    [[ "$count" -ge "$want" ]] && return 0
    sleep 1
  done
  return 1
}
wait_session_gone() {
  local s="$1" max="${2:-20}" i
  for i in $(seq 1 "$max"); do
    if ! zmx list --short 2>/dev/null | grep -qxF "$s" && ! read_sessions | grep -qxF "$s"; then return 0; fi
    sleep 1
  done
  return 1
}
wait_all_managed_gone() {
  local max="${1:-20}" i count live
  for i in $(seq 1 "$max"); do
    count=$(read_sessions | wc -l | tr -d ' ')
    live=$(zmx list --short 2>/dev/null | grep -Fxf <(read_sessions) 2>/dev/null | wc -l | tr -d ' ')
    [[ "$count" -eq 0 && "$live" -eq 0 ]] && return 0
    sleep 1
  done
  return 1
}
layout_report() {
  osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "Ghostty"
  set report to "windows=" & (count of windows)
  repeat with w in windows
    set report to report & linefeed & "window=" & (id of w as string) & " tabs=" & (count of tabs of w)
    repeat with tb in tabs of w
      set report to report & linefeed & "  tab=" & (id of tb as string) & " terms=" & (count of terminals of tb)
    end repeat
  end repeat
  return report
end tell
APPLESCRIPT
}
state_dump() {
  log "-- layout --"; layout_report | tee -a "$LOG"
  log "-- sessions file --"; read_sessions | tee -a "$LOG"
  log "-- zmx list managed --"; zmx list 2>/dev/null | grep 'name=zmx-' | tee -a "$LOG" || true
  log "-- debug tail --"; tail -n 60 "$STATE_HOME/debug.log" 2>/dev/null | tee -a "$LOG" || true
}
quit_ghostty() {
  osascript -e 'tell application "Ghostty" to quit' >> "$LOG" 2>&1 || true
  for i in $(seq 1 20); do pgrep -x ghostty >/dev/null 2>&1 || return 0; sleep 1; done
  return 1
}
open_ghostty_clean() {
  open -a Ghostty >> "$LOG" 2>&1 || return 1
  wait_windows_at_least 1 30 || return 1
  wait_sessions_count 1 40 || return 1
}
cmd_w() {
  osascript <<'APPLESCRIPT' >> "$LOG" 2>&1
activate application "Ghostty"
tell application "System Events" to keystroke "w" using command down
APPLESCRIPT
}
new_split() {
  osascript <<'APPLESCRIPT' >> "$LOG" 2>&1
tell application "Ghostty"
  set cfg to new surface configuration
  set t to focused terminal of selected tab of front window
  split t direction right with configuration cfg
end tell
APPLESCRIPT
}
new_tab() {
  osascript <<'APPLESCRIPT' >> "$LOG" 2>&1
tell application "Ghostty"
  set cfg to new surface configuration
  set w to front window
  set tb to new tab in w with configuration cfg
  set selected tab of w to tb
end tell
APPLESCRIPT
}
new_window() {
  osascript <<'APPLESCRIPT' >> "$LOG" 2>&1
tell application "Ghostty"
  set cfg to new surface configuration
  set w to new window with configuration cfg
end tell
APPLESCRIPT
}
start_fresh() {
  quit_ghostty || true
  rm -rf "$DATA_HOME" "$STATE_HOME"
  mkdir -p "$DATA_HOME" "$STATE_HOME"
  zmx list --short 2>/dev/null | while read -r s; do zmx kill "$s" >/dev/null 2>&1 || true; done
  open_ghostty_clean
}
print_marker() {
  local session="$1" marker="$2"
  printf '\r\n%s\r\n' "$marker" | zmx print "$session" >> "$LOG" 2>&1
}

ORIG_CFG_HASH="$(hash_file "$CFG")"
ORIG_MANAGER_HASH="$(hash_file "$INST_MANAGER")"
ORIG_UNINSTALL_HASH="$(hash_file "$INST_UNINSTALL")"
cp -p "$CFG" "$CFG_BAK"
[[ -f "$INST_MANAGER" ]] && cp -p "$INST_MANAGER" "$MANAGER_BAK"
[[ -f "$INST_UNINSTALL" ]] && cp -p "$INST_UNINSTALL" "$UNINSTALL_BAK"
install -m 0644 "$REPO/session-manager.zsh" "$INST_MANAGER"
install -m 0755 "$REPO/uninstall.sh" "$INST_UNINSTALL"
python3 - "$CFG" "$DATA_HOME" "$STATE_HOME" "$ZMX_DIR" <<'PY'
import pathlib, re, sys
cfg=pathlib.Path(sys.argv[1]); data=sys.argv[2]; state=sys.argv[3]; zmx_dir=sys.argv[4]
text=cfg.read_text()
block=f"""# BEGIN ghostty-zmx
# Managed by ghostty-zmx. TEMPORARY E2E override; restored byte-for-byte by trap.
env = GHOSTTY_ZMX_AUTO_ATTACH=1
env = GHOSTTY_ZMX_DEBUG=1
env = GHOSTTY_ZMX_DATA_HOME={data}
env = GHOSTTY_ZMX_STATE_HOME={state}
env = ZMX_DIR={zmx_dir}
env = GHOSTTY_ZMX_REAPER_INTERVAL=1
env = GHOSTTY_ZMX_ZERO_WINDOWS_GRACE=3
env = GHOSTTY_ZMX_RESTORE_STEP_DELAY=1
window-save-state = never
confirm-close-surface = false
# END ghostty-zmx"""
pat=re.compile(r"(?ms)^# BEGIN ghostty-zmx$.*?^# END ghostty-zmx$")
text=pat.sub(block,text,count=1) if pat.search(text) else text.rstrip()+"\n\n"+block+"\n"
cfg.write_text(text)
PY
log "RUN_ID=$RUN_ID"
log "CONFIG_HASH_BEFORE=$ORIG_CFG_HASH"
log "CONFIG_HASH_DURING=$(hash_file "$CFG")"
log "MANAGER_HASH_BEFORE=$ORIG_MANAGER_HASH"
log "MANAGER_HASH_DURING=$(hash_file "$INST_MANAGER")"
log "UNINSTALL_HASH_BEFORE=$ORIG_UNINSTALL_HASH"
log "UNINSTALL_HASH_DURING=$(hash_file "$INST_UNINSTALL")"
log "DATA_HOME=$DATA_HOME"
log "STATE_HOME=$STATE_HOME"
log "ZMX_DIR=$ZMX_DIR"

quit_ghostty || true

section "Scenario 1 Cmd-Q restore"
if start_fresh; then
  new_split; wait_sessions_count 2 30 || true
  new_tab; wait_sessions_count 3 30 || true
  new_window; wait_sessions_count 4 30 || true
  before_layout=$(layout_report); log "before_layout:\n$before_layout"
  typeset -a s1; s1=(${(f)"$(read_sessions)"})
  for s in $s1; do print_marker "$s" "${RUN_ID}-cmdq-$s" || true; done
  quit_ghostty || log "quit_ghostty timed out"
  sleep 5
  remaining=$(for s in $s1; do zmx list --short | grep -qxF "$s" && print "$s"; done | wc -l | tr -d ' ')
  open -a Ghostty >> "$LOG" 2>&1
  wait_windows_at_least 1 30 || true
  sleep 8
  after_layout=$(layout_report); log "after_layout:\n$after_layout"
  hist_ok=1; for s in $s1; do zmx history "$s" | grep -qF "${RUN_ID}-cmdq-$s" || hist_ok=0; done
  [[ "$remaining" -eq "${#s1}" && "$hist_ok" -eq 1 ]] && scenario_result cmd-q-restore PASS "sessions_remain=$remaining markers_in_history=1" || scenario_result cmd-q-restore FAIL "sessions_remain=$remaining expected=${#s1} markers_ok=$hist_ok"
  state_dump
else scenario_result cmd-q-restore FAIL "could not start fresh Ghostty"; fi

section "Scenario 2 Working-directory inheritance"
if start_fresh; then
  base=$(read_sessions | tail -n 1)
  testdir="/tmp/${RUN_ID}-cwd"; mkdir -p "$testdir"
  printf 'cd %q\rpwd\r' "$testdir" | zmx send "$base" >> "$LOG" 2>&1 || true
  sleep 2
  new_split; wait_sessions_count 2 20 || true; split_s=$(read_sessions | tail -n 1)
  new_tab; wait_sessions_count 3 20 || true; tab_s=$(read_sessions | tail -n 1)
  new_window; wait_sessions_count 4 20 || true; win_s=$(read_sessions | tail -n 1)
  norm="$testdir"; [[ "$norm" == /tmp/* ]] && norm="/private${norm}"
  ok=1; for s in "$split_s" "$tab_s" "$win_s"; do zmx list | grep -F "name=$s" | grep -Eq "start_dir=($testdir|$norm)" || ok=0; done
  [[ $ok -eq 1 ]] && scenario_result working-directory-inheritance PASS "testdir=$testdir norm=$norm" || scenario_result working-directory-inheritance FAIL "start_dir mismatch testdir=$testdir norm=$norm split=$split_s tab=$tab_s win=$win_s"
  state_dump
else scenario_result working-directory-inheritance FAIL "could not start fresh Ghostty"; fi

section "Scenario 3 Pane close cleanup and unmanaged preserved"
if start_fresh; then
  unmanaged="unmanaged-pane"
  zmx run "$unmanaged" -d sleep 120 >> "$LOG" 2>&1 || true
  new_split; wait_sessions_count 2 20 || true; pane_s=$(read_sessions | tail -n 1)
  cmd_w
  if wait_session_gone "$pane_s" 20 && zmx list --short | grep -qxF "$unmanaged"; then scenario_result pane-close-cleanup PASS "closed=$pane_s unmanaged_alive=$unmanaged"; else scenario_result pane-close-cleanup FAIL "closed=$pane_s still_present_or_unmanaged_missing"; fi
  zmx kill "$unmanaged" >/dev/null 2>&1 || true
  state_dump
else scenario_result pane-close-cleanup FAIL "could not start fresh Ghostty"; fi

section "Scenario 4 Window close cleanup"
if start_fresh; then
  first=$(read_sessions | tail -n 1)
  new_window; wait_sessions_count 2 20 || true; win_s=$(read_sessions | tail -n 1)
  cmd_w
  if wait_session_gone "$win_s" 20 && zmx list | grep -F "name=$first" | grep -q 'clients=1'; then scenario_result window-close-cleanup PASS "closed_window_session=$win_s open_session=$first"; else scenario_result window-close-cleanup FAIL "closed_window_session=$win_s not_cleaned_or_first_not_attached"; fi
  state_dump
else scenario_result window-close-cleanup FAIL "could not start fresh Ghostty"; fi

section "Scenario 5 Close all windows cleanup"
if start_fresh; then
  new_window; wait_sessions_count 2 20 || true; old_sessions=(${(f)"$(read_sessions)"})
  cmd_w; wait_windows_exact 1 15 || true
  cmd_w; wait_windows_exact 0 15 || true
  running=$(osascript -e 'tell application "Ghostty" to running' 2>/dev/null || print false)
  wait_all_managed_gone 20 && cleanup_ok=1 || cleanup_ok=0
  open -a Ghostty >> "$LOG" 2>&1; wait_sessions_count 1 30 || true
  new_sessions=(${(f)"$(read_sessions)"})
  fresh_ok=1; for os in $old_sessions; do for ns in $new_sessions; do [[ "$os" == "$ns" ]] && fresh_ok=0; done; done
  [[ "$running" == true && $cleanup_ok -eq 1 && $fresh_ok -eq 1 ]] && scenario_result close-all-windows-cleanup PASS "running=$running old_count=${#old_sessions} new_count=${#new_sessions}" || scenario_result close-all-windows-cleanup FAIL "running=$running cleanup_ok=$cleanup_ok fresh_ok=$fresh_ok"
  state_dump
else scenario_result close-all-windows-cleanup FAIL "could not start fresh Ghostty"; fi

section "Scenario 6 Cmd-Q does not clean"
if start_fresh; then
  new_window; wait_sessions_count 2 20 || true; q_sessions=(${(f)"$(read_sessions)"})
  quit_ghostty || true; sleep 5
  remain=0; for s in $q_sessions; do zmx list --short | grep -qxF "$s" && grep -qxF "$s" "$(sessions_file)" && remain=$((remain+1)); done
  open -a Ghostty >> "$LOG" 2>&1; wait_windows_at_least 1 30 || true; sleep 8
  wcnt=$(osascript -e 'tell application "Ghostty" to count of windows' 2>/dev/null || print 0)
  [[ "$remain" -eq "${#q_sessions}" && "$wcnt" -ge 2 ]] && scenario_result cmd-q-does-not-clean PASS "remain=$remain restored_windows=$wcnt" || scenario_result cmd-q-does-not-clean FAIL "remain=$remain expected=${#q_sessions} restored_windows=$wcnt"
  state_dump
else scenario_result cmd-q-does-not-clean FAIL "could not start fresh Ghostty"; fi

section "Scenario 7 Reboot scrollback simulation"
if start_fresh; then
  rb_s=$(read_sessions | tail -n 1); rb_marker="rb${$}"
  print_marker "$rb_s" "$rb_marker" || true
  for i in $(seq 1 10); do
    zmx history "$rb_s" 2>/dev/null | grep -qF "$rb_marker" && break
    sleep 1
  done
  quit_ghostty || true; sleep 5
  snap="$STATE_HOME/history/${rb_s}.txt"; [[ -s "$snap" ]] && snap_ok=1 || snap_ok=0
  zmx kill "$rb_s" >> "$LOG" 2>&1 || true
  open -a Ghostty >> "$LOG" 2>&1; wait_sessions_count 1 30 || true; sleep 6
  banner='[ghostty-zmx restored saved scrollback from a previous boot; process state was not restored]'
  zmx history "$rb_s" > "$TMPROOT/rb-history.txt" 2>>"$LOG" || true
  grep -qF "$banner" "$TMPROOT/rb-history.txt" && banner_ok=1 || banner_ok=0
  grep -qF "$rb_marker" "$TMPROOT/rb-history.txt" && marker_ok=1 || marker_ok=0
  grep -qF "fresh-session detection session=$rb_s exists=0" "$STATE_HOME/debug.log" && fresh_log=1 || fresh_log=0
  grep -qF "zmx print restored scrollback session=$rb_s" "$STATE_HOME/debug.log" && print_log=1 || print_log=0
  [[ $snap_ok -eq 1 && $banner_ok -eq 1 && $marker_ok -eq 1 && $fresh_log -eq 1 && $print_log -eq 1 ]] && scenario_result reboot-scrollback-simulation PASS "session=$rb_s snapshot=$snap" || scenario_result reboot-scrollback-simulation FAIL "session=$rb_s snap_ok=$snap_ok banner_ok=$banner_ok marker_ok=$marker_ok fresh_log=$fresh_log print_log=$print_log"
  state_dump
else scenario_result reboot-scrollback-simulation FAIL "could not start fresh Ghostty"; fi

section "Scenario 8 Unmanaged sessions are not reaped"
if start_fresh; then
  unmanaged="unmanaged-final"
  zmx run "$unmanaged" -d sleep 120 >> "$LOG" 2>&1 || true
  new_window; wait_sessions_count 2 20 || true
  cmd_w; wait_windows_exact 1 15 || true
  cmd_w; wait_windows_exact 0 15 || true
  sleep 5
  if zmx list --short | grep -qxF "$unmanaged"; then scenario_result unmanaged-not-reaped PASS "unmanaged_alive=$unmanaged"; else scenario_result unmanaged-not-reaped FAIL "unmanaged_missing=$unmanaged"; fi
  zmx kill "$unmanaged" >/dev/null 2>&1 || true
  state_dump
else scenario_result unmanaged-not-reaped FAIL "could not start fresh Ghostty"; fi

section "Final restore check"
restore_real_files
trap - EXIT INT TERM
FINAL_CFG_HASH="$(hash_file "$CFG")"
FINAL_MANAGER_HASH="$(hash_file "$INST_MANAGER")"
FINAL_UNINSTALL_HASH="$(hash_file "$INST_UNINSTALL")"
log "CONFIG_HASH_AFTER=$FINAL_CFG_HASH"
log "MANAGER_HASH_AFTER=$FINAL_MANAGER_HASH"
log "UNINSTALL_HASH_AFTER=$FINAL_UNINSTALL_HASH"
[[ "$FINAL_CFG_HASH" == "$ORIG_CFG_HASH" ]] && log CONFIG_RESTORE_BYTE_FOR_BYTE=PASS || log CONFIG_RESTORE_BYTE_FOR_BYTE=FAIL
[[ "$FINAL_MANAGER_HASH" == "$ORIG_MANAGER_HASH" ]] && log MANAGER_RESTORE_BYTE_FOR_BYTE=PASS || log MANAGER_RESTORE_BYTE_FOR_BYTE=FAIL
[[ "$FINAL_UNINSTALL_HASH" == "$ORIG_UNINSTALL_HASH" ]] && log UNINSTALL_RESTORE_BYTE_FOR_BYTE=PASS || log UNINSTALL_RESTORE_BYTE_FOR_BYTE=FAIL

{
  print '# E2E rerun supervised results'
  print
  print '```text'
  grep -E '^(RUN_ID|CONFIG_|MANAGER_|UNINSTALL_|DATA_HOME|STATE_HOME|ZMX_DIR|SCENARIO_RESULT|RAW_LOG)' "$LOG" || true
  print '```'
  print
  print 'Full log:' "$LOG"
} > "$REPORT"
log "RAW_LOG=$LOG"
log "REPORT=$REPORT"
print -r -- "$REPORT"
