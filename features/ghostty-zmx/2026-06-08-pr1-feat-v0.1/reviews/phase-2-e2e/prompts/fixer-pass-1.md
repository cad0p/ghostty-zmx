# E2E Fixer Pass 1

## Context
Phase 2 E2E found runtime blockers before the full E2E set could converge. Fix only the accepted E2E findings listed here, then push the branch. Do not run new E2E review rounds yourself; the orchestrator will re-run E2E after your commits.

## Tracker
`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md` — E2E fix-now rows are E2E-1, E2E-2, E2E-3, and E2E-4. The implementation-phase deferred rows are not your scope.

## Reviews
Read `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/r1-e2e-tester.md` in full for reproductions and citations.

## Methodology
`/Users/piercarlocadoppi/Documents/personal/github/cad0p/Goldmine/open-source/github/pi-shipit/methodology.md` — follow fixer discipline. One cohesive fix commit per finding or tightly coupled finding pair; tests green between commits; push after each commit.

## Working directory + branch
`/Users/piercarlocadoppi/Documents/open-source/github/cad0p/ghostty-zmx`
`feat/v0.1` (draft PR #1, continue from `adffd5f`)

## Commits to land

### Commit 1: fix generated reaper shell syntax
Finding IDs: E2E-1
Approach: The generated reaper heredoc in `session-manager.zsh` must contain valid zsh only. Remove the embedded AppleScript `on hex_suffix` / `on terminal_hash` handlers from the reaper script. Add or update a shell test that catches generated-reaper syntax errors, preferably by generating the script and running `zsh -n` on it or by extracting a stable generation seam.
Tests: `zsh -n session-manager.zsh install.sh uninstall.sh`; relevant shell tests.
Commit subject: `fix: generate valid reaper shell script`

### Commit 2: clean restore-driver election lock
Finding IDs: E2E-2
Approach: Ensure `restore-${ghosttyPID}.lock` is removed after the restore driver completes its one-time work and after the first shell consumes `restore-first`, while preserving lock behavior during restore. Cleanup should also occur on early/no-session paths where appropriate and should not race child shells that still rely on `restoring-${ghosttyPID}.lock` for restore-active detection.
Tests: syntax + relevant restore/id-map or new shell coverage.
Commit subject: `fix: release restore driver lock after startup`

### Commit 3: trace and repair first-launch auto-attach session logging
Finding IDs: E2E-3, E2E-4
Approach: Investigate why first Ghostty launch may log only `shell init` and fail to create `~/.local/share/ghostty-zmx/sessions`. Add granular debug logs at auto-attach guard exits and around current-position/session generation/logging so runtime failures are diagnosable. Fix the underlying cause if found. Be careful: sourcing from non-interactive shells outside Ghostty is expected to stop early and should not create sessions.
Tests: syntax + automated tests; add targeted shell coverage for guard/debug behavior if feasible without live Ghostty.
Commit subject: `fix: trace first-launch session logging`

## Exit criteria
- All scoped fixes committed and pushed.
- `zsh -n session-manager.zsh install.sh uninstall.sh` passes.
- `zsh tests/install-uninstall.zsh`, `zsh tests/snapshot-scrollback.zsh`, `zsh tests/restore-id-map.zsh`, and `zsh tests/release-control.zsh` pass, unless you report a clear environment-only blocker.
- Report commit SHAs, test results, deviations, and any remaining E2E concerns.

## Do NOT
- Do not address implementation-phase deferred rows outside this E2E fixer scope.
- Do not edit PR state or mark the PR ready.
- Do not modify the user's real `~/.zshrc` or Ghostty config.
- Do not use orchestration-internal vocabulary in source comments, README, tests, or commit messages beyond finding-ID footers if needed.
