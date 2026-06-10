# Phase 3 bloat fixer pass 1

## Context
Phase 3 bloat review found several cheap/stale public-surface items that should be fixed before merge. Apply only the accepted fix-now rows in `deferred.md`; do not refactor core restore/reaper/test architecture.

## Tracker
`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md` — scope rows:

- P3-DOCS-1
- P3-DOCS-2
- P3-DOCS-3
- P3-DOCS-4
- P3-PROD-1

## Reviews
Read in full:

- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-3-bloat/r1-bloat-docs.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-3-bloat/r1-bloat-production.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-3-bloat/r1-correctness-overtrim.md`

## Working directory + branch
`/Users/piercarlocadoppi/Documents/open-source/github/cad0p/ghostty-zmx`
`feat/v0.1`

## Commits to land

### Commit 1: trim public README surface
Finding IDs: P3-DOCS-1, P3-DOCS-3
Approach:
- Remove `GHOSTTY_ZMX_INTERNAL_TEST_GHOSTTY_CONFIG` from public README.
- Collapse internal state-file details so README names only supported/actionable paths: data dir, state dir, debug log, history snapshots, and `sessions` if needed for support.
- Remove private helper-name discussion.
- Remove or reduce the README release-control section; keep release mechanics in `RELEASE.md`.
Tests: docs grep for stale/internal public references.
Commit subject: `docs: narrow public README surface`

### Commit 2: trim release and manual E2E docs
Finding IDs: P3-DOCS-2, P3-DOCS-4
Approach:
- Update `RELEASE.md` to use the current internal test config variable name only if needed, and make release verification concise/current.
- In `docs/manual-e2e.md`, remove duplicated unmanaged-session steps from pane close or replace with a cross-reference to the dedicated unmanaged scenario.
- Condense automated-test config override instructions while preserving the requirement that automated tests restore real config byte-for-byte.
Tests: docs grep for stale `GHOSTTY_ZMX_TEST_GHOSTTY_CONFIG`.
Commit subject: `docs: trim release and e2e checklist prose`

### Commit 3: remove stale flat runtime cleanup
Finding IDs: P3-PROD-1
Approach:
- Remove stale flat `/tmp` cleanup logic from `uninstall.sh` that scans for names current code no longer creates.
- Keep safe per-user runtime directory cleanup.
- Update tests/docs if they assert the old flat cleanup behavior.
Tests: full shell test suite.
Commit subject: `fix: remove stale runtime cleanup path`

## Required tests before done

```sh
zsh -n session-manager.zsh install.sh uninstall.sh features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-supervisor.zsh
zsh tests/install-uninstall.zsh
zsh tests/snapshot-scrollback.zsh
zsh tests/restore-id-map.zsh
zsh tests/release-control.zsh
```

## Exit criteria

- Scoped commits pushed.
- Required tests pass.
- Report commit SHAs, tests, deviations, and any concerns.

## Do NOT

- Do not refactor generated reaper duplication.
- Do not remove restore/id-map/restore-attempt logic.
- Do not weaken live E2E assertions.
- Do not modify the user's real `~/.zshrc` or Ghostty config.
