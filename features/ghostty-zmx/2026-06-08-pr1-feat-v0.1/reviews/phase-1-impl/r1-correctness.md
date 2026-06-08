## Findings

### C1 (block) — Installed `.zshrc` source line cannot source the manager
**Where:** `install.sh`:27, `README.md`:38
**What:** The installer writes the source line with literal backslash-escaped quotes:

```zsh
[[ -r \"$HOME/.config/ghostty-zmx/session-manager.zsh\" ]] && source \"$HOME/.config/ghostty-zmx/session-manager.zsh\"
```

In zsh, those backslashes make the quotes part of the pathname in the `[[ -r ... ]]` test, so the test looks for a path containing literal `"` characters and evaluates false. A freshly installed user will therefore not source `session-manager.zsh`, `GHOSTTY_ZMX_AUTO_ATTACH=1` will have no effect, and no Ghostty surface will attach to a managed zmx session.
**Recommendation:** Write the unescaped shell syntax to `.zshrc` and docs, e.g. `[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"` as actual shell text, not with literal backslashes before the quotes. Keep uninstall matching both the old broken line and the corrected line for migration/idempotence.

### C2 (high) — Cmd-Q snapshot/preserve semantics are timing-dependent and can miss the required reboot snapshot
**Where:** `session-manager.zsh`:149-203
**What:** The reaper only snapshots detached sessions while the Ghostty process is still alive inside the polling loop. On a normal Cmd-Q, Ghostty can exit before the next reaper iteration observes `clients=0`; the loop then terminates at `while kill -0 "$ghosttyPID"` without taking any final snapshot. That violates the design requirement that Cmd-Q snapshots are kept/overwritten for crash/reboot recovery. Conversely, if Cmd-Q detaches clients gradually while Ghostty is still alive and at least one managed session still has `clients=1`, the `attached > 0` branch kills and unlogs any already-detached managed sessions as intentional closes (`session-manager.zsh`:177-199), which can destroy sessions that should be preserved for Cmd-Q restore.
**Recommendation:** Add an explicit Cmd-Q-shaped shutdown path. Before the reaper exits on Ghostty process termination, snapshot all managed sessions that still exist and leave the sessions file intact. Also avoid killing newly detached sessions until the close-vs-quit heuristic has had a stable interval to distinguish single-surface/window closes from all-client detaches caused by app quit.

### C3 (high) — Restore creation uses `front window`/focused terminal, so focus changes can corrupt layout and id-map
**Where:** `session-manager.zsh`:421-449
**What:** The restore driver creates subsequent tabs with `new tab in front window` and splits `focused terminal of selected tab of front window`. During restore, newly spawned shells attach asynchronously and user/Ghostty focus can move. If the front window or focused tab is not the logical window/tab currently being restored, tabs/splits are created in the wrong window/tab while `_ghostty_zmx_write_id_map` records them under the intended logical IDs. This breaks the locked restore invariant that sessions are regrouped by logical window/tab and rebuilt into that layout, and it undermines the design warning that focus can move during restore.
**Recommendation:** Drive AppleScript against explicit window/tab objects or IDs captured at creation time, or deliberately select/activate the expected physical window and tab immediately before each operation and verify the returned physical IDs before writing `id-map`. Treat AppleScript failures or mismatched IDs as restore failures rather than silently continuing.

### C4 (medium) — Experimental `confirm-close-surface = false` is left as a live conflicting setting
**Where:** `install.sh`:101-142
**What:** Migration removes the old `env = ZMX_AUTO_ATTACH=1` line but does not remove the known experimental `confirm-close-surface = false` setting. It only warns about any `confirm-close-surface` outside the managed section and then appends a managed `confirm-close-surface = true` block. Depending on Ghostty config precedence, the old false setting may continue to disable close confirmation, which conflicts with the v0.1 locked decision that production installs keep `confirm-close-surface = true` because managed closes are destructive.
**Recommendation:** Detect the exact experimental `confirm-close-surface = false` line during migration and either remove it after backup/confirmation or fail/warn with clear manual remediation before claiming migration is complete. If duplicate precedence is relied on, document and test that the managed block wins.

## Well-maintained areas

- `zsh -n session-manager.zsh install.sh uninstall.sh` passes.
- The implementation uses the new `GHOSTTY_ZMX_AUTO_ATTACH` variable and XDG-style `ghostty-zmx` data/state paths.
- Session naming uses full logical window/tab hex portions and an eight-character terminal component, matching the collision-avoidance design.
- Restore groups sessions by logical window/tab rather than trusting raw append order.
- Reboot scrollback injection follows the required broad shape: check for missing zmx session, run `zmx run "$session" true`, inject the exact banner and saved text with `zmx print`, then attach.
- Reaper cleanup is scoped to sessions present in the ghostty-zmx `sessions` file, so unmanaged zmx sessions are not directly targeted.
- Installer/uninstaller back up edited config files and avoid wholesale replacement of user shell/Ghostty config.
- Release metadata includes `package.json` and a workflow using `cad0p/semver-calver-release/release@v1`, with package-version validation deferred in docs.

## Summary

The implementation covers much of the intended v0.1 shape, but there are correctness blockers around install activation and core lifecycle semantics. The literal escaped `.zshrc` source line prevents the integration from loading after install. The reaper's Cmd-Q handling can miss required snapshots or misclassify gradual app quit as destructive closes. Restore also relies on focus-sensitive AppleScript targets, risking wrong layout/id-map reconstruction. These should be fixed before treating the implementation as matching the locked design.
