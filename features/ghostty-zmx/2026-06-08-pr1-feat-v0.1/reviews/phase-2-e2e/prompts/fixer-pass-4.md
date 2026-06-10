# E2E Fixer Pass 4

## Context
The cumulative adversarial pass caught a release-blocking E2E gap: the supervised E2E harness marked Cmd-Q restore PASS even though the raw log showed missing restored tabs/panes, sessions with `clients=0`, and AppleScript restore failures. Fix both the runtime restore path and the E2E assertion gap.

## Tracker
`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md` — your scope is `R3-E2E-ADV-1` and `R3-E2E-ADV-2` in the `Must fix before merge` table.

## Evidence
Read in full:
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/r3-cumulative-adversarial.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-supervisor.zsh`
- raw live log if still present: `/var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T//ghostty-zmx-e2e-rerun-1781109021/e2e.log`

Relevant symptoms from the raw log:
- `before_layout` had 2 windows, 3 tabs, 4 terminals.
- `after_layout` had only 2 windows, 2 tabs, 2 terminals.
- `zmx list managed` showed two restored sessions with `clients=0`.
- restore logged:
  - `restore failed step=split ... pane_index=2 direction=down`
  - `restore failed step=new-tab ... expected_window=...`
  - `restore failed step=new-window ...`

## Methodology
`/Users/piercarlocadoppi/Documents/personal/github/cad0p/Goldmine/open-source/github/pi-shipit/methodology.md` — follow fixer discipline. Use cohesive commits; tests green; push after commits.

## Working directory + branch
`/Users/piercarlocadoppi/Documents/open-source/github/cad0p/ghostty-zmx`
`feat/v0.1`

## Commits to land

### Commit 1: make restore surface creation robust
Finding IDs: R3-E2E-ADV-1, R3-E2E-ADV-2
Approach:
- Investigate and fix the AppleScript restore snippets in `session-manager.zsh` so creating restored splits/tabs/windows succeeds reliably on Ghostty 1.3.1.
- Avoid fragile focus/index/selected-tab operations where possible. Prefer returning explicit created object ids, then using explicit window/tab/terminal ids for subsequent operations.
- If an AppleScript step fails, do not silently let queued sessions attach into a reduced layout. At minimum, emit enough state for the E2E harness to fail. Prefer making the creation path reliable rather than adding broad fallback behavior.
- Keep serial restore; do not reintroduce fast/batch restore.

Required checks:
- `zsh -n session-manager.zsh install.sh uninstall.sh`
- Existing shell tests, plus add/update deterministic coverage if feasible for the restored-layout/harness logic.

Commit subject: `fix: restore Ghostty layout before reattaching sessions`

### Commit 2: assert restore layout and clients in E2E harness
Finding IDs: R3-E2E-ADV-1
Approach:
- Update `features/.../e2e-rerun-supervisor.zsh` so Cmd-Q restore PASS requires:
  - same logical layout shape after restore as before quit (window count, tab count, terminal count per logical group is enough; physical ids may differ),
  - every recorded managed session has `clients=1` after restore,
  - markers remain in `zmx history`.
- The harness should fail if debug logs contain `restore failed step=` during the scenario.
- Keep byte-for-byte config/install restoration behavior intact.

Required checks:
- Run the shell test suite.
- Do not run the full live E2E inside this fixer unless you can do it safely; the orchestrator will rerun the live E2E convergence gate.

Commit subject: `test: assert restored layout and clients in e2e`

## Exit criteria
- Scoped commits pushed.
- Required tests pass.
- Report commit SHAs, tests, and remaining concerns.

## Do NOT
- Do not mark PR ready.
- Do not modify the user's real `~/.zshrc` or Ghostty config.
- Do not address unrelated deferred rows.
