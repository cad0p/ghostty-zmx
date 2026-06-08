# ghostty-zmx v0.1 findings tracker

## Must fix before merge (`fix-now`)

None.

## Open, defer further (`defer`)

| ID | Severity | Source | Summary | Rationale | Owner / deadline |
|---|---:|---|---|---|---|
| R1-SEC-S5 | low | `reviews/phase-1-impl/r1-security-adversarial.md` | Release workflow uses mutable `cad0p/semver-calver-release/release@v1` with write permissions. | The referenced release-control repo's own consumer guidance recommends `@v1`, and the user explicitly requested using that repo for release control. Pinning to a SHA can be revisited once this repo's release-control baseline is established. | Maintainer / before v0.2 or before enabling automated publishing beyond GitHub releases |
| R2-SEC-S6 | low | `reviews/phase-1-impl/r2-security-adversarial.md` | Experimental `/tmp/zmx-*` cleanup is broad. | It is scoped to the known experimental lock/script/log name prefixes under sticky `/tmp`, and full ownership-safe cleanup would require a more invasive runtime-state migration. | Maintainer / v0.2 cleanup |
| R2-SEC-S7 | low | `reviews/phase-1-impl/r2-security-adversarial.md` | Debug log path permissions are not hardened. | Current logging avoids terminal history content; runtime state dir hardening covers reaper scripts. State-dir hardening can be added if users run with hostile shared XDG paths. | Maintainer / v0.2 |
| R3-C4 | medium | `reviews/phase-1-impl/r3-cumulative-correctness.md` | Reaper can misclassify Cmd-Q as close-all-windows if Ghostty stays alive with zero windows. | v0.1 has no public Ghostty close/quit signal; the existing zero-window grace is covered by manual E2E and can be revisited if a Ghostty close/quit hook becomes available. | Maintainer / after manual E2E or v0.2 |
| R3-COV-1 | medium | `reviews/phase-1-impl/r3-cumulative-coverage.md` | Reaper lifecycle decisions are not covered by automated fixtures. | v0.1 adds restore/id-map and snapshot/injection fixtures; live Ghostty/reaper timing remains covered by manual E2E. | Maintainer / after v0.1 manual E2E |
| R3-COV-2 | medium | `reviews/phase-1-impl/r3-cumulative-coverage.md` | Full restore-driver and auto-attach path is under-tested. | Direct fixture coverage would require a larger subprocess/AppleScript harness; current restore-id-map tests cover the deterministic layout/id-map core. | Maintainer / v0.2 automation |
| R3-COV-3 | medium | `reviews/phase-1-impl/r3-cumulative-coverage.md` | Intentional-close snapshot deletion is not explicitly verified. | Manual E2E covers pane/window close cleanup; automated snapshot tests cover failure preservation and injection seams. | Maintainer / after v0.1 manual E2E |
| R3-COV-6 | low | `reviews/phase-1-impl/r3-cumulative-coverage.md` | Release workflow validation is mostly grep-based/manual. | Current smoke test checks package metadata and workflow shape; full workflow schema validation can be added when CI tooling is established. | Maintainer / v0.2 |
| R3-SA-03 | medium | `reviews/phase-1-impl/r3-cumulative-security-adversarial.md` | External commands are resolved through mutable `PATH`. | Shell integration intentionally runs in user shell environment; documenting and testing through controlled temp-HOME fixtures is the v0.1 boundary. | Maintainer / v0.2 if hardened command lookup is needed |
| R3-SA-07 | low | `reviews/phase-1-impl/r3-cumulative-security-adversarial.md` | Debug logging can expose user-controlled paths. | Debug logging is opt-in and records metadata, not terminal history content. Path redaction can be added if users run with hostile shared XDG paths. | Maintainer / v0.2 |
| R3-SA-08 | low | `reviews/phase-1-impl/r3-cumulative-security-adversarial.md` | Release workflow action is not pinned by SHA. | User explicitly requested `cad0p/semver-calver-release/release@v1`; the release-control repo recommends that tag. | Maintainer / before v0.2 or before enabling automated publishing beyond GitHub releases |
| R3-CLEAN-C1 | medium | `reviews/phase-1-impl/r3-cumulative-cleanness.md` | Sourced manager exposes a broad private helper surface. | Helpers are prefixed private implementation details; removing them requires a larger testability refactor. | Maintainer / v0.2 |
| R3-CLEAN-C2 | medium | `reviews/phase-1-impl/r3-cumulative-cleanness.md` | Generated reaper duplicates core logic and uses unprefixed names. | Standalone reaper is generated to survive terminal/window close; centralizing it is a larger refactor. | Maintainer / v0.2 |
| R3-CLEAN-C5 | medium | `reviews/phase-1-impl/r3-cumulative-cleanness.md` | Restore/layout logic is intermixed and has a nested helper seam. | v0.1 keeps the serial restore algorithm in one auditable path; helper extraction can be revisited after manual E2E stabilizes behavior. | Maintainer / v0.2 |
| R3-CLEAN-C6 | low | `reviews/phase-1-impl/r3-cumulative-cleanness.md` | Noisey `env =` conflict warnings for unrelated settings. | Installer now warns only on auto-attach env conflicts; broader env warning cleanup is not needed for v0.1. | Maintainer / v0.2 |

## Declined — wrong, non-applicable, or out-of-scope, with rationale citing contradicting evidence

| ID | Severity | Source | Summary | Rationale |
|---|---:|---|---|---|
| R1-CORR-C1 / R1-CLEAN-C1 / R2-CLEAN-1 | block/high | `reviews/phase-1-impl/r1-correctness.md`, `reviews/phase-1-impl/r1-cleanness.md`, `reviews/phase-1-impl/r2-cleanness.md` | Installed/documented `.zshrc` source line allegedly contains literal backslash-escaped quotes. | Current branch bytes show normal quote characters and no backslash characters in `install.sh`, `uninstall.sh`, `README.md`, and tests. Verified with Python `repr`: `source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"'`. |
| R3-C2 / R3-COV-2 migration rows | high/medium | `reviews/phase-1-impl/r3-cumulative-correctness.md`, `reviews/phase-1-impl/r3-cumulative-coverage.md` | Experimental migration path handling. | Maintainer clarified that v0.1 is a new package and production migration code should not exist. The code now documents manual experimental cleanup instead; migration-specific fixtures were removed. |

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

## Diagnostic-message deviations — deviate-with-rationale entries

None yet.

## Methodology observations — patterns to carry into next review

- Review prompts were written and then sanitized to avoid status wording before spawning reviewers.
- Four fresh implementation reviews completed, then one fixer pass, then a second fresh review batch and second fixer pass.
- A cumulative review was run after the second fixer pass; accepted medium/high findings were fixed, and migration-specific findings were reclassified after maintainer clarification that v0.1 should not contain production migration code.
