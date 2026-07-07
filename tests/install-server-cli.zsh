#!/bin/zsh
# Unit tests for the ghostty-zmx CLI subcommands.
#
# Covers:
#   1. --help lists all modes (projection, install, uninstall, install-server)
#   2. install-server with no host → error exit 2
#   3. install-server with missing local bundle files → error exit 1
#   4. install-server <known-host> resolves transport from remote-hosts
#   5. install-server <unknown-host> falls back to ssh <host>
#   6. install-server -- <transport...> uses the explicit transport
#   7. install-server falls back to the wrapper's own install dir when env is unset
#   8. install delegates to sibling install.sh
#   9. uninstall delegates to sibling uninstall.sh
#
# Does NOT contact a real remote. The tar|ssh pipe is not exercised here;
# that is covered by the manual e2e doc. These tests verify argument parsing,
# transport resolution, the missing-file guard, and install/uninstall delegation.

repo_dir="${0:A:h:h}"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

export HOME="$workdir/home"
export GHOSTTY_ZMX_INSTALL_DIR="$workdir/config/ghostty-zmx"
export GHOSTTY_ZMX_DATA_HOME="$workdir/data/ghostty-zmx"
export GHOSTTY_ZMX_STATE_HOME="$workdir/state/ghostty-zmx"
mkdir -p "$HOME" "$GHOSTTY_ZMX_INSTALL_DIR/terminfo" "$GHOSTTY_ZMX_DATA_HOME" "$GHOSTTY_ZMX_STATE_HOME"

# Copy the wrapper and its cli/ subcommand siblings under test (mirror install layout).
mkdir -p "$GHOSTTY_ZMX_INSTALL_DIR/cli"
install -m 0755 "$repo_dir/cli/ghostty-zmx" "$GHOSTTY_ZMX_INSTALL_DIR/cli/ghostty-zmx"
install -m 0755 "$repo_dir/cli/install-server" "$GHOSTTY_ZMX_INSTALL_DIR/cli/install-server"
install -m 0755 "$repo_dir/cli/debug" "$GHOSTTY_ZMX_INSTALL_DIR/cli/debug"
install -m 0755 "$repo_dir/cli/remote-layout" "$GHOSTTY_ZMX_INSTALL_DIR/cli/remote-layout"
wrapper="$GHOSTTY_ZMX_INSTALL_DIR/cli/ghostty-zmx"

# --- Case 1: --help lists all modes ---
out="$("$wrapper" --help 2>&1)"
rc=$?
[[ $rc -eq 0 ]] || { print -u2 "help: expected exit 0, got $rc"; exit 1 }
[[ "$out" == *"projection"* ]] || { print -u2 "help: missing projection mode"; exit 1 }
[[ "$out" == *"install-server"* ]] || { print -u2 "help: missing install-server mode"; exit 1 }
[[ "$out" == *"install "* ]] || { print -u2 "help: missing install mode"; exit 1 }
[[ "$out" == *"uninstall"* ]] || { print -u2 "help: missing uninstall mode"; exit 1 }
print "ok: --help lists all modes"

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
for f in install-server.sh session-manager.zsh session-manager-lib.zsh; do
  : > "$GHOSTTY_ZMX_INSTALL_DIR/$f"
done
: > "$GHOSTTY_ZMX_INSTALL_DIR/cli/remote-layout"
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

# --- Case 4b: install-server <known-host> with ABSOLUTE tsh path ---
# Regression: the manager resolves transport binaries absolutely
# (ghostty_zmx_resolve_transport_path), so a stored prefix may be
# "/usr/local/bin/tsh ssh -t pier@host" rather than "tsh ssh". The
# is_tsh detection must use the basename, not a literal == "tsh" compare,
# or it falls into the plain-ssh branch and produces "ssh ssh pier@host"
# ("Could not resolve hostname ssh").
# Use a stub at an absolute path we control (the wrapper execs the absolute
# path directly, so PATH shadowing doesn't work for absolute paths).
# Name it 'tsh' so the basename detection (\${bin:t} == "tsh") works.
stub_tsh_dir="$workdir/stub-bin"
mkdir -p "$stub_tsh_dir"
cat > "$stub_tsh_dir/tsh" <<'EOF'
#!/bin/sh
echo "TSH_ARGV:$@"
exit 0
EOF
chmod +x "$stub_tsh_dir/tsh"
stub_tsh="$stub_tsh_dir/tsh"
print -r -- "pcad-dev-abs	tsh	0.6.0	active	$stub_tsh ssh -t pier@pcad-dev	/home/pier/.local/bin/zmx" \
  > "$GHOSTTY_ZMX_DATA_HOME/remote-hosts"

out="$(PATH="$stubbin:$PATH" "$wrapper" install-server pcad-dev-abs 2>&1)"
rc=$?
[[ $rc -eq 0 ]] || { print -u2 "known-host-abs: expected exit 0, got $rc ($out)"; exit 1 }
# The absolute stub tsh must receive: ssh pier@pcad-dev <remote_script>.
# The -t is dropped (no-pty). The basename detection means is_tsh=1, so no
# -T is inserted and the "ssh" after tsh is consumed as the subcommand.
[[ "$out" == *"TSH_ARGV:ssh pier@pcad-dev"* ]] || { print -u2 "known-host-abs: wrong transport argv: $out"; exit 1 }
print "ok: known-host with absolute tsh path → tsh transport (basename detection)"

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

# --- Case 7: install-server uses the wrapper's own install dir when env is unset ---
alt_install="$workdir/alt-install"
mkdir -p "$alt_install/cli" "$alt_install/terminfo"
install -m 0755 "$repo_dir/cli/ghostty-zmx" "$alt_install/cli/ghostty-zmx"
install -m 0755 "$repo_dir/cli/install-server" "$alt_install/cli/install-server"
for f in install-server.sh session-manager.zsh session-manager-lib.zsh; do
  : > "$alt_install/$f"
done
: > "$alt_install/cli/remote-layout"
: > "$alt_install/terminfo/xterm-ghostty.terminfo"
out="$(cd "$workdir"; unset GHOSTTY_ZMX_INSTALL_DIR; PATH="$stubbin:$PATH" "$alt_install/cli/ghostty-zmx" install-server selfdir-host 2>&1)"
rc=$?
[[ $rc -eq 0 ]] || { print -u2 "self-dir: expected exit 0, got $rc ($out)"; exit 1 }
[[ "$out" == *"SSH_ARGV:-T selfdir-host"* ]] || { print -u2 "self-dir: wrong transport argv: $out"; exit 1 }
print "ok: install-server uses wrapper dir when install env is unset"

# --- Case 8: install delegates to sibling install.sh ---
# Stage install.sh + uninstall.sh as siblings of the wrapper so delegation finds them.
cat > "$GHOSTTY_ZMX_INSTALL_DIR/install.sh" <<'EOF'
#!/bin/zsh
echo "INSTALL_SH_CALLED with: $@"
exit 0
EOF
chmod +x "$GHOSTTY_ZMX_INSTALL_DIR/install.sh"
out="$("$wrapper" install --yes 2>&1)"
rc=$?
[[ $rc -eq 0 ]] || { print -u2 "install: expected exit 0, got $rc ($out)"; exit 1 }
[[ "$out" == *"INSTALL_SH_CALLED with: --yes"* ]] || { print -u2 "install: wrong delegation: $out"; exit 1 }
print "ok: install delegates to install.sh"

# --- Case 9: uninstall delegates to sibling uninstall.sh ---
cat > "$GHOSTTY_ZMX_INSTALL_DIR/uninstall.sh" <<'EOF'
#!/bin/zsh
echo "UNINSTALL_SH_CALLED with: $@"
exit 0
EOF
chmod +x "$GHOSTTY_ZMX_INSTALL_DIR/uninstall.sh"
out="$("$wrapper" uninstall --yes 2>&1)"
rc=$?
[[ $rc -eq 0 ]] || { print -u2 "uninstall: expected exit 0, got $rc ($out)"; exit 1 }
[[ "$out" == *"UNINSTALL_SH_CALLED with: --yes"* ]] || { print -u2 "uninstall: wrong delegation: $out"; exit 1 }
print "ok: uninstall delegates to uninstall.sh"

print ""
print "all install-server-cli tests passed"
