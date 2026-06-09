## Findings

### C1 (High) — AppleScript snippets call zsh-only helper names
**Where:** `session-manager.zsh`:481-500, 665-756
**What:** Restore and current-position AppleScript calls invoke `hex_suffix(...)` and `terminal_hash(...)` inside AppleScript, but those handlers are only zsh functions. In a real Ghostty/osascript run those calls are undefined, so current-position detection, new-window/tab/split creation, and restore id-map population can fail. The existing `tests/restore-id-map.zsh` stubs `osascript` and therefore does not exercise this failure.
**Recommendation:** Have AppleScript return raw Ghostty window/tab/terminal IDs and let zsh hash them via `_ghostty_zmx_applescript_ids`, or define the handlers inside each AppleScript payload. Add a test that fails if AppleScript payloads call undefined helper names or that runs against a real Ghostty/osascript path.

### C2 (High) — Reaper state updates are lost in pipeline subshells
**Where:** `session-manager.zsh`:378, 418-430
**What:** The reaper uses `managed_sessions_from_log | while ...` and `managed_detached_sessions | while ...`. In zsh, the `while` side of a pipeline runs in a subshell, so `attached` is never incremented in the parent and `detachedSeen[...]` never persists across intervals. This prevents the intended close-pane/window cleanup path while Ghostty still has attached managed sessions, and detached sessions can remain pending indefinitely instead of being killed/unlogged after the grace period.
**Recommendation:** Avoid pipelines into stateful `while` loops. Use process substitution, `while ...; done < <(...)`, or collect managed sessions into an array first. Keep `attached` and `detachedSeen` updates in the reaper's main shell.

### C3 (Medium) — Restore queue is written before AppleScript layout creation succeeds
**Where:** `session-manager.zsh`:622-630, 646-774
**What:** `_ghostty_zmx_restore` writes `restore-first` and `restore-queue` before attempting the serial AppleScript window/tab/split creation. If a later AppleScript step fails, queued shells can still pop sessions and attach them even though the corresponding Ghostty surfaces were not created, producing orphaned or misassigned managed sessions.
**Recommendation:** Either build the AppleScript layout first and only then write `restore-first`/`restore-queue`, or remove failed sessions from the queue/first file and log the partial restore. Add a failure-path test with a stubbed AppleScript failure.

### C4 (Low) — Reboot-scrollback test checks print input, not zmx history
**Where:** `tests/snapshot-scrollback.zsh`:78-82
**What:** The reboot-scrollback test verifies that `zmx print` receives the exact banner and snapshot text and that `zmx run` was called first, but it does not verify that attaching afterward leaves the text inside `zmx history <session>`, which is the required user-visible behavior.
**Recommendation:** Extend the test or manual E2E harness to assert the restored banner and marker appear in `zmx history <session>` after `zmx attach`, not only in the `zmx print` input log.

## Well-maintained areas

- Managed session naming follows the locked spec: full logical window/tab hex portions and an eight-character terminal prefix.
- Restore grouping is by logical window/tab rather than trusting append order, and the first restored shell remains the only restore driver.
- Reboot scrollback injection uses the required `zmx list --short`, `zmx run "$session" true`, exact banner, `zmx print`, then `zmx attach` flow.
- Snapshot handling preserves old snapshots on `zmx history` failure and truncates saved scrollback with the configured line limit.
- Installer and uninstaller are symlink-aware for their primary install/data/state/runtime targets, preserve user Ghostty settings outside the managed block, and document/manual-clean old experimental state rather than migrating it implicitly.
- Release metadata and workflow align with the v0.1 shell-only package approach and defer package-version validation until `package.json` exists on `main`.

## Summary

The diff implements most of the v0.1 design, including install/uninstall, release metadata, restore grouping/id-map behavior, snapshot truncation, and reboot scrollback injection. The most important correctness blockers are real AppleScript execution and reaper state handling: the AppleScript payloads call undefined handlers, and the reaper loses critical state through zsh pipeline subshells. I also found a restore failure-path issue where queued sessions can outlive failed AppleScript surface creation, and a test gap around proving reboot scrollback lands in zmx history.