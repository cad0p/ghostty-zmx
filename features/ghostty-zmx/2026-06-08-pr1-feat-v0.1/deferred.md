# ghostty-zmx v0.1 findings tracker

## Must fix before merge (`fix-now`)

| ID | Severity | Source | Summary | Required fix | Commit |
|---|---:|---|---|---|---|
| R1-CORR-C2 | high | `reviews/phase-1-impl/r1-correctness.md` | Reaper can miss Cmd-Q snapshots or misclassify gradual app quit as intentional closes. | Add a stable close-vs-quit heuristic, snapshot all managed sessions before reaper exits on Ghostty termination, and avoid destructive cleanup until a detached state is stable enough to classify. | `0374992` |
| R1-CORR-C3 | high | `reviews/phase-1-impl/r1-correctness.md` | Restore uses `front window` / focused terminal and can corrupt layout/id-map when focus moves. | Drive restore against explicit physical window/tab IDs or deliberately activate and verify the intended physical window/tab before writing id-map or creating splits. | `a38914c` |
| R1-CORR-C4 | medium | `reviews/phase-1-impl/r1-correctness.md` | Known experimental `confirm-close-surface = false` may remain outside managed block. | Remove the exact experimental false line after backup/confirmation or fail with explicit remediation; update tests/docs. | `27da8f5` |
| R1-SEC-S1 | high | `reviews/phase-1-impl/r1-security-adversarial.md` | Predictable `/tmp` reaper script/log paths can be symlink-clobbered. | Use a private runtime directory or installed helper path; avoid writing executable/log files to predictable `/tmp` filenames. | `e049397` |
| R1-SEC-S2 | medium | `reviews/phase-1-impl/r1-security-adversarial.md` | Persisted session names are trusted before path construction/destructive zmx operations. | Validate canonical session names at read/migration/use boundaries; skip/log invalid entries; prevent path traversal in history filenames. | `e049397`, `ef9cdc4` |
| R1-SEC-S3 / R1-CLEAN-C2 | medium | `reviews/phase-1-impl/r1-security-adversarial.md`, `reviews/phase-1-impl/r1-cleanness.md` | `uninstall.sh --yes` can recursively delete env-selected data/state directories and is unexpectedly destructive. | Make `--yes` non-destructive for data/state by default; require explicit destructive flags and refuse unsafe paths. | `9fce39e` |
| R1-SEC-S4 | medium | `reviews/phase-1-impl/r1-security-adversarial.md` | Restore-driver election uses non-atomic predictable `/tmp` flag. | Use atomic lock directory creation, preferably under a safe private runtime directory, and clean up safely. | `e049397` |
| R1-CLEAN-C3 | medium | `reviews/phase-1-impl/r1-cleanness.md` | Sourced runtime leaks unprefixed globals into user shells. | Wrap the top-level auto-attach logic in a prefixed function with local variables; avoid leaking `SESSION_NAME`, `POSITION`, etc. | `f3e03b7` |
| R1-CLEAN-C5 | low | `reviews/phase-1-impl/r1-cleanness.md` | `GHOSTTY_ZMX_GHOSTTY_CONFIG` override is undocumented. | Document as an advanced/testing override or remove it. | `9fce39e` |
| R1-CLEAN-C6 | low | `reviews/phase-1-impl/r1-cleanness.md` | Runtime waits/retries are unnamed magic numbers. | Promote to named internal constants with rationale comments; expose only intended knobs. | `e049397`, `0374992` |
| R1-COV-1 | medium | `reviews/phase-1-impl/r1-coverage.md` | No executable coverage exists for installer/migration paths. | Add lightweight temp-HOME shell tests for installer migration, idempotency, conflict warnings, interactive decline, and `--yes`. | `9fce39e`, `27da8f5` |
| R1-COV-2 | medium | `reviews/phase-1-impl/r1-coverage.md` | Restore/reaper behavior lacks fixture-level validation seams. | Add testable helper/seams or fixture tests for reaper decision parsing and managed/unmanaged behavior. | `f845299` |
| R1-COV-3 | medium | `reviews/phase-1-impl/r1-coverage.md` | Snapshot/truncation/injection edge cases lack executable validation. | Add stubbed zmx tests for line limits, banner ordering, failure logging without saved content, and intentional-close deletion. | `0374992`, `b659bee`, `90fdb40` |
| R1-COV-4 | low | `reviews/phase-1-impl/r1-coverage.md` | Manual docs omit an installer/release pre-merge verification matrix. | Add documented pre-merge verification steps for syntax, installer temp-HOME paths, uninstall, `jq`, and release workflow sanity. | `9fce39e`, `f845299` |
| R2-C1 | high | `reviews/phase-1-impl/r2-correctness.md` | `zmx history` pipeline failures can overwrite or empty scrollback snapshots. | Capture `zmx history` output to a temporary file and check its exit status before truncating/moving the snapshot into place. | `b659bee` |
| R2-C2 | medium | `reviews/phase-1-impl/r2-correctness.md` | Restore lock can be removed before serial restore has fully completed. | Keep the restore lock for a duration derived from session count and restore step delay, plus a conservative AppleScript margin. | `ef9cdc4` |
| R2-C3 | medium | `reviews/phase-1-impl/r2-correctness.md` | Unterminated experimental `.zshrc` block is not fatal before adding the new source line. | Abort installation or repair the unterminated block before appending the new source line. | `27da8f5` |
| R2-C4 | medium | `reviews/phase-1-impl/r2-correctness.md` | Fresh-session detection treats `zmx list --short` failure as “session missing.” | Explicitly check the exit status of `zmx list --short`; skip injection and log failure on command failure. | `b659bee` |
| R2-C5 | low | `reviews/phase-1-impl/r2-correctness.md` | Managed session-name validation is broader than the canonical spec. | Tighten managed-name validation to hexadecimal window/tab components and eight-character terminal component. | `ef9cdc4` |
| R2-SEC-S1 | medium | `reviews/phase-1-impl/r2-security-adversarial.md` | Reaper can act after Ghostty PID reuse and delete preserved sessions. | Stop cleanup when the original app instance exits; use elapsed-time guard and snapshot preserved sessions before exit. | `bc9b50c` |
| R2-SEC-S2 | medium | `reviews/phase-1-impl/r2-security-adversarial.md` | Physical Ghostty IDs are used in regex filters before validation. | Validate physical window/tab IDs before filtering/writing id-map. | `ef9cdc4` |
| R2-SEC-S3 | medium | `reviews/phase-1-impl/r2-security-adversarial.md` | Installer removes `confirm-close-surface = false` outside the managed block. | Limit removal to documented experimental migration context and make the plan/test coverage explicit. | `27da8f5` |
| R2-SEC-S4 | low | `reviews/phase-1-impl/r2-security-adversarial.md` | Uninstaller does not clean the current per-user runtime directory. | Teach uninstall to remove the expected owned per-user runtime directory and refuse unsafe paths. | `bc9b50c` |
| R2-SEC-S5 | low | `reviews/phase-1-impl/r2-security-adversarial.md` | Scrollback line limit is not numerically validated. | Validate positive integer and default to `1000` on invalid input. | `b659bee` |
| R2-COV-1 | medium | `reviews/phase-1-impl/r2-coverage.md` | Restore and reaper behavior is mostly manual-only. | Add feasible fixture coverage for restore grouping/id-map behavior and snapshot/injection seams. | `f845299` |
| R2-COV-2 | medium | `reviews/phase-1-impl/r2-coverage.md` | Installer migration edge cases are not fully covered. | Add fixtures for unterminated blocks, existing sessions file, stale runtime flags, and live-session preservation. | `27da8f5` |
| R2-COV-3 | medium | `reviews/phase-1-impl/r2-coverage.md` | Interactive install acceptance is only partially exercised. | Add deterministic `printf 'y\n'` install fixture and plan-output assertions. | `27da8f5` |
| R2-COV-4 | low | `reviews/phase-1-impl/r2-coverage.md` | Release-control validation is declarative rather than executable. | Add lightweight release-control smoke test for package metadata and workflow shape. | `f845299` |
| R2-COV-5 | low | `reviews/phase-1-impl/r2-coverage.md` | Uninstall interactive behavior is not covered. | Add fixtures for interactive decline and acceptance. | `f845299` |
| R2-CLEAN-2 | medium | `reviews/phase-1-impl/r2-cleanness.md` | Runtime file layout is implicit and uninstaller targets stale paths. | Document per-user runtime directory and teach uninstall to safely remove it. | `0a93cf3`, `bc9b50c` |
| R2-CLEAN-3 | medium | `reviews/phase-1-impl/r2-cleanness.md` | Installer deletes an unmanaged Ghostty setting despite promising to leave conflicts alone. | Keep automatic edits scoped to managed block plus explicit documented experimental migration for `confirm-close-surface = false`. | `27da8f5` |
| R2-CLEAN-5 | low | `reviews/phase-1-impl/r2-cleanness.md` | `--yes` uninstaller behavior is not explicit about Ghostty config removal. | Document `--yes` removes managed Ghostty block while preserving install/data/state unless destructive flags are passed. | `0a93cf3` |

## Open, defer further (`defer`)

| ID | Severity | Source | Summary | Rationale | Owner / deadline |
|---|---:|---|---|---|---|
| R1-SEC-S5 | low | `reviews/phase-1-impl/r1-security-adversarial.md` | Release workflow uses mutable `cad0p/semver-calver-release/release@v1` with write permissions. | The referenced release-control repo's own consumer guidance recommends `@v1`, and the user explicitly requested using that repo for release control. Pinning to a SHA can be revisited once this repo's release-control baseline is established. | Maintainer / before v0.2 or before enabling automated publishing beyond GitHub releases |
| R2-SEC-S6 | low | `reviews/phase-1-impl/r2-security-adversarial.md` | Experimental `/tmp/zmx-*` cleanup is broad. | It is scoped to the known experimental lock/script/log name prefixes under sticky `/tmp`, and full ownership-safe cleanup would require a more invasive runtime-state migration. | Maintainer / v0.2 cleanup |
| R2-SEC-S7 | low | `reviews/phase-1-impl/r2-security-adversarial.md` | Debug log path permissions are not hardened. | Current logging avoids terminal history content; runtime state dir hardening covers reaper scripts. State-dir hardening can be added if users run with hostile shared XDG paths. | Maintainer / v0.2 |
| R2-COV-1 | medium | `reviews/phase-1-impl/r2-coverage.md` | Full generated reaper decision-loop fixture coverage remains limited. | v0.1 adds restore/id-map and snapshot/injection fixtures; live Ghostty/reaper timing remains covered by manual E2E. | Maintainer / after v0.1 manual E2E |
| R2-CLEAN-4 | low | `reviews/phase-1-impl/r2-cleanness.md` | Conflict warning treats all `env =` lines as ghostty-zmx conflicts. | Low-severity warning noise; installer leaves unrelated env lines untouched. Can refine in a follow-up. | Maintainer / v0.2 |
| R2-CLEAN-6 | low | `reviews/phase-1-impl/r2-cleanness.md` | Internal helper functions remain in the interactive shell namespace. | Helpers are prefixed private implementation details; removing them requires a larger testability refactor. | Maintainer / v0.2 |

## Declined — wrong, non-applicable, or out-of-scope, with rationale citing contradicting evidence

| ID | Severity | Source | Summary | Rationale |
|---|---:|---|---|---|
| R1-CORR-C1 / R1-CLEAN-C1 / R2-CLEAN-1 | block/high | `reviews/phase-1-impl/r1-correctness.md`, `reviews/phase-1-impl/r1-cleanness.md`, `reviews/phase-1-impl/r2-cleanness.md` | Installed/documented `.zshrc` source line allegedly contains literal backslash-escaped quotes. | Current branch bytes show normal quote characters and no backslash characters in `install.sh`, `uninstall.sh`, `README.md`, and tests. Verified with Python `repr`: `source_line='[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"'`. |

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

## Diagnostic-message deviations — deviate-with-rationale entries

None yet.

## Methodology observations — patterns to carry into next review

- Review prompts were written and then sanitized to avoid status wording before spawning reviewers.
- Four fresh implementation reviews completed, then one fixer pass, then a second fresh review batch and second fixer pass.
- r2 source-line quote finding was declined after byte-level verification.
