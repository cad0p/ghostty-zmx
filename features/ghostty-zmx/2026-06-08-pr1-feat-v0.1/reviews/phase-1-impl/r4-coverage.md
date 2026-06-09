## Findings

### C1 (High) — Reaper lifecycle decisions lack automated coverage
**Where:** session-manager.zsh:376-448; docs/manual-e2e.md:13-147
**What:** The generated reaper contains the core close-cleanup decisions: pid reuse, zero-window cleanup, restore-active skip, all-detached preserve, and detached-session cleanup. These behaviors are documented as manual E2E scenarios, but there is no automated fixture that executes the generated reaper with stubbed `zmx`, `osascript`, and `ps` to assert preserve vs cleanup outcomes.
**Recommendation:** Add a reaper harness test that writes or invokes the generated script with controlled stubs and asserts: zero-window cleanup, all-detached preserve, restore-active skip, pid reuse stop, snapshot preservation/deletion, and unmanaged-session exclusion.

### C2 (Medium) — Restore AppleScript path is only partially covered
**Where:** session-manager.zsh:638-780; tests/restore-id-map.zsh:21-35
**What:** `tests/restore-id-map.zsh` validates session grouping, `restore-first`, `restore-queue`, and `id-map` writes. It does not assert that the AppleScript emitted for the first window, new windows, new tabs, and splits targets the expected physical window/tab, nor does it cover AppleScript failure paths.
**Recommendation:** Extend the restore test to capture the `osascript` scripts and assert the exact new-window/new-tab/split flow, then add failure cases for new-window, new-tab, and split creation.

### C3 (Medium) — Reboot scrollback `zmx run` failure path is untested
**Where:** session-manager.zsh:186-190; tests/snapshot-scrollback.zsh:34-40,75-99
**What:** The scrollback test stub can simulate `zmx run` failure, but the test never enables that path. The implementation logs `zmx run failed` and continues to `zmx print`, which may fail if the fresh session was not created.
**Recommendation:** Decide the intended behavior. If `zmx run` failure should abort restore, add a fail-fast assertion. If it is allowed to continue, add a test documenting that behavior and asserting the resulting `zmx print` failure path.

### C4 (Medium) — Manual E2E checklist needs more concrete verification commands
**Where:** docs/manual-e2e.md:30-45,66-83,93-112
**What:** Several design-critical scenarios are actionable but not fully explicit: working-directory inheritance says to verify new splits/tabs/windows start in the same directory without concrete `pwd` commands; window close cleanup says to record sessions without showing how to map sessions to windows; close-all-windows cleanup lacks an AppleScript command to verify `windows=0`; reboot simulation mentions disposable zmx socket directories but does not give exact setup steps; pane/window close cleanup does not explicitly verify intentional-close snapshot deletion.
**Recommendation:** Add concrete commands for each missing assertion, including `pwd` checks for new surfaces, session/window mapping commands, AppleScript zero-window check, disposable zmx socket setup, and `history/<session>.txt` deletion checks after intentional closes.

### C5 (Low) — Backup creation is not directly asserted
**Where:** install.sh:35-41,182-192; uninstall.sh:31-37,161-166; tests/install-uninstall.zsh:88-135
**What:** The installer and uninstaller claim timestamped backups before editing user shell/Ghostty config files. The smoke tests verify edits and idempotency, but do not assert that backup files were created for the edited `.zshrc` and Ghostty config paths.
**Recommendation:** Add assertions that backup files exist after install/uninstall edits and that they contain the pre-edit content.

### C6 (Low) — Release-control validation is shallow
**Where:** tests/release-control.zsh:7-12; .github/workflows/release.yml:1-24
**What:** The release-control test checks package metadata and greps the workflow/docs for expected strings. It does not parse the workflow YAML or validate the semver-calver action invocation beyond string matching.
**Recommendation:** Add workflow YAML parsing with `ruby`, `python`, or `actionlint` where available, and expand the test to validate the release action inputs/permissions rather than only matching strings.

## Well-maintained areas

- Installer/uninstaller coverage is broad: interactive decline/acceptance, `--yes`, idempotency, symlink refusal, stale experimental runtime cleanup, conflict warnings, existing `sessions` preservation, runtime cleanup, and explicit destructive flags are represented in `tests/install-uninstall.zsh`.
- Scrollback snapshot coverage is strong for the helper path: truncation, failed `zmx history` preserving old snapshots, fresh-session detection, banner injection, `zmx run` before `zmx print`, `zmx list` failure skip, missing snapshot skip, and debug-log history leakage are tested in `tests/snapshot-scrollback.zsh`.
- Restore grouping and `id-map` behavior have a focused fixture in `tests/restore-id-map.zsh`.
- Release-control documentation explicitly explains why `validate-package-version` is deferred until `package.json` exists on `main`.

## Summary

Coverage is solid for installer/uninstaller smoke behavior, scrollback snapshot/injection helpers, restore grouping/id-map, and release metadata. The main coverage gaps are automated tests for the generated reaper lifecycle and the AppleScript restore creation path, plus more concrete E2E commands for working-directory inheritance, window mapping, zero-window cleanup, reboot daemon-loss simulation, and intentional-close snapshot deletion.