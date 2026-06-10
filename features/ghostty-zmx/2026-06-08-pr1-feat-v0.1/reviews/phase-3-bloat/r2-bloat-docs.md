# Phase 3 bloat-docs review — r2 post-fixer

Scope reviewed in full:

- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-3-bloat/r1-bloat-docs.md`
- `README.md`
- `RELEASE.md`
- `docs/manual-e2e.md`

Additional focus:

- `0ed05c4` (`docs: narrow public README surface`)
- `2e2d80a` (`docs: trim release and e2e checklist prose`)

## Result

No remaining fix-now documentation bloat, stale public references, or unsafe over-trim found.

## Verification notes

- `README.md` no longer documents `GHOSTTY_ZMX_INTERNAL_TEST_GHOSTTY_CONFIG` as a user-facing knob.
- `README.md` no longer has the user-facing `Release control` section; release mechanics remain in `RELEASE.md`.
- `README.md` no longer enumerates internal state files such as `restore-queue`, `restore-first`, or the `id-map` file path. It keeps only user-actionable data/state paths plus one internal-state caveat.
- The README `.zshrc` source-line example contains normal quote characters in the file bytes, not literal backslash characters.
- `RELEASE.md` no longer references stale `GHOSTTY_ZMX_TEST_GHOSTTY_CONFIG` wording or stale runtime-flag cleanup. Its smoke-test paragraph is compact and still preserves the important release-operator coverage categories.
- `docs/manual-e2e.md` removed the duplicated unmanaged-session steps from the pane-close scenario while retaining the dedicated unmanaged-session scenario.
- `docs/manual-e2e.md` condensed the automated close-confirmation override guidance while retaining the safety requirements that real config edits must be restored byte-for-byte and that `confirm-close-surface = false` must not be left in production config.
- Manual E2E instructions still preserve the important user-visible assertions from Phase 2: Cmd-Q layout shape, restored clients, markers in `zmx history`, reboot-scrollback banner/marker verification in zmx history, close-all behavior, and unmanaged-session preservation.

## Non-blocking observations

- `README.md` still mentions that restored panes attach "through a restore queue" in prose. This no longer exposes a file path or a stable user-operable artifact, so I do not consider it fix-now bloat.
- `RELEASE.md` intentionally remains process-oriented. That is appropriate for a release-facing document and is not duplicate public README content after `0ed05c4`.
