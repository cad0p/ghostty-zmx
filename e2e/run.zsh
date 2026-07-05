#!/usr/bin/env zsh
# Run the Ghostty-tip E2E scenarios.
#
# Defaults to the Docker sshd fixture. To use a real/external SSH fixture:
#
#   GZMX_E2E_EXTERNAL_FIXTURE=1 \
#   GZMX_E2E_SSH_COMMAND='ssh yachunt-agentsdesk' \
#   GZMX_E2E_FIXTURE_USER=yachunt \
#   GZMX_E2E_FIXTURE_HOME=/home/yachunt \
#   e2e/run.zsh
#
# The external host should be a disposable test host with ghostty-zmx
# server-side files installed. The scenarios reset remote-layout state and
# kill gzr-* sessions on that host.
set -eu

emulate -L zsh
setopt no_sh_word_split

local repo_dir="${0:A:h:h}"
cd "$repo_dir"

usage() {
  cat <<'EOF'
Usage: e2e/run.zsh [scenario ...]

Examples:
  e2e/run.zsh
  e2e/run.zsh e2e/01-ssh-handoff.zsh e2e/12-remote-split-multipane-cwd.zsh
  GZMX_E2E_EXTERNAL_FIXTURE=1 GZMX_E2E_SSH_COMMAND='ssh yachunt-agentsdesk' e2e/run.zsh

Environment:
  GHOSTTY_APP_NAME                 App name, default Ghostty-tip.
  GHOSTTY_BIN                      Binary path override.
  GZMX_E2E_EXTERNAL_FIXTURE=1      Use an existing SSH host instead of Docker.
  GZMX_E2E_SSH_COMMAND             Convenience form, e.g. 'ssh yachunt-agentsdesk'.
  GZMX_E2E_FIXTURE_HOST            Host alias used inside tests.
  GZMX_E2E_EXTERNAL_HOST           HostName for the generated ssh config.
  GZMX_E2E_FIXTURE_USER            Remote user, default gzmx.
  GZMX_E2E_FIXTURE_HOME            Remote home, default /home/$GZMX_E2E_FIXTURE_USER.
  GZMX_E2E_EXTERNAL_SSH_INCLUDE    ssh_config to Include, default ~/.ssh/config.
  GZMX_E2E_EXTERNAL_SSH_CONFIG_APPEND
                                     Extra ssh_config lines appended to the Host block.
  GZMX_E2E_EXTERNAL_INSTALL_SERVER=1
                                     Reinstall server-side files on external fixture.

Run e2e/cleanup.zsh after interrupted runs.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -n "${GZMX_E2E_SSH_COMMAND:-}" ]]; then
  local -a _ssh_cmd
  _ssh_cmd=(${(z)GZMX_E2E_SSH_COMMAND})
  [[ "${_ssh_cmd[1]:-}" == "ssh" ]] || { print -u2 "GZMX_E2E_SSH_COMMAND must start with ssh"; exit 2; }
  local _target="${_ssh_cmd[-1]}"
  [[ -n "$_target" && "$_target" != -* ]] || { print -u2 "could not determine host from GZMX_E2E_SSH_COMMAND"; exit 2; }
  local _host="$_target" _user=""
  if [[ "$_target" == *@* ]]; then
    _user="${_target%%@*}"
    _host="${_target#*@}"
  fi
  export GZMX_E2E_EXTERNAL_FIXTURE="${GZMX_E2E_EXTERNAL_FIXTURE:-1}"
  export GZMX_E2E_FIXTURE_HOST="${GZMX_E2E_FIXTURE_HOST:-$_host}"
  export GZMX_E2E_EXTERNAL_HOST="${GZMX_E2E_EXTERNAL_HOST:-$_host}"
  if [[ -n "$_user" && -z "${GZMX_E2E_FIXTURE_USER:-}" ]]; then
    export GZMX_E2E_FIXTURE_USER="$_user"
    export GZMX_E2E_EXTERNAL_SSH_CONFIG_APPEND="${GZMX_E2E_EXTERNAL_SSH_CONFIG_APPEND:-  User $_user}"
  fi
fi

export GHOSTTY_APP_NAME="${GHOSTTY_APP_NAME:-Ghostty-tip}"
export GHOSTTY_BIN="${GHOSTTY_BIN:-/Applications/${GHOSTTY_APP_NAME}.app/Contents/MacOS/ghostty}"

local -a scenarios
if [[ "$#" -gt 0 ]]; then
  scenarios=("$@")
else
  scenarios=(e2e/[0-9][0-9]-*.zsh)
fi

local scenario
for scenario in "${scenarios[@]}"; do
  print "===== $scenario ====="
  env -u TERM_PROGRAM -u GHOSTTY_RESOURCES_DIR zsh "$scenario"
done
