#!/bin/zsh
# Unit tests for `ghostty-zmx install-server` — the one-shot server bootstrap
# subcommand added to the ghostty-zmx wrapper.
#
# Covers:
#   1. --help lists both modes (projection + install-server)
#   2. install-server with no host → error exit 2
#   3. install-server with missing local bundle files → error exit 1
#   4. install-server <known-host> resolves transport from remote-hosts
#   5. install-server <unknown-host> falls back to ssh <host>
#   6. install-server -- <transport...> uses the explicit transport
#
# Does NOT contact a real remote. The tar|ssh pipe is not exercised here;
# that is covered by the manual e2e doc. These tests verify argument parsing,
# transport resolution, and the missing-file guard.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

export HOME="$workdir/home"
export GHOSTTY_ZMX_INSTALL_DIR="$workdir/config/ghostty-zmx"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data/ghostty-zmx"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state/ghostty-zmx"
mkdir -p "$HOME" "$GHOSTTY_ZMX_INSTALL_DIR/terminfo" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME"

# Copy the wrapper under test.
install -m 0755 "$repo_dir/ghostty-zmx" "$GHOSTTY_ZMX_INSTALL_DIR/ghostty-zmx"
wrapper="$GHOSTTY_ZMX_INSTALL_DIR/ghostty-zmx"

# --- Case 1: --help lists both modes ---
out="$("$wrapper" --help 2>&1)"
rc=$?
[[ $rc -eq 0 ]] || { print -u2 "help: expected exit 0, got $rc"; exit 1 }
[[ "$out" == *"projection"* ]] || { print -u2 "help: missing projection mode"; exit 1 }
[[ "$out" == *"install-server"* ]] || { print -u2 "help: missing install-server mode"; exit 1 }
print "ok: --help lists both modes"

# --- Case 2: install-server with no host → error exit 2 ---
out="$("$wrapper" install-server 2>&1)"
rc=$?
[[ $rc -eq 2 ]] || { print -u2 "no-host: expected exit 2, got $rc"; exit 1 }
[[ "$out" == *"host argument required"* ]] || { print -u2 "no-host: wrong message: $out"; exit 1 }
print "ok: no host → exit 2"

# --- Case 3: install-server with missing local bundle → error exit 1 ---
# (no files installed in $GHOSTTY_ZMX_INSTALL_DIR except the wrapper itself)
out="$("$wrapper" install-server somehost 2>&1)"
rc=$?
[[ $rc -eq 1 ]] || { print -u2 "missing-bundle: expected exit 1, got $rc ($out)"; exit 1 }
[[ "$out" == *"missing local file"* ]] || { print -u2 "missing-bundle: wrong message: $out"; exit 1 }
[[ "$out" == *"Run ghostty-zmx-install --yes on this laptop first"* ]] || { print -u2 "missing-bundle: missing hint: $out"; exit 1 }
print "ok: missing bundle → exit 1 with hint"

# --- Case 4: install-server <known-host> resolves transport from remote-hosts ---
# Stage the bundle files so we get past the missing-file guard.
for f in install-server.sh session-manager.zsh session-manager-lib.zsh ghostty-zmx-remote-layout; do
  : > "$GHOSTTY_ZMX_INSTALL_DIR/$f"
done
: > "$GHOSTTY_ZMX_INSTALL_DIR/terminfo/xterm-ghostty.terminfo"

# Record a known host with a tsh prefix + zmx path (6-field format).
print -r -- "pcad-dev	tsh	0.6.0	active	tsh ssh -t pier@pcad-dev	/home/pier/.local/bin/zmx" \
  > "$GHOSTTY_ZMX_DATA_HOME/remote-hosts"

# Intercept the tar|ssh pipe by shadowing tar and the transport in PATH.
# We point PATH at a stub dir where `tsh` prints the argv it received.
stubbin="$workdir/stubbin"
mkdir -p "$stubbin"
# Stub tar: consume stdin, exit 0 (pretend the bundle was sent).
cat > "$stubbin/tar" <<'EOF'
#!/bin/sh
# drain stdin
cat >/dev/null 2>&1
exit 0
EOF
chmod +x "$stubbin/tar"
# Stub tsh: record argv, exit 0 (pretend the remote install succeeded).
cat > "$stubbin/tsh" <<'EOF'
#!/bin/sh
echo "TSH_ARGV:$@"
exit 0
EOF
chmod +x "$stubbin/tsh"

out="$(PATH="$stubbin:$PATH" "$wrapper" install-server pcad-dev 2>&1)"
rc=$?
[[ $rc -eq 0 ]] || { print -u2 "known-host: expected exit 0, got $rc ($out)"; exit 1 }
[[ "$out" == *"bootstrapping server install on pcad-dev"* ]] || { print -u2 "known-host: missing banner: $out"; exit 1 }
# tsh ssh is non-interactive when a command arg is present; no -T/-t needed.
# The stub tsh should have received: ssh pier@pcad-dev <remote_script>
[[ "$out" == *"TSH_ARGV:ssh pier@pcad-dev"* ]] || { print -u2 "known-host: wrong transport argv: $out"; exit 1 }
print "ok: known-host → tsh transport from remote-hosts"

# --- Case 5: install-server <unknown-host> falls back to ssh <host> ---
# Stub ssh in the same stubbin.
cat > "$stubbin/ssh" <<'EOF'
#!/bin/sh
echo "SSH_ARGV:$@"
exit 0
EOF
chmod +x "$stubbin/ssh"

out="$(PATH="$stubbin:$PATH" "$wrapper" install-server newhost.example.com 2>&1)"
rc=$?
[[ $rc -eq 0 ]] || { print -u2 "unknown-host: expected exit 0, got $rc ($out)"; exit 1 }
[[ "$out" == *"SSH_ARGV:-T newhost.example.com"* ]] || { print -u2 "unknown-host: wrong transport argv: $out"; exit 1 }
print "ok: unknown-host → ssh fallback"

# --- Case 6: install-server -- <transport...> uses explicit transport ---
out="$(PATH="$stubbin:$PATH" "$wrapper" install-server -- tsh ssh -i /tmp/key pier@explicit-host 2>&1)"
rc=$?
[[ $rc -eq 0 ]] || { print -u2 "explicit: expected exit 0, got $rc ($out)"; exit 1 }
[[ "$out" == *"TSH_ARGV:ssh -i /tmp/key pier@explicit-host"* ]] || { print -u2 "explicit: wrong transport argv: $out"; exit 1 }
print "ok: explicit -- transport"

print ""
print "all install-server-cli tests passed"
