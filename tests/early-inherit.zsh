#!/bin/zsh
set -eu

repo_dir="${0:A:h:h}"
cd "$repo_dir"

fail() {
  print -u2 "early-inherit test failed: $*"
  exit 1
}

# Lib double-source guard: sourcing twice is safe and leaves functions defined.
(
  source ./session-manager-lib.zsh
  [[ "${_GHOSTTY_ZMX_LIB_SOURCED:-}" == "1" ]] || fail "lib guard not set after first source"
  source ./session-manager-lib.zsh
  whence -w ghostty_zmx_has_tty_capability >/dev/null 2>&1 || fail "capability function missing after second source"
  whence -w ghostty_zmx_inherit_remote_context_if_any >/dev/null 2>&1 || fail "inherit function missing after second source"
) || exit 1

# Capability probe fails closed when not in Ghostty, without invoking osascript.
(
  unset TERM_PROGRAM GHOSTTY_RESOURCES_DIR || true
  source ./session-manager-lib.zsh
  if ghostty_zmx_has_tty_capability; then
    fail "capability unexpectedly succeeded outside Ghostty"
  fi
) || exit 1

# Early file is a no-op outside Ghostty.
(
  unset TERM_PROGRAM GHOSTTY_RESOURCES_DIR GHOSTTY_ZMX_EARLY_INHERIT_RAN || true
  export GHOSTTY_ZMX_AUTO_ATTACH=1
  source ./session-manager-early.zsh
  [[ -z "${GHOSTTY_ZMX_EARLY_INHERIT_RAN:-}" ]] || fail "early marker set outside Ghostty"
) || exit 1

# Early file is a no-op inside projection surfaces (prevents cascades).
(
  export TERM_PROGRAM=ghostty
  export GHOSTTY_ZMX_AUTO_ATTACH=1
  export GHOSTTY_ZMX_PROJECTION=1
  unset GHOSTTY_ZMX_EARLY_INHERIT_RAN GHOSTTY_RESOURCES_DIR || true
  source ./session-manager-early.zsh
  [[ -z "${GHOSTTY_ZMX_EARLY_INHERIT_RAN:-}" ]] || fail "early marker set inside projection"
) || exit 1

# Early file is a no-op when auto attach is disabled.
(
  export TERM_PROGRAM=ghostty
  export GHOSTTY_ZMX_AUTO_ATTACH=0
  unset GHOSTTY_ZMX_EARLY_INHERIT_RAN GHOSTTY_ZMX_PROJECTION GHOSTTY_RESOURCES_DIR || true
  source ./session-manager-early.zsh
  [[ -z "${GHOSTTY_ZMX_EARLY_INHERIT_RAN:-}" ]] || fail "early marker set when auto attach disabled"
) || exit 1

# When the capability probe succeeds but surface identity is unavailable, the
# early marker is NOT set. This is intentional: let the later ~/.zshrc manager
# retry the legacy inherit path rather than incorrectly falling through to a
# local zmx pane.
(
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  cat > "$tmp/osascript" <<'EOS'
#!/bin/sh
# Capability probe succeeds (rc=0) but identity lookup receives unusable output.
exit 0
EOS
  chmod +x "$tmp/osascript"
  export PATH="$tmp:$PATH"
  export TERM_PROGRAM=ghostty
  export GHOSTTY_RESOURCES_DIR=/Applications/Ghostty.app/Contents/Resources/ghostty
  export GHOSTTY_ZMX_AUTO_ATTACH=1
  export GHOSTTY_ZMX_EARLY_INHERIT_ATTEMPTS=1
  export GHOSTTY_ZMX_EARLY_INHERIT_DELAY=0
  export TTY=/dev/ttys999
  unset GHOSTTY_ZMX_EARLY_INHERIT_RAN GHOSTTY_ZMX_PROJECTION || true
  source ./session-manager-early.zsh
  [[ -z "${GHOSTTY_ZMX_EARLY_INHERIT_RAN:-}" ]] || fail "early marker set even though identity was unavailable"
) || exit 1

# `ssh -T` must be inserted before the destination, not appended after it
# where OpenSSH treats it as the remote command (`ssh host -T`).
(
  source ./session-manager-lib.zsh
  [[ "$(ghostty_zmx_notty_prefix 'ssh myhost')" == "ssh -T myhost" ]] || fail "ssh -T inserted after destination"
  [[ "$(ghostty_zmx_notty_prefix 'ssh -F /tmp/cfg myhost')" == "ssh -F /tmp/cfg -T myhost" ]] || fail "ssh -F option arg confused destination detection"
  [[ "$(ghostty_zmx_notty_prefix 'ssh -t -p 2222 myhost')" == "ssh -p 2222 -T myhost" ]] || fail "ssh -t removal/-T insertion failed with port option"
  [[ "$(ghostty_zmx_notty_prefix 'tsh ssh -t myhost')" == "tsh ssh myhost" ]] || fail "tsh notty prefix unexpectedly inserted -T"
) || exit 1

# If the wrapper is missing/non-executable, inherit must fail before mutating
# remote layout state or setting the early marker. This makes partial installs
# fail open to the later ~/.zshrc path rather than leaving orphaned server rows.
(
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  export GHOSTTY_ZMX_DATA_HOME="$tmp/data"
  export GHOSTTY_ZMX_INSTALL_DIR="$tmp/install-missing"
  mkdir -p "$GHOSTTY_ZMX_DATA_HOME"
  print -r -- $'h\ttsh\tzmx 0.6.0\tactive\t/tmp/should-not-run' > "$GHOSTTY_ZMX_DATA_HOME/remote-hosts"
  print -r -- $'h\tdeadbeef\tgzr-deadbeef-cafebabe-abc123-def456\t/dev/ttys999\t123\tattached\t1\taaaa\tbbbb' > "$GHOSTTY_ZMX_DATA_HOME/remote-projections"
  unset GHOSTTY_ZMX_EARLY_INHERIT_RAN || true
  source ./session-manager-lib.zsh
  if ghostty_zmx_inherit_remote_context_if_any 'aaaa bbbb cccc 123 /dev/ttys999'; then
    fail "inherit unexpectedly succeeded with missing wrapper"
  fi
  [[ -z "${GHOSTTY_ZMX_EARLY_INHERIT_RAN:-}" ]] || fail "early marker set despite missing wrapper"
) || exit 1

# If the target tty vanished before exec, inherit must fail before remote layout
# mutation / marker set so ~/.zshrc can retry the legacy path.
(
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  export GHOSTTY_ZMX_DATA_HOME="$tmp/data"
  export GHOSTTY_ZMX_INSTALL_DIR="$tmp/install"
  mkdir -p "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_INSTALL_DIR"
  : > "$GHOSTTY_ZMX_INSTALL_DIR/ghostty-zmx"
  chmod +x "$GHOSTTY_ZMX_INSTALL_DIR/ghostty-zmx"
  print -r -- $'h\ttsh\tzmx 0.6.0\tactive\t/tmp/should-not-run' > "$GHOSTTY_ZMX_DATA_HOME/remote-hosts"
  print -r -- $'h\tdeadbeef\tgzr-deadbeef-cafebabe-abc123-def456\t/dev/ghostty-zmx-missing-tty\t123\tattached\t1\taaaa\tbbbb' > "$GHOSTTY_ZMX_DATA_HOME/remote-projections"
  unset GHOSTTY_ZMX_EARLY_INHERIT_RAN || true
  source ./session-manager-lib.zsh
  if ghostty_zmx_inherit_remote_context_if_any 'aaaa bbbb cccc 123 /dev/ghostty-zmx-missing-tty'; then
    fail "inherit unexpectedly succeeded with vanished tty"
  fi
  [[ -z "${GHOSTTY_ZMX_EARLY_INHERIT_RAN:-}" ]] || fail "early marker set despite vanished tty"
) || exit 1

# The marker must never be exported by ghostty-zmx. Exporting it would leak into
# nested shells and make later Ghostty surfaces skip their own early-inherit
# checks incorrectly.
if grep -R "export GHOSTTY_ZMX_EARLY_INHERIT_RAN" session-manager*.zsh >/dev/null 2>&1; then
  fail "early marker is exported somewhere"
fi

# Early file idempotence: if the marker is already set, sourcing is a no-op.
(
  export TERM_PROGRAM=ghostty
  export GHOSTTY_ZMX_AUTO_ATTACH=1
  export GHOSTTY_ZMX_EARLY_INHERIT_RAN=1
  unset GHOSTTY_ZMX_PROJECTION GHOSTTY_RESOURCES_DIR || true
  source ./session-manager-early.zsh
  [[ "${GHOSTTY_ZMX_EARLY_INHERIT_RAN:-}" == "1" ]] || fail "early marker changed during idempotent no-op"
) || exit 1

# The tty helper's result is interpolated into AppleScript, so adversarial TTY
# env values that start with /dev/ but contain quotes/newlines must be rejected.
(
  source ./session-manager-lib.zsh
  export TTY=$'/dev/ttys999" then return "owned\n'
  if _ghostty_zmx_shell_tty >/dev/null 2>&1; then
    fail "malformed TTY accepted by shell_tty helper"
  fi
) || exit 1

# zsh function definitions are global even inside functions/emulate scopes. The
# accept-line widget must not define a generic `rand()` helper that could clobber
# (or be clobbered by) a user/plugin function and corrupt generated gzr names.
if grep -n '^[[:space:]]*rand()' session-manager.zsh >/dev/null 2>&1; then
  fail "session-manager defines global rand() helper"
fi

# Transactional ordering (e2e round 6): the remote `add` must be under the
# per-session lock, and any failure between remote `add` and exec must roll
# the remote row back with `transition <session> deleted` so a later poller
# cannot resurrect an orphan projection.
#
# Static assertion: the source order in the lib is (lock acquire) -> (remote
# add) -> (local write) -> (exec re-check) -> (exec).
(
  file=session-manager-lib.zsh
  add_line=$(grep -n '"$helper" add "$workspace_id"' "$file" | head -1 | cut -d: -f1)
  lock_line=$(grep -n 'mkdir "$inh_lock"' "$file" | head -1 | cut -d: -f1)
  write_line=$(grep -n 'ghostty_zmx_write_projection_row "$host" "$workspace_id"' "$file" | head -1 | cut -d: -f1)
  rollback_line=$(grep -n '_gzmx_inherit_rollback' "$file" | head -1 | cut -d: -f1)
  transition_line=$(grep -n '"$helper" transition "$session" deleted' "$file" | head -1 | cut -d: -f1)
  [[ -n "$lock_line" && -n "$add_line" && -n "$write_line" ]] || fail "expected inherit steps not found in $file"
  (( lock_line < add_line )) || fail "remote add ($add_line) is not under the per-session lock ($lock_line)"
  (( add_line < write_line )) || fail "remote add ($add_line) does not precede local write ($write_line)"
  [[ -n "$rollback_line" && -n "$transition_line" ]] || fail "rollback path missing (rollback_line=$rollback_line transition_line=$transition_line)"
) || exit 1

# Behavior test: if the local projections-file lock cannot be acquired after the
# remote `add` succeeds, inherit must (1) return failure, (2) fire the remote
# rollback (`transition <session> deleted`), and (3) NOT set the early marker.
(
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  export GHOSTTY_ZMX_DATA_HOME="$tmp/data"
  export GHOSTTY_ZMX_STATE_HOME="$tmp/state"
  export GHOSTTY_ZMX_INSTALL_DIR="$tmp/install"
  mkdir -p "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME" "$GHOSTTY_ZMX_INSTALL_DIR" "$tmp/bin"
  : > "$GHOSTTY_ZMX_INSTALL_DIR/ghostty-zmx"; chmod +x "$GHOSTTY_ZMX_INSTALL_DIR/ghostty-zmx"

  # Fake `ssh` on PATH that records every call and reports success for add.
  # The lib's notty_prefix expands to `ssh -T host` so `ssh` is argv[0].
  cat > "$tmp/bin/ssh" <<EOS
#!/bin/sh
printf '%s\n' "\$*" >> "$tmp/ssh-calls"
exit 0
EOS
  chmod +x "$tmp/bin/ssh"
  export PATH="$tmp/bin:$PATH"

  # Point the projection prefix at our fake `ssh host`. The lib will insert -T.
  print -r -- $'h\tssh\tzmx 0.6.0\tactive\tssh h' > "$GHOSTTY_ZMX_DATA_HOME/remote-hosts"
  # Parent projection row: attached, on the current shell's window/tab.
  print -r -- $'h\tdeadbeef\tgzr-deadbeef-cafebabe-abc123-def456\t/dev/ttys000\t123\tattached\t1\taaaa\tbbbb' > "$GHOSTTY_ZMX_DATA_HOME/remote-projections"

  # Point cur_tty at a real, readable+writable device so the tty guard passes.
  real_tty="$(tty 2>/dev/null || echo /dev/null)"
  [[ -r "$real_tty" && -w "$real_tty" ]] || real_tty=/dev/null

  # Wedge the projections-file lock so ghostty_zmx_write_projection_row cannot
  # acquire it and returns failure (rc=1). This is the branch that must trigger
  # the remote rollback.
  proj_file="$GHOSTTY_ZMX_DATA_HOME/remote-projections"
  mkdir -p "$proj_file.lock"

  unset GHOSTTY_ZMX_EARLY_INHERIT_RAN || true
  source ./session-manager-lib.zsh

  identity="aaaa bbbb cccc 123 $real_tty"
  if ghostty_zmx_inherit_remote_context_if_any "$identity"; then
    fail "inherit unexpectedly succeeded despite wedged local write lock"
  fi
  [[ -z "${GHOSTTY_ZMX_EARLY_INHERIT_RAN:-}" ]] || fail "early marker set even though local write failed"
  # The fake ssh must have been called twice: once for `add`, once for the
  # rollback `transition <session> deleted`.
  [[ -f "$tmp/ssh-calls" ]] || fail "fake ssh never invoked; add call missing"
  grep -q ' add deadbeef ' "$tmp/ssh-calls" || fail "remote add was not called"
  grep -q 'transition gzr-deadbeef-.* deleted' "$tmp/ssh-calls" || fail "remote rollback (transition deleted) was not called"

  # Cleanup wedged lock so the trap can rm -rf cleanly.
  rmdir "$proj_file.lock" 2>/dev/null || true
) || exit 1

# Projection-row writes must propagate fs/mv failures. A false success here
# would make inherit skip its remote rollback path and leave orphaned server rows.
(
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  export GHOSTTY_ZMX_DATA_HOME="$tmp/data"
  source ./session-manager-lib.zsh
  mv() { return 99 }
  if ghostty_zmx_write_projection_row h w s /dev/ttys1 123 opening win tab; then
    fail "projection row write succeeded despite mv failure"
  fi
) || exit 1

print "early-inherit tests passed"
