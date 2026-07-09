# ghostty-zmx E2E fixture: Ubuntu 24.04 sshd with zmx + zsh.
# Used by the plain-ssh (`ssh gzmx-fixture`) E2E scenarios.
# Built and run by e2e/fixtures/sshd/up.sh.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
# zmx 0.6.x is a prerequisite on both laptop and server (per the v0.2 design).
# Install zsh, openssh-server, and curl (for the zmx install script). socat is
# useful for E2E debugging. ca-certificates for the zmx download.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server zsh curl ca-certificates socat && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /run/sshd

# Create the fixture user (gzmx) with a home dir and zsh as the login shell.
RUN useradd -m -s /usr/bin/zsh gzmx

# Authorize the fixture SSH key (generated on the laptop by up.sh).
RUN mkdir -p /home/gzmx/.ssh && chmod 700 /home/gzmx/.ssh
COPY id_ed25519.pub /home/gzmx/.ssh/authorized_keys
RUN chmod 600 /home/gzmx/.ssh/authorized_keys && chown -R gzmx:gzmx /home/gzmx/.ssh

# Install zmx 0.6.x as the fixture user (so ~/.local/bin is on the interactive
# PATH via .zshrc, mirroring pcad-dev where zmx is NOT on the non-interactive
# PATH — this is the exact scenario the absolute-path probe fixes).
# zmx ships prebuilt static binaries on GitHub releases (no install.sh).
USER gzmx
ENV HOME=/home/gzmx
ARG TARGETARCH
RUN case "$TARGETARCH" in \
      amd64) zmx_arch="x86_64"; ;; \
      arm64) zmx_arch="aarch64"; ;; \
      *) echo "unsupported arch: $TARGETARCH"; exit 1; ;; \
    esac && \
    mkdir -p ~/.local/bin && \
    curl -fsSL "https://github.com/neurosnap/zmx/releases/download/v0.6.0/zmx-0.6.0-linux-${zmx_arch}.tar.gz" \
      | tar xz -C ~/.local/bin && \
    chmod +x ~/.local/bin/zmx && \
    ~/.local/bin/zmx version | head -1
# Add ~/.local/bin to PATH only in .zshrc (interactive), NOT .profile, so the
# non-interactive PATH lacks zmx — matching pcad-dev and exercising the probe.
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/gzmx/.zshrc

USER root

# Simulate pam_systemd setting XDG_RUNTIME_DIR for INTERACTIVE shells only.
# Real Linux hosts set XDG_RUNTIME_DIR=/run/user/<uid> via pam_systemd at
# login (interactive), but NON-interactive ssh commands (the projection's
# `ssh host 'zmx attach ...'`) do NOT get it. This divergence is the root
# cause of the socket-dir mismatch bug: the projection creates the session in
# zmx's fallback dir (/tmp/zmx-<uid>), but the pane's interactive shell
# queries /run/user/<uid>/zmx. Without this simulation the e2e fixture (no
# systemd) has both paths agree on /tmp and cannot reproduce the bug.
# gzmx is uid 1000 in this image (useradd default).
RUN mkdir -p /run/user/1000 && chown gzmx:gzmx /run/user/1000 && chmod 700 /run/user/1000 && \
    echo 'export XDG_RUNTIME_DIR=/run/user/1000' >> /home/gzmx/.zshrc
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D", "-e"]
