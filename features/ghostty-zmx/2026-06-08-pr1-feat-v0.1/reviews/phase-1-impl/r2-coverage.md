## Findings

### COV-R2-1 (medium) — Restore and reaper behavior is mostly manual-only
**Where:** `session-manager.zsh:249-308`, `session-manager.zsh:420-748`, `tests/snapshot-scrollback.zsh:48-69`, `docs/manual-e2e.md:93-112`
**What:** The executable tests cover snapshot truncation, fresh-session detection, `zmx run` before `zmx print`, banner ordering, and debug-log non-leakage for the scrollback helper. They do not provide fixture-level coverage for restore grouping by logical window/tab, `restore-queue`/`restore-first` behavior, id-map writes, reaper detached-session cleanup, zero-window cleanup, app-exit snapshot preservation, or managed-vs-unmanaged classification. The manual E2E checklist covers those scenarios, but it is not a regression seam for future shell changes.
**Recommendation:** Add temp-HOME fixture tests for restore grouping and id-map behavior with stubbed `osascript` and fake Ghostty positions. Extract or parameterize the generated reaper decision loop enough to feed fake `zmx list` output and assert snapshot, `zmx kill`, cleanup-log, and preserve decisions without requiring real Ghostty/zmx daemons.

### COV-R2-2 (medium) — Installer migration edge cases are not fully covered
**Where:** `install.sh:67-87`, `install.sh:106-169`, `install.sh:177-187`, `tests/install-uninstall.zsh:40-63`
**What:** The installer test covers the normal experimental `.zshrc` block, old `ZMX_AUTO_ATTACH`, exact `confirm-close-surface = false`, one conflict warning, invalid migrated session filtering, and idempotency. It does not cover an unterminated experimental `.zshrc` block, an existing `~/.local/share/ghostty-zmx/sessions` file during migration, stale `/tmp/zmx-*` flag cleanup, or preservation of live zmx sessions.
**Recommendation:** Add migration fixtures for unterminated experimental blocks, existing ghostty-zmx sessions files, stale runtime flag removal, and a live session that remains untouched. Document or test the expected behavior when the old experimental sessions file is absent or unreadable.

### COV-R2-3 (medium) — Interactive install acceptance is only partially exercised
**Where:** `install.sh:50-56`, `install.sh:197-198`, `tests/install-uninstall.zsh:27-32`, `tests/install-uninstall.zsh:57-67`
**What:** The installer test covers interactive decline and non-interactive `--yes` installation/idempotency. It does not exercise the default interactive path where the user accepts the printed plan. Because the installer is interactive by default and prints the exact managed block before applying it, that path should have a deterministic fixture.
**Recommendation:** Add a `printf 'y\n' | run_install ...` fixture that asserts the same file outcomes as `--yes` and checks that the plan output includes the managed Ghostty block.

### COV-R2-4 (low) — Release-control validation is declarative rather than executable
**Where:** `.github/workflows/release.yml:23-24`, `package.json:2-3`, `README.md:176-178`, `RELEASE.md:5-18`
**What:** The package has `package.json` and a release workflow using `cad0p/semver-calver-release/release@v1`, and the validation workflow deferral is documented because `package.json` is not yet on `main`. However, the current coverage consists of documentation and manual pre-merge checks, not an executable smoke check for the release-control inputs.
**Recommendation:** Add a lightweight local release-control smoke test that validates `package.json` version metadata and the release workflow shape, while explicitly recording why `validate-package-version` remains deferred until `package.json` exists on `main`.

### COV-R2-5 (low) — Uninstall interactive behavior is not covered
**Where:** `uninstall.sh:40-47`, `uninstall.sh:89-120`, `tests/install-uninstall.zsh:69-83`
**What:** The uninstall test covers `--yes` non-destructive behavior, explicit destructive flags, and unsafe data deletion refusal. It does not cover interactive decline or interactive acceptance for the Ghostty block removal prompt.
**Recommendation:** Add a fixture that pipes `n\n` into uninstall and asserts no config/source-line changes, plus one that accepts the managed block removal and verifies the block is removed while data/state remain unless explicit flags are passed.

## Well-maintained areas

- `tests/install-uninstall.zsh` provides a useful temp-HOME harness with stubbed `zmx`, `osascript`, and `zsh`, covering installer decline, `--yes` install, migration cleanup, conflict warnings, valid-session filtering, idempotency, non-destructive uninstall, explicit destructive flags, and unsafe deletion refusal.
- `tests/snapshot-scrollback.zsh` verifies the most important reboot-scrollback seams: truncation, banner ordering, creating a fresh session before printing, no-op when no snapshot exists, and failure logging without saved history leakage.
- `README.md` and `docs/manual-e2e.md` document the tested environment, installer behavior, managed Ghostty block, migration path, state paths, debug logging, close/reboot semantics, and manual E2E scenarios.
- `RELEASE.md` and `package.json` make the release-control plan explicit for a shell-only v0.1 package, including why package-version validation is deferred until after `package.json` lands on `main`.

## Summary

The diff adds meaningful executable coverage for installer/uninstaller paths and scrollback snapshot/injection behavior, but coverage remains uneven around restore/reaper internals and full interactive/migration workflows. The strongest next step is fixture-level coverage for restore grouping/id-map behavior and reaper decisions, followed by tests for interactive install acceptance, additional migration edge cases, uninstall prompts, and a small release-control smoke check.