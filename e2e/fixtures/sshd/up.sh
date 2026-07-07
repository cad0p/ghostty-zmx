#!/usr/bin/env zsh
# Bring up the ghostty-zmx plain-ssh E2E fixture.
# Builds the Ubuntu 24.04 sshd image, generates a one-time SSH key, runs the
# container on port 2222, writes an ssh config to /tmp, and installs the
# ghostty-zmx server-side files (session-manager.zsh, lib, remote-layout
# helper, terminfo) via ghostty-zmx install-server.
#
# Usage: e2e/fixtures/sshd/up.sh
# Idempotent: if the container is already running, reuses it.
# Teardown: e2e/fixtures/sshd/down.sh
set -eu

emulate -L zsh
setopt no_sh_word_split

local repo_dir="${0:A:h:h:h:h}"
local fixture_dir="${0:A:h}"
local image="ghostty-zmx-sshd-fixture:24.04"
local container="ghostty-zmx-sshd-fixture"
local port="${GHOSTTY_ZMX_FIXTURE_PORT:-2222}"
local key_dir="/tmp/ghostty-zmx-docker-fixture"
local ssh_config="/tmp/ghostty-zmx-fixture-sshconfig"

# 1. Generate a one-time ED25519 key for the fixture (no passphrase).
if [[ ! -f "$key_dir/id_ed25519" ]]; then
  mkdir -p "$key_dir"
  ssh-keygen -t ed25519 -N "" -f "$key_dir/id_ed25519" -C "ghostty-zmx-fixture" >/dev/null
  chmod 600 "$key_dir/id_ed25519"
fi
cp "$key_dir/id_ed25519.pub" "$fixture_dir/id_ed25519.pub"

# 2. Build the image (idempotent; Docker caches).
echo "==> Building $image (may take a minute on first run)..."
docker build -q -t "$image" "$fixture_dir" >/dev/null

# 3. Run the container on $port (reuse if already running).
if ! docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null | grep -q true; then
  echo "==> Starting container $container on port $port..."
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker run -d --name "$container" -p "${port}:22" "$image" >/dev/null
else
  echo "==> Container $container already running."
fi

# 4. Write the ssh config alias.
cat > "$ssh_config" <<EOF
Host gzmx-fixture
  HostName 127.0.0.1
  Port $port
  User gzmx
  IdentityFile $key_dir/id_ed25519
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  LogLevel ERROR
EOF
chmod 600 "$ssh_config"

# 5. Wait for sshd to accept connections.
echo "==> Waiting for sshd..."
local i
for (( i=1; i<=30; i++ )); do
  if ssh -F "$ssh_config" -o ConnectTimeout=2 gzmx-fixture 'true' 2>/dev/null; then
    echo "==> sshd is up."
    break
  fi
  sleep 1
  (( i == 30 )) && { echo "ERROR: sshd did not come up in 30s"; exit 1; }
done

# 6. Install ghostty-zmx server-side files by streaming the tarball over ssh
# (mirrors what `ghostty-zmx install-server` does, but without needing the
# laptop install to be present). Bundles install-server.sh + its siblings.
echo "==> Installing ghostty-zmx server-side files on the fixture..."
local tmpdir="/tmp/ghostty-zmx-server-install.$$"
ssh -F "$ssh_config" gzmx-fixture "
set -e
 tmpdir='$tmpdir'
rm -rf \"\$tmpdir\"
mkdir -p \"\$tmpdir\"
cd \"\$tmpdir\"
tar xzf -
./install-server.sh --yes
rc=$?
cd /
rm -rf \"\$tmpdir\"
exit \$rc
" < <(COPYFILE_DISABLE=1 tar --no-mac-metadata --format ustar -czf - \
  -C "$repo_dir" \
  install-server.sh \
  session-manager.zsh \
  session-manager-lib.zsh \
  cli/remote-layout \
  terminfo/xterm-ghostty.terminfo 2>/dev/null)

echo "==> Fixture ready."
echo "    ssh -F $ssh_config gzmx-fixture 'zmx version | head -1'"
echo "    Teardown: e2e/fixtures/sshd/down.sh"
