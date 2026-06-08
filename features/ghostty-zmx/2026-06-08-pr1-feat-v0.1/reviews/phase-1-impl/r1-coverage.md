## Findings

### COV-1 (medium) — No executable coverage exists for installer/migration paths
**Where:** `package.json`:1, `install.sh`:62, `install.sh`:133, `install.sh`:180
**What:** The PR adds substantial migration and installer logic, including experimental `.zshrc` block removal, Ghostty managed-section rewriting, dependency checks, backups, migration copy behavior, and stale `/tmp` cleanup, but there are no test files, package scripts, or CI checks to exercise those paths. `install.sh` is also only executable as a whole, so testing helper functions requires running the installer entrypoint unless a harness wraps the whole script with temp `HOME`, stubbed commands, and a temporary Ghostty config. This leaves the required interactive and `--yes` flows, idempotency, conflict warnings, and migration edge cases vulnerable to regressions.
**Recommendation:** Add a lightweight shell test harness, even if not full E2E: run `install.sh --yes` under a temporary `HOME`, temporary `GHOSTTY_ZMX_GHOSTTY_CONFIG`, and stubbed `zmx`/`osascript`/`zsh`; assert backups, source-line idempotency, managed-block replacement, conflict warnings, experimental block removal, sessions-copy behavior, and stale-flag cleanup. If helper-level tests are desired, split installer functions into a sourceable library or gate the entrypoint behind a test variable.

### COV-2 (medium) — Restore/reaper behavior has no fixture-level validation seams
**Where:** `session-manager.zsh`:81, `session-manager.zsh`:112, `session-manager.zsh`:149, `session-manager.zsh`:181
**What:** Core v0.1 correctness depends on the generated reaper script parsing `zmx list`, distinguishing Cmd-Q-shaped all-detached states from pane/window closes, respecting restore flags, handling zero-window cleanup, and never touching unmanaged sessions. The current coverage is only syntax checking/manual E2E; the reaper is embedded in a heredoc generated at runtime and depends directly on live `zmx` and AppleScript, so parser and decision edge cases are hard to test without a real Ghostty session. This is a coverage gap for the most regression-prone lifecycle behavior.
**Recommendation:** Extract the reaper script or its decision helpers into a testable file/function and add fixtures for representative `zmx list` output and window-count sequences: attached managed session, detached managed pane while another managed session is attached, Cmd-Q/all-clients-detached preservation, zero-window cleanup after grace, restore-active skip, and unmanaged sessions in `zmx list` not present in the sessions file.

### COV-3 (medium) — Scrollback snapshot, truncation, and injection claims are only manually checked in the happy path
**Where:** `session-manager.zsh`:46, `session-manager.zsh`:60, `session-manager.zsh`:73, `docs/manual-e2e.md`:93
**What:** The design requires saved scrollback to be truncated by `GHOSTTY_ZMX_SCROLLBACK_LINES`, injected into a newly created zmx session after daemon loss, and not leaked into debug logs. The implementation contains those mechanisms, and the manual E2E checks for the banner and marker after `zmx kill`, but there is no fixture/test plan for boundary cases: custom line limits, empty/missing snapshots, `zmx run` failure before `zmx print`, `zmx print` failure logging, deletion of intentional-close snapshots, or verifying debug logs never include terminal output. The manual checklist also does not explicitly validate truncation.
**Recommendation:** Add unit-style tests with stubbed `zmx history`, `zmx list --short`, `zmx run`, and `zmx print` to assert line-limit truncation, banner ordering, fresh-session creation before print, failure logging without saved content, and snapshot deletion for intentional close. Extend manual E2E with a large marker set and a small `GHOSTTY_ZMX_SCROLLBACK_LINES` value to prove truncation behavior.

### COV-4 (low) — Manual E2E checklist is useful but not fully actionable for installer and release readiness
**Where:** `docs/manual-e2e.md`:1, `docs/manual-e2e.md`:130, `README.md`:21, `.github/workflows/release.yml`:1
**What:** The checklist covers Ghostty lifecycle scenarios well, but it does not include an explicit installer/uninstaller verification matrix for interactive install, `--yes`, migration fixtures, conflict warnings, or idempotent reruns. Release-control validation is documented as deferred for `validate-package-version`, and the release workflow is present, but there is no stated local/CI validation step for workflow syntax or package metadata while `package.json` is not yet on `main`.
**Recommendation:** Add a short `docs/manual-e2e.md` or `RELEASE.md` section listing pre-merge checks: `zsh -n session-manager.zsh install.sh uninstall.sh`, temp-HOME `./install.sh --yes`, interactive decline/apply smoke test, uninstall `--yes`, `jq . package.json`, and an explicit release-workflow sanity check appropriate for the repo tooling. This can remain manual for v0.1, but it should be written down.

## Well-maintained areas

- The implementation at least passes `zsh -n session-manager.zsh install.sh uninstall.sh` during this review.
- `docs/manual-e2e.md` covers the main user-visible lifecycle scenarios: Cmd-Q restore, working-directory inheritance, pane/window/all-window cleanup, Cmd-Q preservation, reboot scrollback simulation, unmanaged sessions, and automated-test close-confirmation override.
- README documents the `--yes` installer path, managed Ghostty block, migration behavior, debug logging scope, reboot scrollback semantics, release-control deferral, and known limitations.
- Debug log messages are event/session oriented in the reviewed code paths, and the scrollback content is kept in history snapshot files rather than logged directly.

## Summary

Coverage is currently mostly documentation plus a syntax check. That may be acceptable for an early shell-only draft, but v0.1 behavior is stateful and destructive enough that temp-HOME installer fixtures and stubbed reaper/snapshot tests would materially reduce regression risk before release.