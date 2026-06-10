# Phase 3 bloat review r2: post-fixer tests

Scope read in full:

- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-3-bloat/r1-bloat-tests.md`
- `tests/install-uninstall.zsh`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-supervisor.zsh`

Additional files inspected for context:

- `uninstall.sh`
- `tests/snapshot-scrollback.zsh`
- `tests/restore-id-map.zsh`
- `tests/release-control.zsh`
- `e480dc2` patch
- `e574e41` tracker reconciliation patch

Validation run:

```text
for t in tests/*.zsh; do echo "== $t =="; zsh "$t"; done
```

Result: all shell tests passed.

## Verdict

No remaining `fix-now` test bloat found, and no unsafe loss of test coverage from the post-fixer changes reviewed.

The r1 test-bloat findings that remain in the suite are appropriately tracked as v0.2/defer refactors in `deferred.md`: installer fixture duplication, repeated symlink/refusal fixture shape, reaper syntax/elapsed checks living in the scrollback fixture, repeated `osascript` stubs, mixed restore/startup fixture responsibilities, and verbose/fixed-wait E2E harness behavior. They are maintenance/readability issues, not merge blockers.

## Post-fixer review of `e480dc2`

`e480dc2` removed stale flat runtime cleanup from `uninstall.sh` and changed `tests/install-uninstall.zsh` accordingly.

The test change is coverage-preserving for the intended new behavior:

- It still verifies that the current per-user runtime directory, `ghostty-zmx-${UID}`, is removed by uninstall.
- It now verifies that an unrelated flat decoy matching the old broad namespace shape, `ghostty-zmx-reaper-decoy-*`, is preserved.
- It still separately verifies that a symlinked current per-user runtime directory is refused and that its target survives.

The removed assertions covered behavior that no longer exists by design: skipping old flat runtime symlinks and printing `Skipped generated runtime symlink`. Keeping those assertions after deleting the flat cleanup path would have forced stale production behavior back into the implementation. Their removal is therefore safe and desirable, not an unsafe coverage loss.

One minor nuance: the old test also created a flat symlink decoy, while the new test creates only a flat directory decoy. That is acceptable because the new production code no longer iterates flat runtime globs at all; the meaningful safety boundary is the named current runtime directory, and that symlink refusal remains covered immediately below.

## Remaining bloat status

No new r2 findings.

Carry forward the existing deferred r1 test-bloat items without escalating them:

- `P3-BT-1` duplicate installer conflict fixtures.
- `P3-BT-2` repeated unsafe deletion/symlink refusal fixture shape.
- `P3-BT-3` reaper syntax/elapsed coverage colocated with snapshot-scrollback tests.
- `P3-BT-4` repeated `osascript` stubs in restore/id-map coverage.
- `P3-BT-5` mixed restore/id-map and auto-attach startup responsibilities.
- `P3-BT-6` fixed sleeps in the live E2E harness.
- `P3-BT-7` unconditional successful-state dumps in the live E2E harness.

These are still valid cleanup candidates for v0.2, but fixing them before v0.1 would be refactor churn with little risk reduction.
