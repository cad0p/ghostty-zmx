# ghostty-zmx v0.1 findings tracker

## Must fix before merge (`fix-now`)

None.

## Open, defer further (`defer`)

| ID | Severity | Source | Summary | Rationale | Owner / deadline |
|---|---:|---|---|---|---|
| R1-SEC-S5 | low | `reviews/phase-1-impl/r1-security-adversarial.md` | Release workflow uses mutable `cad0p/semver-calver-release/release@v1` with write permissions. | The referenced release-control repo's own consumer guidance recommends `@v1`, and the user explicitly requested using that repo for release control. Pinning to a SHA can be revisited once this repo's release-control baseline is established. | Maintainer / before v0.2 or before enabling automated publishing beyond GitHub releases |
| R2-SEC-S6 | low | `reviews/phase-1-impl/r2-security-adversarial.md` | Experimental `/tmp/zmx-*` cleanup is broad. | Production migration cleanup was removed. Residual cleanup of old experimental runtime state is maintainer/user-specific manual work. | Maintainer / manual cleanup only |
| R2-SEC-S7 | low | `reviews/phase-1-impl/r2-security-adversarial.md` | Debug log path permissions are not hardened. | Current logging avoids terminal history content; runtime state dir hardening covers reaper scripts. State-dir hardening can be added if users run with hostile shared XDG paths. | Maintainer / v0.2 |
| R3-C4 | medium | `reviews/phase-1-impl/r3-cumulative-correctness.md` | Reaper can misclassify Cmd-Q as close-all-windows if Ghostty stays alive with zero windows. | v0.1 has no public Ghostty close/quit signal; the existing zero-window grace is covered by manual E2E and can be revisited if a Ghostty close/quit hook becomes available. | Maintainer / after manual E2E or v0.2 |
| R3-COV-1 | medium | `reviews/phase-1-impl/r3-cumulative-coverage.md` | Reaper lifecycle decisions are not covered by automated fixtures. | v0.1 adds restore/id-map and snapshot/injection fixtures; live Ghostty/reaper timing remains covered by manual E2E. | Maintainer / after v0.1 manual E2E |
| R3-COV-2 | medium | `reviews/phase-1-impl/r3-cumulative-coverage.md` | Full restore-driver and auto-attach path is under-tested. | Direct fixture coverage would require a larger subprocess/AppleScript harness; current restore-id-map tests cover the deterministic layout/id-map core. | Maintainer / v0.2 automation |
| R3-COV-3 | medium | `reviews/phase-1-impl/r3-cumulative-coverage.md` | Intentional-close snapshot deletion is not explicitly verified. | Manual E2E covers pane/window close cleanup; automated snapshot tests cover failure preservation and injection seams. | Maintainer / after v0.1 manual E2E |
| R3-COV-6 | low | `reviews/phase-1-impl/r3-cumulative-coverage.md` | Release workflow validation is mostly grep-based/manual. | Current smoke test checks package metadata and workflow shape; full workflow schema validation can be added when CI tooling is established. | Maintainer / v0.2 |
| R3-SA-03 | medium | `reviews/phase-1-impl/r3-cumulative-security-adversarial.md` | External commands are resolved through mutable `PATH`. | Shell integration intentionally runs in user shell environment; documenting and testing through controlled temp-HOME fixtures is the v0.1 boundary. | Maintainer / v0.2 if hardened command lookup is needed |
| R3-SA-07 | low | `reviews/phase-1-impl/r3-cumulative-security-adversarial.md` | Debug logging can expose user-controlled paths. | Debug logging is opt-in and records metadata, not terminal history content. Path redaction can be added if users run with hostile shared XDG paths. | Maintainer / v0.2 |
| R3-CLEAN-C1 | medium | `reviews/phase-1-impl/r3-cumulative-cleanness.md` | Sourced manager exposes a broad private helper surface. | Startup now unfunctions `_ghostty_zmx_*` helpers unless `GHOSTTY_ZMX_KEEP_HELPERS=1` is set for tests; normal users get a minimal sourced surface. | Maintainer / already addressed |
| R3-CLEAN-C2 | medium | `reviews/phase-1-impl/r3-cumulative-cleanness.md` | Generated reaper duplicates core logic and uses unprefixed names. | Standalone reaper is generated to survive terminal/window close; centralizing it is a larger refactor. | Maintainer / v0.2 |
| R3-CLEAN-C5 | medium | `reviews/phase-1-impl/r3-cumulative-cleanness.md` | Restore/layout logic is intermixed and has a nested helper seam. | v0.1 keeps the serial restore algorithm in one auditable path; helper extraction can be revisited after manual E2E stabilizes behavior. | Maintainer / v0.2 |
| R3-CLEAN-C6 | low | `reviews/phase-1-impl/r3-cumulative-cleanness.md` | Noisy `env =` conflict warnings for unrelated settings. | Installer now warns only on auto-attach env conflicts; broader env warning cleanup is not needed for v0.1. | Maintainer / v0.2 |
| R4-C3 | medium | `reviews/phase-1-impl/r4-cumulative-correctness.md` | Restore queue is written before AppleScript layout creation succeeds. | v0.1 restore remains serial and is covered by restore/id-map tests plus planned manual E2E; partial AppleScript failure cleanup can be revisited if manual E2E exposes orphaned sessions. | Maintainer / after manual E2E |
| R4-C4 | low | `reviews/phase-1-impl/r4-cumulative-correctness.md` | Reboot-scrollback test checks print input, not zmx history. | Manual E2E reboot simulation explicitly verifies saved marker in `zmx history <session>`; helper test verifies the deterministic print input. | Maintainer / after v0.1 manual E2E |
| R4-COV-1 | high | `reviews/phase-1-impl/r4-cumulative-coverage.md` | Reaper lifecycle decisions lack automated coverage. | Generated reaper depends on live Ghostty timing; manual E2E scenarios cover close pane, close window, close all windows, Cmd-Q, and unmanaged-session preservation. | Maintainer / after v0.1 manual E2E |
| R4-COV-2 | medium | `reviews/phase-1-impl/r4-cumulative-coverage.md` | Restore AppleScript path is only partially covered. | Restore-id-map fixture covers deterministic grouping/id-map behavior; AppleScript surface creation is covered by manual E2E. | Maintainer / v0.2 automation |
| R4-COV-3 | medium | `reviews/phase-1-impl/r4-cumulative-coverage.md` | Reboot scrollback `zmx run` failure path is untested. | The implementation logs and continues to `zmx print`; this edge path is lower priority than successful reboot injection and will be covered if manual E2E exposes issues. | Maintainer / v0.2 |
| R4-COV-4 | medium | `reviews/phase-1-impl/r4-cumulative-coverage.md` | Manual E2E checklist needs more concrete verification commands. | The checklist is actionable; exact command polish can be added during manual E2E execution without changing implementation. | Maintainer / during manual E2E |
| R4-COV-5 | low | `reviews/phase-1-impl/r4-cumulative-coverage.md` | Backup creation is not directly asserted. | Installer/uninstaller backup paths are exercised by smoke tests; direct backup-content assertions can be added in v0.2 if desired. | Maintainer / v0.2 |
| R4-COV-6 | low | `reviews/phase-1-impl/r4-cumulative-coverage.md` | Release-control validation is shallow. | Current smoke test checks package metadata, workflow action, permissions, branch trigger, and deferred package-version docs; full YAML schema validation can be added when CI tooling is established. | Maintainer / v0.2 |
| R4-SA-03 | medium | `reviews/phase-1-impl/r4-cumulative-security-adversarial.md` | User-controlled XDG/TMP roots can redirect runtime, state, and map files. | v0.1 intentionally uses XDG/TMP-derived per-user paths and validates the runtime directory; broader root hardening is a larger refactor. | Maintainer / v0.2 |
| R4-SA-07 | low | `reviews/phase-1-impl/r4-cumulative-security-adversarial.md` | Debug log path metadata is user-controlled and state dir permissions are not hardened. | Debug logging is opt-in and records metadata, not terminal history content. State-dir hardening can be added if users run with hostile shared XDG paths. | Maintainer / v0.2 |
| R2-E2E-ADV-1 | medium | `reviews/phase-2-e2e/r2-adversarial.md` | Reboot scrollback path can log successful restore after `zmx run` failure. | Live E2E proves the success path; failure-path hardening can re-check session existence before `zmx print` in v0.2. | Maintainer / v0.2 |
| R2-E2E-ADV-2 | medium | `reviews/phase-2-e2e/r2-adversarial.md` | Stale restore-in-progress flag can suppress cleanup if the restore driver is killed mid-restore. | Live E2E passed; add TTL/self-expiring restore flags in v0.2 for crash resilience. | Maintainer / v0.2 |
| R2-E2E-ADV-3 | low | `reviews/phase-2-e2e/r2-adversarial.md` | Session log updates are not serialized between attach and reaper cleanup. | No live race observed; shared locking around all `sessions` mutations can be added in v0.2. | Maintainer / v0.2 |
| R2-E2E-ADV-4 | low | `reviews/phase-2-e2e/r2-adversarial.md` | Reaper depends on current tabular `zmx list` field ordering. | Tested zmx 0.6.x output matches parser; key-based parsing can be added in v0.2 if zmx CLI shape changes. | Maintainer / v0.2 |

## Declined — wrong, non-applicable, or out-of-scope, with rationale citing contradicting evidence

| ID | Severity | Source | Summary | Rationale |
|---|---:|---|---|---|
| R1-CORR-C1 / R1-CLEAN-C1 / R2-CLEAN-1 | block/high | `reviews/phase-1-impl/r1-correctness.md`, `reviews/phase-1-impl/r1-cleanness.md`, `reviews/phase-1-impl/r2-cleanness.md` | Installed/documented `.zshrc` source line allegedly contains literal backslash-escaped quotes. | Current branch bytes show normal quote characters and no backslash characters in `install.sh`, `uninstall.sh`, `README.md`, and tests. Verified with Python `repr`: `source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"'`. |
| R3-C2 / R3-COV-2 migration rows | high/medium | `reviews/phase-1-impl/r3-cumulative-correctness.md`, `reviews/phase-1-impl/r3-cumulative-coverage.md` | Experimental migration path handling. | Maintainer clarified that v0.1 is a new package and production migration code should not exist. The code now documents manual experimental cleanup instead; migration-specific fixtures were removed. |
| R4-C1 | high | `reviews/phase-1-impl/r4-cumulative-correctness.md` | AppleScript snippets call zsh-only helper names. | Fixed in `2cbfc65`: AppleScript payloads now return raw Ghostty IDs; zsh hashes them with `_ghostty_zmx_applescript_ids`. |
| R4-C2 | high | `reviews/phase-1-impl/r4-cumulative-correctness.md` | Reaper state updates are lost in pipeline subshells. | Fixed in `2cbfc65`: stateful reaper loops now use process substitution so `attached` and `detachedSeen` updates persist in the parent shell. |
| R4-CLEAN-C1 | medium | `reviews/phase-1-impl/r4-cumulative-cleanness.md` | Private manager helpers remain in the sourced shell namespace. | Normal sourced startup now unfunctions `_ghostty_zmx_*` helpers unless `GHOSTTY_ZMX_KEEP_HELPERS=1` is set for tests. |
| R4-CLEAN-C2 | medium | `reviews/phase-1-impl/r4-cumulative-cleanness.md` | Test-only Ghostty config override is part of the public script surface. | Renamed to `GHOSTTY_ZMX_INTERNAL_TEST_GHOSTTY_CONFIG`; README no longer documents it as a user-facing knob. |
| R4-CLEAN-C3 | medium | `reviews/phase-1-impl/r4-cumulative-cleanness.md` | Installer performs experimental setup cleanup by default. | Fixed in `1dece19`: default installer no longer cleans old experimental runtime flags. |
| R4-CLEAN-C4 | low | `reviews/phase-1-impl/r4-cumulative-cleanness.md` | Unused installer variable. | Fixed in `1dece19`: removed unused `data_home` from installer. |
| R4-CLEAN-C5 | low | `reviews/phase-1-impl/r4-cumulative-cleanness.md` | README lists too many runtime internals as user-facing paths. | Fixed in `db36ab6`: README now describes runtime files as internal without listing implementation files. |
| R4-CLEAN-C6 | low | `reviews/phase-1-impl/r4-cumulative-cleanness.md` | Duplicated standalone helper logic in generated reaper script. | The generated reaper must be standalone; `2cbfc65` documents the intentional mirrored copy near the generated script. |
| R4-SA-05 | medium | `reviews/phase-1-impl/r4-cumulative-security-adversarial.md` | Reaper may miscount attached managed sessions. | Fixed in `2cbfc65`: stateful reaper loops no longer run on the right side of a pipeline. |
| R4-SA-06 | low | `reviews/phase-1-impl/r4-cumulative-security-adversarial.md` | Release workflow grants `pull-requests: read`. | Fixed in `aaaf9a8`: release workflow now grants only `contents: write`. |

## Re-declined — re-flagged after a prior decline, prior decline's rationale + reason for re-decline

| ID | Severity | Source | Summary | Prior rationale | Reason for re-decline |
|---|---:|---|---|---|---|
| R2-CLEAN-1 | high | `reviews/phase-1-impl/r2-cleanness.md` | Re-flagged escaped `.zshrc` source line. | Prior decline verified current bytes contain normal quotes, not backslashes. | Re-flag appears to be report/rendering confusion; no code change needed. |

## Fixed before merge — traceability

- `e049397` — hardens runtime locks/session validation and addresses predictable reaper paths plus restore-driver atomic locking.
- `0374992` — fixes app-quit preservation/snapshot semantics and adds snapshot/reaper-oriented executable coverage.
- `a38914c` — targets restored Ghostty windows/tabs explicitly and avoids writing misleading id-map entries on mismatch.
- `9fce39e` — makes migration/uninstall safer, documents the Ghostty config override, and adds installer/uninstaller coverage plus verification docs.
- `f3e03b7` — localizes sourced-shell state and removes straightforward stale helper surface.
- `b659bee` — makes scrollback snapshotting failure-safe and validates scrollback line limits.
- `ef9cdc4` — hardens restore locking, id-map writes, and session-name validation.
- `27da8f5` — hardens installer migration handling and coverage.
- `bc9b50c` — guards reaper shutdown against PID reuse and cleans current runtime directory.
- `f845299` — adds remaining shell coverage for restore/id-map, uninstall prompts, and release-control smoke.
- `0a93cf3` — documents private runtime layout and `--yes` uninstall behavior.
- `90fdb40` — isolates snapshot runtime fixture to avoid cross-test runtime-dir races.
- `4d94072` — parses AppleScript IDs by hex suffix and removes migration-path assumptions from the ID code path.
- `b6ad3c9` — narrows Ghostty config handling before migration code was removed.
- `ed316b8` — hardens installer/uninstaller file-boundary behavior, symlink refusal, backup uniqueness, atomic edit status checks, and runtime cleanup.
- `d6ce41b` — documents that experimental setup cleanup is manual/out-of-band for v0.1.
- `6fa1141` — updates release verification guidance to match manual cleanup and `GHOSTTY_ZMX_TEST_GHOSTTY_CONFIG`.
- `762a0ae` — removes the unused restore cleanup constant and test assignment.
- `1dece19` — removes default experimental cleanup, renames the test-only Ghostty config override, and unfunctions private startup helpers in normal use.
- `db36ab6` — reduces runtime internals exposure in README.
- `2cbfc65` — fixes AppleScript handler calls, reaper pipeline subshell state loss, and documents generated reaper helper duplication.
- `aaaf9a8` — validates managed Ghostty block pairs, closes install-dir symlink TOCTOU, and removes unused release PR-read permission.
- `12ca3f5` — records r4 fresh implementation review reports.
- `451ba52` — fixes generated reaper syntax by removing invalid AppleScript handlers and adds generated-reaper syntax coverage.
- `6ff0480` — releases the restore-driver election lock after startup and adds restore-lock coverage.
- `5cb127f` — adds first-launch auto-attach debug tracing and verifies generated first-launch session logging.
- `aba667f` — records the partial E2E run that exposed unsafe blocking `zmx run` marker injection.
- `c11cb63` — records the supervised E2E rerun harness and the restore-election implementation blocker.
- `47479e6` — makes restore-driver election one-shot per Ghostty process and fixes new split/tab/window session generation in live E2E.
- `8fefa35` — accepts `MM:SS`, `HH:MM:SS`, and `D-HH:MM:SS` elapsed formats so the reaper no longer exits immediately for young Ghostty processes on macOS.
- `17f754c` — makes restore queue exposure incremental and fixes Ghostty restore surface creation before reattaching sessions.
- `7dc6eb0` — tightens E2E Cmd-Q restore assertions to require layout shape, all clients attached, markers in zmx history, and no restore failure debug entries.

## Diagnostic-message deviations — deviate-with-rationale entries

None yet.

## Methodology observations — patterns to carry into next review

- Review prompts were written and then sanitized to avoid status wording before spawning reviewers.
- Four fresh implementation reviews completed, then one fixer pass, then a second fresh review batch and second fixer pass.
- A cumulative review was run after the second fixer pass; accepted medium/high findings were fixed, and migration-specific findings were reclassified after maintainer clarification that v0.1 should not contain production migration code.
- A fresh r4 review caught real high-severity correctness regressions in AppleScript handler scope and zsh pipeline subshell state handling; both were fixed before tracker reconciliation.
- Phase 2 E2E required supervised live Ghostty runs with byte-for-byte config/install restoration. Harness failures were separated from implementation failures; implementation fixes landed for restore re-election and reaper elapsed parsing before all eight E2E scenarios passed.
- Phase 2 adversarial review initially found no fix-now blockers after a passing supervised run, but the cumulative adversarial pass caught that the harness did not assert layout/client invariants for Cmd-Q restore. A stricter live rerun then passed with layout shape, all clients attached, zmx history markers, and no restore failure logs.
