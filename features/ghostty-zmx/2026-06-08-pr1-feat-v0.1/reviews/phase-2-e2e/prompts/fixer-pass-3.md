# E2E Fixer Pass 3

## Context
A supervised E2E rerun after the restore-election fix passed Cmd-Q restore, working-directory inheritance, and Cmd-Q preservation, but pane/window/close-all cleanup failed. The raw logs show the generated reaper exits almost immediately with `reason=elapsed-check-failed` for young Ghostty processes. On macOS, `ps -o etime` can return `MM:SS`; the current elapsed parser requires `HH:MM:SS`.

## Tracker
`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md` — your scope is `E2E-IMPL-2` in the `Must fix before merge` table.

## Evidence
Read in full:
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-results.md`
- raw log path recorded there: `/var/folders/z6/fqkn3gjj1q704xr2s_xvgpq00000gn/T//ghostty-zmx-e2e-rerun-1781107406/e2e.log` if still present

Relevant code:
- `session-manager.zsh` main `_ghostty_zmx_ghostty_elapsed_seconds`
- generated reaper `elapsed_seconds` inside `_ghostty_zmx_start_reaper`

## Methodology
`/Users/piercarlocadoppi/Documents/personal/github/cad0p/Goldmine/open-source/github/pi-shipit/methodology.md` — follow fixer discipline. One cohesive fix commit. Tests green. Push the commit.

## Working directory + branch
`/Users/piercarlocadoppi/Documents/open-source/github/cad0p/ghostty-zmx`
`feat/v0.1`

## Commit to land

### Commit: accept short ps elapsed format in reaper
Finding IDs: E2E-IMPL-2
Approach:
- Fix elapsed parsing so both main code and generated reaper accept `MM:SS`, `HH:MM:SS`, and existing `D-HH:MM:SS` shapes.
- Avoid duplicating subtly different parsers if feasible; but generated reaper is standalone, so mirrored shell logic is acceptable.
- Ensure the generated reaper no longer treats young Ghostty processes as elapsed-check failures simply because `ps -o etime` is `01:27`.
- Add/update tests. Coverage should include at least `01:27` and `00:01:27` parsing, and ideally generated reaper syntax/logic if practical.
- Do not change close/Cmd-Q heuristics beyond fixing elapsed parsing.

Tests:
- `zsh -n session-manager.zsh install.sh uninstall.sh`
- `zsh tests/install-uninstall.zsh`
- `zsh tests/snapshot-scrollback.zsh`
- `zsh tests/restore-id-map.zsh`
- `zsh tests/release-control.zsh`

Commit subject: `fix: accept short elapsed times in reaper`

## Exit criteria
- One fix commit pushed.
- Required tests pass.
- Report commit SHA, test results, and remaining concerns.

## Do NOT
- Do not run broad live Ghostty E2E; the orchestrator will rerun it.
- Do not modify the user's real `~/.zshrc` or Ghostty config.
- Do not address unrelated rows.
