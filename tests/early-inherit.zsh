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

print "early-inherit tests passed"
