# Phase 3 bloat review: tests and E2E harness

Scope reviewed in full:

- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/design.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md`
- `tests/install-uninstall.zsh`
- `tests/snapshot-scrollback.zsh`
- `tests/restore-id-map.zsh`
- `tests/release-control.zsh`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-supervisor.zsh`

Overall: the test suite is not testing deleted or out-of-scope production features. The main bloat is fixture/setup duplication and broad mixed-purpose harness scripts. The E2E assertions added after Phase 2 are aligned with the design/methodology and should be preserved: Cmd-Q restore layout shape, `clients=1`, markers in `zmx history`, no restore failures, close cleanup, close-all behavior, reboot scrollback inside zmx history, unmanaged preservation, and byte-for-byte restoration of user files.

## Findings

### R1-BT-1 — low — Duplicate installer conflict fixtures can be collapsed

- Location: `tests/install-uninstall.zsh:63`, `tests/install-uninstall.zsh:86`
- Issue: the primary install fixture at lines 63-84 and the `home_user_conflict` fixture at lines 86-99 both construct nearly the same Ghostty conflict block and reassert preservation/warnings for `confirm-close-surface` and `quit-after-last-window-closed`. The only meaningful delta is presence/absence of the pre-existing auto-attach env line.
- Recommendation: keep the behavioral coverage, but extract a small helper for “run install against config text and assert preserved conflict settings/warnings”, or make one table-style mini-loop for the two input variants. Preserve the separate auto-attach warning assertion only for the first case.
- Risk/LOC saved: low risk; saves about 10-18 LOC and reduces future drift between the two conflict fixtures.

### R1-BT-2 — low — Unsafe deletion fixtures repeat the same symlink/refusal pattern

- Location: `tests/install-uninstall.zsh:159`, `tests/install-uninstall.zsh:173`, `tests/install-uninstall.zsh:185`, `tests/install-uninstall.zsh:196`
- Issue: the unsafe runtime, install-dir, data-dir, and home-as-data checks are valuable, but each repeats full temp path setup, symlink creation, negative invocation, and target-survival assertion inline.
- Recommendation: keep all symlink-safety cases, but factor the common negative-check shape into a helper such as `expect_refuses_and_preserves_target <label> <command...> <target>`. The home-as-data case can still remain explicit because it has no symlink target.
- Risk/LOC saved: low risk; saves about 15-25 LOC while retaining the security assertions required by prior reviews.

### R1-BT-3 — medium — `snapshot-scrollback.zsh` contains unrelated generated-reaper syntax and elapsed-parser coverage

- Location: `tests/snapshot-scrollback.zsh:56`
- Issue: lines 56-84 extract the generated reaper heredoc with `awk`, write it to a temp file, syntax-check it, then test generated and main elapsed-time parser helpers. This coverage is useful because Phase 2 exposed reaper elapsed parsing problems, but it is not scrollback snapshot/restore coverage. It also introduces brittle test machinery: the test depends on exact heredoc sentinel formatting inside `session-manager.zsh`.
- Recommendation: move the generated-reaper syntax/elapsed-parser assertions to a dedicated reaper/startup fixture, or at least split them into a clearly named helper block. If kept here, use a single loop over parser functions/cases to avoid duplicating the same `MM:SS`, `HH:MM:SS`, `D-HH:MM:SS`, and invalid-input assertions for generated and main helpers.
- Risk/LOC saved: medium maintenance benefit; likely saves 10-20 LOC and makes scrollback regressions easier to localize. Do not delete the elapsed coverage unless another reaper-focused test owns it.

### R1-BT-4 — low — `restore-id-map.zsh` repeats full `osascript` stubs three times

- Location: `tests/restore-id-map.zsh:38`, `tests/restore-id-map.zsh:94`, `tests/restore-id-map.zsh:125`
- Issue: the success, failure, and restored-success phases rewrite nearly identical `osascript` stubs. This is fixture bloat and makes the test brittle to changes in how AppleScript payloads are recognized (`front window`, `new window`, `new tab`).
- Recommendation: replace the repeated heredocs with one stub that switches behavior on an environment variable or flag file, e.g. `OSASCRIPT_STUB_MODE=success|fail-new-tab`. Keep the same asserted id-map and failure-log behavior.
- Risk/LOC saved: low risk; saves about 25-35 LOC and reduces the chance that one copied stub diverges from another.

### R1-BT-5 — low — `restore-id-map.zsh` has mixed responsibilities beyond restore/id-map

- Location: `tests/restore-id-map.zsh:147`, `tests/restore-id-map.zsh:168`, `tests/restore-id-map.zsh:181`
- Issue: after restore/id-map assertions, the script also verifies first-launch session generation, restore-lock release, one-shot restore election, later fresh session generation, and non-interactive auto-attach guard logging. These were important Phase 2 regressions, but they make the file name and fixture scope misleading.
- Recommendation: either rename/split into two focused fixtures (`restore-id-map.zsh` and `auto-attach-startup.zsh`) or add section helpers so setup is shared but assertion groups are clearly isolated. Do not remove these assertions; they protect design-critical startup behavior.
- Risk/LOC saved: low direct LOC savings; medium readability benefit. Splitting may add a few lines initially but makes future bloat less likely.

### R1-BT-6 — low — E2E fixed sleeps add runtime and timing brittleness where condition waits already exist

- Location: `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-supervisor.zsh:255`, `:259`, `:321`, `:323`, `:337`, `:340`, `:358`
- Issue: the supervisor uses several fixed `sleep 5` / `sleep 8` waits after actions that already have observable success conditions nearby. This inflates run time and can still be flaky if the environment is slower than the fixed sleep.
- Recommendation: replace fixed sleeps with condition-oriented waits where possible, e.g. wait for all expected managed sessions to remain, restored window count/layout shape, managed `clients=1`, snapshot file existence, or expected debug log entries. Keep conservative timeouts; do not weaken the E2E assertions.
- Risk/LOC saved: low-to-medium risk because live Ghostty timing is sensitive; potential runtime saved is roughly 20-30 seconds on successful runs, with improved diagnostics on slow failures.

### R1-BT-7 — low — E2E dumps full state after every successful scenario

- Location: `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-supervisor.zsh:141`, `:266`, `:281`, `:292`, `:301`, `:315`, `:326`, `:348`, `:361`
- Issue: `state_dump` is useful for failure triage, but the harness calls it unconditionally after every scenario. That creates large logs dominated by repeated layout/session/debug-tail output even on passing runs.
- Recommendation: call `state_dump` only on failure, or gate successful dumps behind an env var such as `GHOSTTY_ZMX_E2E_VERBOSE=1`. Preserve the concise `SCENARIO_RESULT` lines and final byte-for-byte restore hashes in the report.
- Risk/LOC saved: low risk; saves little script LOC but significantly reduces log volume and review noise. Failure logs remain available if dumps are emitted only on failed scenarios.

### R1-BT-8 — low — Release-control smoke test is appropriately small; no bloat action recommended

- Location: `tests/release-control.zsh:7`
- Issue: none. The test is grep/JQ-based and shallow, but that matches the deferred tracker rationale for release workflow validation. Adding schema validation now would be more bloat, not less.
- Recommendation: keep as-is for v0.1.
- Risk/LOC saved: none.

## Out-of-scope/deleted-feature check

No current test appears to exercise the declined production migration path or deleted `ghostty-zmx reset` behavior. The installer tests correctly focus on the new package boundaries, managed Ghostty block behavior, uninstall prompts, symlink-safe cleanup, and preserving existing `sessions` state.
