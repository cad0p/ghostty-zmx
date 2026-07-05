#!/usr/bin/env zsh
# Clean up Ghostty-tip E2E leftovers after normal or interrupted runs.
#
# Local cleanup is conservative: it removes disposable /tmp/gzmx-e2e-* state,
# kills Ghostty-tip processes, kills pollers/reapers tied to those tmpdirs, and
# kills local zmx sessions listed in the disposable sessions files.
#
# Remote cleanup runs only when GZMX_E2E_EXTERNAL_FIXTURE=1 or when the Docker
# fixture ssh config exists. Use a dedicated test host: remote cleanup removes
# gzr-* sessions and remote-layout state on the fixture.
set -u

emulate -L zsh
setopt no_sh_word_split null_glob

local ghostty_app="${GHOSTTY_APP_NAME:-Ghostty-tip}"
local ghostty_bundle="/Applications/${ghostty_app}.app"
local ghostty_bin="${GHOSTTY_BIN:-$ghostty_bundle/Contents/MacOS/ghostty}"
local zmx_bin="${GZMX_E2E_LOCAL_ZMX:-zmx}"
local tmpdirs=(/tmp/gzmx-e2e-*)
local sessions=()
local d f s

for d in "${tmpdirs[@]}"; do
  f="$d/data/sessions"
  [[ -r "$f" ]] || continue
  while IFS= read -r s; do
    [[ "$s" == zmx-* ]] && sessions+=("$s")
  done < "$f"
done

if (( ${#sessions} > 0 )); then
  for s in "${sessions[@]}"; do
    "$zmx_bin" kill "$s" >/dev/null 2>&1 || true
  done
fi

if command -v ps >/dev/null 2>&1; then
  local -a pids
  pids=("${(@f)$(ps -ax -o pid=,command= 2>/dev/null | awk -v bin="$ghostty_bin" '
    $0 ~ bin { print $1; next }
    $0 ~ /\/tmp\/gzmx-e2e-[^ ]*\/(data|state)/ { print $1; next }
    $0 ~ /\/tmp\/gzmx-e2e-[^ ]*/ { print $1; next }
  ')}")
  if (( ${#pids} > 0 )); then
    kill "${pids[@]}" >/dev/null 2>&1 || true
    sleep 1
    kill -9 "${pids[@]}" >/dev/null 2>&1 || true
  fi
fi

rm -rf /tmp/gzmx-e2e-* 2>/dev/null || true

cleanup_remote() {
  emulate -L zsh
  local ssh_config="$1" host="$2" home="$3"
  [[ -n "$ssh_config" && -n "$host" && -n "$home" ]] || return 0
  ssh -F "$ssh_config" "$host" "
    zmx_bin='$home/.local/bin/zmx'
    [[ -x \"\$zmx_bin\" ]] || zmx_bin=zmx
    for session in \$(\"\$zmx_bin\" list 2>/dev/null | sed -n 's/.*name=\\(gzr-[A-Za-z0-9-]*\\).*/\\1/p'); do
      \"\$zmx_bin\" kill \"\$session\" >/dev/null 2>&1 || true
    done
    rm -rf ~/.local/share/ghostty-zmx/remote-layout ~/.local/share/ghostty-zmx/remote-layout.rev ~/.local/share/ghostty-zmx/remote-layout.lock
  " >/dev/null 2>&1 || true
}

if [[ "${GZMX_E2E_EXTERNAL_FIXTURE:-0}" == "1" || -n "${GZMX_E2E_SSH_COMMAND:-}" ]]; then
  local target="${GZMX_E2E_FIXTURE_HOST:-${GZMX_E2E_EXTERNAL_HOST:-}}"
  if [[ -z "$target" && -n "${GZMX_E2E_SSH_COMMAND:-}" ]]; then
    local -a ssh_cmd
    ssh_cmd=(${(z)GZMX_E2E_SSH_COMMAND})
    target="${ssh_cmd[-1]:-}"
  fi
  local target_host="$target" target_user="${GZMX_E2E_FIXTURE_USER:-}"
  if [[ "$target" == *@* ]]; then
    target_user="${target%%@*}"
    target_host="${target#*@}"
  fi
  local ssh_config
  ssh_config="$(mktemp /tmp/gzmx-e2e-cleanup-sshconfig-XXXXXX)"
  {
    print -r -- "Include ${GZMX_E2E_EXTERNAL_SSH_INCLUDE:-$HOME/.ssh/config}"
    print -r -- "Host $target_host"
    print -r -- "  HostName ${GZMX_E2E_EXTERNAL_HOST:-$target_host}"
    [[ -n "$target_user" ]] && print -r -- "  User $target_user"
    print -r -- "  StrictHostKeyChecking no"
    print -r -- "  UserKnownHostsFile /dev/null"
    print -r -- "  LogLevel ERROR"
    [[ -n "${GZMX_E2E_EXTERNAL_SSH_CONFIG_APPEND:-}" ]] && print -r -- "$GZMX_E2E_EXTERNAL_SSH_CONFIG_APPEND"
  } > "$ssh_config"
  cleanup_remote "$ssh_config" "$target_host" "${GZMX_E2E_FIXTURE_HOME:-/home/${target_user:-gzmx}}"
  rm -f "$ssh_config"
elif [[ -r /tmp/ghostty-zmx-fixture-sshconfig ]]; then
  cleanup_remote /tmp/ghostty-zmx-fixture-sshconfig gzmx-fixture /home/gzmx
fi

if [[ "${GZMX_E2E_STOP_DOCKER:-1}" == "1" && -x e2e/fixtures/sshd/down.sh ]]; then
  e2e/fixtures/sshd/down.sh >/dev/null 2>&1 || true
fi

print "ghostty-zmx E2E cleanup complete."
