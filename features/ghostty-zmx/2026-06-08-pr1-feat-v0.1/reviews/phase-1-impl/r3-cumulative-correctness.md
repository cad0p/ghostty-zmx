## Findings

### C1 (high) — AppleScript ID extraction does not preserve full Ghostty hex IDs
**Where:** `session-manager.zsh`:437-443, `session-manager.zsh`:628-633, `session-manager.zsh`:668-672, `session-manager.zsh`:687-690, `session-manager.zsh`:725-728, `session-manager.zsh`:740-743
**What:** The canonical spec requires managed names to use the full Ghostty window and tab hex portions. The AppleScript helpers assume the hex portion starts at character 11 when the returned ID is longer than 10 characters. If Ghostty's AppleScript `id` includes a textual prefix such as `window:` or `tab:`, this drops characters from the actual hex ID and can generate/truncate logical IDs instead of preserving the full value. That can produce incorrect session names and undermine the collision-prevention rationale in the design.
**Recommendation:** Confirm Ghostty 1.3.1's exact AppleScript ID string format and strip only the documented prefix, or otherwise parse the hex suffix without dropping hex characters. Add a regression test with prefixed AppleScript IDs, not only raw hex stubs.

### C2 (medium) — Experimental session migration can look in the wrong old data directory
**Where:** `install.sh`:26, `install.sh`:152-169
**What:** The design states the experimental state lives under `~/.local/share/zmx/sessions`. The installer derives `old_data_home` from `${XDG_DATA_HOME:-$HOME/.local/share}/zmx`, so users with `XDG_DATA_HOME` set may have their old experimental `sessions` file skipped during migration.
**Recommendation:** Migrate from the canonical legacy path `~/.local/share/zmx/sessions` for the experimental setup, or explicitly document/test an `XDG_DATA_HOME`-based legacy path if that is intended.

### C3 (medium) — Installer removes arbitrary `confirm-close-surface = false` settings outside the managed block
**Where:** `install.sh`:106-117
**What:** During Ghostty config preparation, the installer removes every exact `confirm-close-surface = false` line, not just an experimental entry inside the old managed area. The design says unrelated user config outside the ghostty-zmx block should be left untouched and warned about when it conflicts.
**Recommendation:** Remove only the legacy experimental `confirm-close-surface = false` when it is part of the known experimental migration context; otherwise leave the setting in place and warn that it conflicts with ghostty-zmx's managed block.

### C4 (medium) — Reaper can misclassify Cmd-Q as close-all-windows if Ghostty stays alive with zero windows
**Where:** `session-manager.zsh`:345-360, `session-manager.zsh`:397-398
**What:** The reaper preserves detached sessions on process exit, but if Ghostty remains alive with `windows=0` for `GHOSTTY_ZMX_ZERO_WINDOWS_GRACE`, it snapshots, kills, unlogs, and forgets all detached managed sessions. During a real Cmd-Q, there may be a window where the app is still alive with zero windows before the process exits; that can be treated like close-all-windows cleanup instead of a quit-shaped preservation event.
**Recommendation:** Strengthen the quit heuristic, for example by tracking whether the Ghostty process exits within the zero-window grace period before applying zero-window cleanup, or by using a more explicit Ghostty/app-state signal when available.

## Well-maintained areas

- Restore state is grouped by logical window and tab before queueing, so append order in `sessions` is not trusted as layout order.
- The restore queue/first-session flow is present and uses serial AppleScript creation plus `zmx attach` for each restored shell.
- The reaper filters managed sessions through the ghostty-zmx `sessions` file and validates session names before logging, snapshotting, killing, or cleanup.
- Scrollback snapshots are truncated, written through a temp file, and not overwritten when `zmx history` fails.
- Reboot/fresh-session injection uses the required banner and runs `zmx run "$session" true` before `zmx print` when a snapshot exists and the session is missing.
- Installer migration removes the experimental `.zshrc` block, replaces the old auto-attach env, preserves existing `ghostty-zmx/sessions`, filters invalid migrated names, and cleans stale `/tmp/zmx-*` flags.
- Release metadata, `package.json`, and the semver-calver release workflow are present, with package-version validation deferred in the release notes.

## Summary

The implementation is close to the locked v0.1 spec and covers the main restore, cleanup, migration, snapshot, reboot-injection, and release-control areas. The main correctness risks are AppleScript ID parsing/truncation, legacy migration path selection under `XDG_DATA_HOME`, over-removal of user Ghostty config during migration, and the reaper's close-vs-Cmd-Q heuristic during zero-window app shutdown.
