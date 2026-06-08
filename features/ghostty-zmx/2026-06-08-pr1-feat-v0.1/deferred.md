# ghostty-zmx v0.1 findings tracker

## Must fix before merge (`fix-now`)

| ID | Severity | Source | Summary | Required fix | Commit |
|---|---:|---|---|---|---|
| CORR-C2 | high | `reviews/phase-1-impl/r1-correctness.md` | Reaper can miss Cmd-Q snapshots or misclassify gradual app quit as intentional closes. | Add a stable close-vs-quit heuristic, snapshot all managed sessions before reaper exits on Ghostty termination, and avoid destructive cleanup until a detached state is stable enough to classify. | `0374992` |
| CORR-C3 | high | `reviews/phase-1-impl/r1-correctness.md` | Restore uses `front window` / focused terminal and can corrupt layout/id-map when focus moves. | Drive restore against explicit physical window/tab IDs or deliberately activate and verify the intended physical window/tab before writing id-map or creating splits. | `a38914c` |
| CORR-C4 | medium | `reviews/phase-1-impl/r1-correctness.md` | Known experimental `confirm-close-surface = false` may remain outside managed block. | During migration, remove the exact experimental false line after backup/confirmation or fail with explicit remediation; update tests/docs. | `9fce39e` |
| SEC-S1 | high | `reviews/phase-1-impl/r1-security-adversarial.md` | Predictable `/tmp` reaper script/log paths can be symlink-clobbered. | Use a private runtime directory or installed helper path; avoid writing executable/log files to predictable `/tmp` filenames. | `e049397` |
| SEC-S2 | medium | `reviews/phase-1-impl/r1-security-adversarial.md` | Persisted session names are trusted before path construction/destructive zmx operations. | Validate canonical session names at read/migration/use boundaries; skip/log invalid entries; prevent path traversal in history filenames. | `e049397` |
| SEC-S3 / CLEAN-C2 | medium | `reviews/phase-1-impl/r1-security-adversarial.md`, `reviews/phase-1-impl/r1-cleanness.md` | `uninstall.sh --yes` can recursively delete env-selected data/state directories and is unexpectedly destructive. | Make `--yes` non-destructive for data/state by default; require explicit destructive flags and refuse unsafe paths. | `9fce39e` |
| SEC-S4 | medium | `reviews/phase-1-impl/r1-security-adversarial.md` | Restore-driver election uses non-atomic predictable `/tmp` flag. | Use atomic lock directory creation, preferably under a safe private runtime directory, and clean up safely. | `e049397` |
| CLEAN-C3 | medium | `reviews/phase-1-impl/r1-cleanness.md` | Sourced runtime leaks unprefixed globals into user shells. | Wrap the top-level auto-attach logic in a prefixed function with local variables; avoid leaking `SESSION_NAME`, `POSITION`, etc. | `f3e03b7` |
| CLEAN-C5 | low | `reviews/phase-1-impl/r1-cleanness.md` | `GHOSTTY_ZMX_GHOSTTY_CONFIG` override is undocumented. | Document as an advanced/testing override or remove it. | `9fce39e` |
| CLEAN-C6 | low | `reviews/phase-1-impl/r1-cleanness.md` | Runtime waits/retries are unnamed magic numbers. | Promote to named internal constants with rationale comments; expose only intended knobs. | `e049397`, `0374992` |
| COV-1 | medium | `reviews/phase-1-impl/r1-coverage.md` | No executable coverage exists for installer/migration paths. | Add lightweight temp-HOME shell tests for installer migration, idempotency, conflict warnings, interactive decline, and `--yes`. | `9fce39e` |
| COV-2 | medium | `reviews/phase-1-impl/r1-coverage.md` | Restore/reaper behavior lacks fixture-level validation seams. | Add testable helper/seams or fixture tests for reaper decision parsing and managed/unmanaged behavior. | `0374992` |
| COV-3 | medium | `reviews/phase-1-impl/r1-coverage.md` | Snapshot/truncation/injection edge cases lack executable validation. | Add stubbed zmx tests for line limits, banner ordering, failure logging without saved content, and intentional-close deletion. | `0374992` |
| COV-4 | low | `reviews/phase-1-impl/r1-coverage.md` | Manual docs omit an installer/release pre-merge verification matrix. | Add documented pre-merge verification steps for syntax, installer temp-HOME paths, uninstall, `jq`, and release workflow sanity. | `9fce39e` |

## Open, defer further (`defer`)

| ID | Severity | Source | Summary | Rationale | Owner / deadline |
|---|---:|---|---|---|---|
| SEC-S5 | low | `reviews/phase-1-impl/r1-security-adversarial.md` | Release workflow uses mutable `cad0p/semver-calver-release/release@v1` with write permissions. | The referenced release-control repo's own consumer guidance recommends `@v1`, and the user explicitly requested using that repo for release control. Pinning to a SHA can be revisited once this repo's release-control baseline is established. | Maintainer / before v0.2 or before enabling automated publishing beyond GitHub releases |

## Declined — wrong, non-applicable, or out-of-scope, with rationale citing contradicting evidence

| ID | Severity | Source | Summary | Rationale |
|---|---:|---|---|---|
| CORR-C1 / CLEAN-C1 | block/high | `reviews/phase-1-impl/r1-correctness.md`, `reviews/phase-1-impl/r1-cleanness.md` | Installed/documented `.zshrc` source line allegedly contains literal backslash-escaped quotes. | Current branch bytes show normal quote characters and no backslash characters in `install.sh:27`, `uninstall.sh:22`, and `README.md:38`. Verified with `od`: quote bytes are `0x22`, with no preceding `0x5c`. The report appears to have interpreted JSON/markdown escaping as file content. |

## Re-declined — re-flagged after a prior decline, prior decline's rationale + reason for re-decline

None yet.

## Fixed before merge — traceability

- `e049397` — hardens runtime locks/session validation and addresses predictable reaper paths plus restore-driver atomic locking.
- `0374992` — fixes app-quit preservation/snapshot semantics and adds snapshot/reaper-oriented executable coverage.
- `a38914c` — targets restored Ghostty windows/tabs explicitly and avoids writing misleading id-map entries on mismatch.
- `9fce39e` — makes migration/uninstall safer, documents the Ghostty config override, and adds installer/uninstaller coverage plus verification docs.
- `f3e03b7` — localizes sourced-shell state and removes straightforward stale helper surface.

## Diagnostic-message deviations — deviate-with-rationale entries

None yet.

## Methodology observations — patterns to carry into next review

- Review prompts were written and then sanitized to avoid status wording before spawning reviewers.
- Four fresh implementation reviews completed: correctness, coverage, cleanness/API surface, and security/adversarial.
