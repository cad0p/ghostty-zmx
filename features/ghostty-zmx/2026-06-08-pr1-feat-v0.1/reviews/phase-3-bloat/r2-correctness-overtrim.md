# Phase 3 bloat review r2: correctness / over-trim

Reviewer: Phase 3 correctness / over-trim, post-fixer
Scope read in full: `deferred.md`, prior r1 over-trim review, `README.md`, `RELEASE.md`, `docs/manual-e2e.md`, `uninstall.sh`, and `tests/install-uninstall.zsh`.

## Summary

I found no correctness regression or over-trim blocker from the bloat fixes.

The public docs still describe enough of the install, managed Ghostty config, usage model, state/data locations, close semantics, reboot-scrollback behavior, and uninstall safety model for v0.1 users. Release verification is current for the trimmed docs and still points maintainers at the relevant shell/static checks. The manual E2E checklist remains safe and actionable after prose trimming. The uninstaller now removes only the current per-user runtime directory after ownership/path/symlink checks and no longer performs stale flat runtime glob cleanup; the test suite explicitly preserves flat runtime decoys.

The only substantive correctness edge from r1 remains deferred: reboot scrollback can still continue to `zmx print` after `zmx run` failure. This was already tracked as `R1-OT-1` / `R2-E2E-ADV-1` and was not worsened by the bloat fixes.

## Checks run

```sh
zsh -n session-manager.zsh install.sh uninstall.sh tests/*.zsh
zsh tests/install-uninstall.zsh
```

Both passed with no output.

## Review notes

### Public README surface

- The README no longer documents the internal Ghostty config test override as a public knob.
- Runtime internals are appropriately collapsed: user-actionable data/state paths remain documented, while volatile runtime files are described as internal implementation state.
- Install/uninstall behavior remains sufficiently specified, including backups, conflict warnings, non-destructive `--yes`, explicit destructive flags, and unsafe deletion refusal.
- Close and reboot-scrollback semantics remain clear enough for users without exposing unnecessary implementation details.

No over-trim finding.

### Release docs

- `RELEASE.md` still lists the relevant syntax, installer/uninstaller, snapshot, restore/id-map, release-control, and `package.json` checks.
- It correctly says experimental setup cleanup is manual/out-of-band for v0.1.
- It avoids the stale public variable wording that prompted the bloat docs fix.

No release-doc correctness finding.

### Manual E2E checklist

- The checklist remains safe: it instructs running from outside managed Ghostty, requires production `confirm-close-surface = true` except for temporary automated-test overrides, and warns harnesses to restore the real Ghostty config byte-for-byte.
- The key v0.1 behavioral assertions remain present: Cmd-Q preserves sessions and restores layout, close paths reap only managed sessions, close-all-windows depends on Ghostty staying alive, unmanaged sessions are preserved, and reboot scrollback must be verified in `zmx history`, not merely outer Ghostty scrollback.
- The automated-test override section is generic and does not expose the internal env var name as public documentation.

No E2E over-trim finding.

### Uninstall runtime cleanup and unsafe decoys

`uninstall.sh` now calls `safe_remove_runtime_dir`, which targets only:

```text
${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ghostty-zmx-${UID}
```

It refuses symlinks, missing ownership, unsafe parents, unexpected basenames, `$HOME`, and `/`, then removes that validated directory. It no longer scans broad flat `ghostty-zmx-*` runtime globs.

`tests/install-uninstall.zsh` covers the intended post-fix behavior:

- current runtime directory `ghostty-zmx-${UID}` is removed;
- flat decoy `ghostty-zmx-reaper-decoy-$$` is preserved;
- symlinked runtime directory is refused and the target is preserved;
- `--yes` alone keeps install/data/state directories;
- explicit deletion flags remove install/data/state only through the same safe tree checks.

No uninstall safety regression found.

## Findings

None new.

## Deferred item still valid

`R1-OT-1` remains a real but already-deferred correctness edge: after `zmx run "$session" true` failure, reboot scrollback restore should eventually verify the target session exists before attempting/logging `zmx print`. This is unchanged by the bloat fixes and does not block the current trimmed-doc/runtime-cleanup changes.
