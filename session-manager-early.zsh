# ghostty-zmx early inherit hook for zsh.
# Source this file from ~/.zprofile, before ~/.zshrc.
#
# Native Ghostty splits of remote projection windows start a fresh local login
# shell. If that shell sources ~/.zshrc before ghostty-zmx execs the projection
# wrapper, prompt/plugins can emit terminal queries (OSC 11, CSI 6n) whose
# responses leak into the remote zmx pane's scrollback. This hook runs before
# ~/.zshrc, detects that specific inherited-remote case, and execs the
# projection wrapper immediately. Ordinary local panes fall through to ~/.zshrc.
#
# On Ghostty without the 1.4.0 tty/pid AppleScript capability, return silently:
# the full ~/.zshrc manager handles the frozen v0.1 fallback.

[[ "${TERM_PROGRAM:-}" == "ghostty" ]] || return 0
[[ "${GHOSTTY_ZMX_AUTO_ATTACH:-}" == "1" ]] || return 0
[[ "${GHOSTTY_ZMX_PROJECTION:-}" == "1" ]] && return 0
[[ "${GHOSTTY_ZMX_EARLY_INHERIT_RAN:-}" != "1" ]] || return 0
[[ "${GHOSTTY_ZMX_DISABLE_EARLY_INHERIT:-0}" != "1" ]] || return 0

# Source the shared lib from this file's install directory so the early hook and
# full manager travel together under ~/.config/ghostty-zmx/.
typeset _gzmx_early_self="${(%):-%N}"
typeset _gzmx_early_dir="${_gzmx_early_self:A:h}"
[[ -r "$_gzmx_early_dir/session-manager-lib.zsh" ]] || return 0
source "$_gzmx_early_dir/session-manager-lib.zsh"

# Capability gate: fail open on Ghostty 1.3.x / non-scriptable surfaces.
ghostty_zmx_has_tty_capability || return 0

# Once the early hook has the capability to make the inherit decision, mark it
# as definitive. The full ~/.zshrc manager skips its inherit block when this is
# set, avoiding a second late inherit attempt that would reintroduce ~/.zshrc
# query leakage.
export GHOSTTY_ZMX_EARLY_INHERIT_RAN=1

# AppleScript registration can lag shell startup slightly, mirroring the full
# manager's native-split inherit retry loop.
typeset _gzmx_early_identity="" _gzmx_early_attempt
for (( _gzmx_early_attempt=1; _gzmx_early_attempt<=8; _gzmx_early_attempt++ )); do
  _gzmx_early_identity="$(_ghostty_zmx_current_surface_identity 2>/dev/null)"
  [[ -n "$_gzmx_early_identity" ]] && break
  _ghostty_zmx_debug "early-inherit identity-not-ready attempt=$_gzmx_early_attempt"
  sleep 0.25
done

if [[ -n "$_gzmx_early_identity" ]]; then
  _ghostty_zmx_debug "early-inherit attempt=$_gzmx_early_attempt identity=$_gzmx_early_identity"
  ghostty_zmx_inherit_remote_context_if_any "$_gzmx_early_identity" || true
else
  _ghostty_zmx_debug "early-inherit no-identity after $_gzmx_early_attempt attempts"
fi

return 0
