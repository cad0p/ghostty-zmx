# Phase 3 bloat-production review — r2 post-fixer

Reviewer: post-fixer Phase 3 bloat-production
Branch: `feat/v0.1`

## Scope read in full

- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-3-bloat/r1-bloat-production.md`
- `README.md`
- `RELEASE.md`
- `docs/manual-e2e.md`
- `uninstall.sh`
- `tests/install-uninstall.zsh`

Additional context inspected:

- `session-manager.zsh`
- `install.sh`
- post-fixer patches for `0ed05c4`, `2e2d80a`, `e480dc2`, and `e574e41`
- current references to internal test variables, restore internals, flat runtime names, and process-token/elapsed handling

## Checks run

```sh
git show --stat --oneline --decorate 0ed05c4 2e2d80a e480dc2 e574e41
git show --format=fuller --patch --find-renames 0ed05c4
git show --format=fuller --patch --find-renames 2e2d80a
git show --format=fuller --patch --find-renames e480dc2
git show --format=fuller --patch --find-renames e574e41
zsh -n session-manager.zsh install.sh uninstall.sh tests/*.zsh
zsh tests/install-uninstall.zsh
zsh tests/snapshot-scrollback.zsh
zsh tests/restore-id-map.zsh
zsh tests/release-control.zsh
```

All shell syntax/tests passed with no output.

## Verdict

No remaining `fix-now` production bloat found in the post-fixer diff, and no unsafe over-trim caused by the bloat fixes.

The fixes correctly resolved the r1 production bloat that was cheap and appropriate for v0.1:

- public README exposure of the internal Ghostty config test override was removed;
- public README listing of internal restore queue/map files and private helper surface was collapsed;
- release/manual E2E prose was trimmed without deleting required safety or verification content;
- stale flat `/tmp` runtime cleanup was removed from production uninstall;
- `deferred.md` was reconciled so the remaining open bloat items are tracked as v0.2/defer rather than hidden.

The two remaining r1 production-bloat concerns are still correctly deferred, not fix-now:

- `P3-BLOAT-1`: generated reaper mirrors manager helper logic, but the standalone reaper is part of the v0.1 lifecycle design and a safe dedup/template refactor requires broader E2E coverage.
- `P3-BLOAT-5`: elapsed/process-token fallback remains defensive and duplicated, but recent E2E regressions depended on elapsed parsing and PID-reuse guardrails, so trimming it now would risk reintroducing close/reaper failures.

## Commit review notes

### `0ed05c4` — README public-surface trim

This commit removed the public paragraph documenting `GHOSTTY_ZMX_INTERNAL_TEST_GHOSTTY_CONFIG`, removed private `_ghostty_zmx_*` helper wording, and replaced enumerated internal data files (`restore-queue`, `restore-first`, `id-map`) with a short user-actionable path list plus an explicit note that other files are internal.

No over-trim found. The README still documents install, managed Ghostty config, usage model, state/data overrides, support/debug paths, close semantics, reboot scrollback semantics, uninstall behavior, and limitations. It no longer turns implementation/test details into public API surface.

### `2e2d80a` — release/manual E2E prose trim

This commit replaced stale release-test wording with current concise guidance and collapsed duplicated manual E2E text.

No over-trim found. `RELEASE.md` still lists the pre-merge static/test commands and preserves the important boundaries: temp `HOME`, stubbed commands, internal temporary Ghostty config override, non-destructive uninstall defaults, explicit destructive flags, and manual/out-of-band experimental cleanup. `docs/manual-e2e.md` still covers Cmd-Q restore, working-directory observation, pane/window/close-all cleanup, Cmd-Q preservation, reboot scrollback simulation, unmanaged-session preservation, and automated-test config safety.

### `e480dc2` — stale flat runtime cleanup removal

This commit removed `safe_remove_runtime_globs` from `uninstall.sh` and updated `tests/install-uninstall.zsh` to assert the current per-user runtime directory is removed while flat decoys are preserved.

No remaining production bloat found. Current runtime files are created under `${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ghostty-zmx-${UID}` with names such as `reaper-${pid}.zsh`, `restore-${pid}.lock`, `restoring-${pid}.lock`, and `restore-attempted-${pid}.done`. The uninstaller now targets only that validated per-user runtime directory through `safe_remove_runtime_dir`, avoiding broad stale flat-name scanning.

No unsafe over-trim found. The test suite still covers current runtime removal and symlink refusal for the current runtime directory. Removing flat symlink skip assertions is appropriate because production no longer iterates flat globs.

### `e574e41` — tracker reconciliation

This commit moved the resolved fix-now bloat rows out of `deferred.md`'s must-fix table and added traceability entries for the three fixer commits.

No tracker bloat or unsafe reconciliation found. Existing deferred production-bloat items `P3-BLOAT-1` and `P3-BLOAT-5` remain present with rationale, and the must-fix table now accurately says none.

## Findings

None new.
