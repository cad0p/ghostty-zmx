# E2E Fixer Pass 2

## Context
A supervised E2E rerun exposed a real implementation defect: after the first startup shell releases `restore-${ghosttyPID}.lock`, later shells created by ordinary splits/tabs/windows in the same Ghostty process can re-elect themselves as restore drivers. They then restore the existing first managed session instead of generating a fresh per-surface session. Fix this implementation defect only.

## Tracker
`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md` — your scope is `E2E-IMPL-1` in the `Must fix before merge` table.

## Evidence
Read in full:
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-results.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-supervisor.zsh`

## Methodology
`/Users/piercarlocadoppi/Documents/personal/github/cad0p/Goldmine/open-source/github/pi-shipit/methodology.md` — follow fixer discipline. One cohesive fix commit. Tests green. Push the commit.

## Working directory + branch
`/Users/piercarlocadoppi/Documents/open-source/github/cad0p/ghostty-zmx`
`feat/v0.1` (draft PR #1, continue from `c11cb63`)

## Commit to land

### Commit: make restore election one-shot per Ghostty process
Finding IDs: E2E-IMPL-1
Approach:
- Preserve the stale-lock fix from `6ff0480`: the election lock must not permanently block future Ghostty restarts.
- Add a separate per-Ghostty-process sentinel such as `restore-attempted-${ghosttyPID}.done` or equivalent under the safe runtime dir.
- The first shell in a Ghostty process may attempt `_ghostty_zmx_restore`; it should mark the sentinel once restore has been attempted, regardless of whether a sessions file existed.
- Later ordinary shells in the same Ghostty process must not call `_ghostty_zmx_restore` just because the election lock was released. They should still be able to pop a restore queue if restore is active, or generate/log a fresh session for normal new surfaces.
- Ensure stale sentinel behavior does not break a new Ghostty process with a reused PID. Existing PID-reuse defense can be reused or extended; do not reintroduce persistent stale-lock behavior.
- Add/update shell coverage that fails on repeated restore-driver election in the same Ghostty PID and verifies a later shell generates/logs a fresh session rather than consuming `restore-first` from the existing sessions file.

Tests:
- `zsh -n session-manager.zsh install.sh uninstall.sh`
- `zsh tests/install-uninstall.zsh`
- `zsh tests/snapshot-scrollback.zsh`
- `zsh tests/restore-id-map.zsh`
- `zsh tests/release-control.zsh`

Commit subject: `fix: make restore election one-shot per Ghostty process`

## Exit criteria
- One fix commit pushed.
- Required tests pass.
- Report commit SHA, test results, and any remaining E2E concerns.

## Do NOT
- Do not run broad live Ghostty E2E; the orchestrator will rerun it.
- Do not modify the user's real `~/.zshrc` or Ghostty config.
- Do not address unrelated implementation-phase deferred rows.
