#!/usr/bin/env zsh
# Tear down the ghostty-zmx plain-ssh E2E fixture.
# Stops and removes the container. The built image is kept (rebuild is slow).
set -eu
local container="ghostty-zmx-sshd-fixture"
docker rm -f "$container" >/dev/null 2>&1 && echo "==> Removed container $container." || echo "==> Container $container not running."
