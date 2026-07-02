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

# Early file idempotence: if the marker is already set, sourcing is a no-op.
(
  export TERM_PROGRAM=ghostty
  export GHOSTTY_ZMX_AUTO_ATTACH=1
  export GHOSTTY_ZMX_EARLY_INHERIT_RAN=1
  unset GHOSTTY_ZMX_PROJECTION GHOSTTY_RESOURCES_DIR || true
  source ./session-manager-early.zsh
  [[ "${GHOSTTY_ZMX_EARLY_INHERIT_RAN:-}" == "1" ]] || fail "early marker changed during idempotent no-op"
) || exit 1

print "early-inherit tests passed"
