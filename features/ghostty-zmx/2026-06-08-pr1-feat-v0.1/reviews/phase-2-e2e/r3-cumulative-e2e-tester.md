## Findings

None.

## Well-maintained areas

- All eight design E2E scenarios have passing supervised evidence in `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/e2e-rerun-results.md:12` through `:19`:
  - `cmd-q-restore PASS`
  - `working-directory-inheritance PASS`
  - `pane-close-cleanup PASS`
  - `window-close-cleanup PASS`
  - `close-all-windows-cleanup PASS`
  - `cmd-q-does-not-clean PASS`
  - `reboot-scrollback-simulation PASS`
  - `unmanaged-not-reaped PASS`
- The real Ghostty config baseline hash captured before E2E is `d973fbe7bff3e640e7f6a582dabdfcfcd9ddf5f42b4707d83265a844781a9125` in `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/real-config-baseline/README.md`. The supervised rerun restored the config to the same hash and recorded `CONFIG_RESTORE_BYTE_FOR_BYTE=PASS` in `e2e-rerun-results.md:20` and `:23`.
- The supervised rerun also restored the installed manager and uninstaller byte-for-byte: `MANAGER_RESTORE_BYTE_FOR_BYTE=PASS` and `UNINSTALL_RESTORE_BYTE_FOR_BYTE=PASS` in `e2e-rerun-results.md:24` and `:25`. This is stronger than the minimum fixture-shape requirement for config restoration.
- The automated E2E override is appropriately temporary: `e2e-rerun-supervisor.zsh` replaces only the managed `# BEGIN ghostty-zmx` block with `confirm-close-surface = false`, sets disposable data/state homes and short `ZMX_DIR=/tmp/gzmx-$$`, and restores the user's real files through an exit trap before final hash checks.
- The reboot scrollback scenario covers the design-critical success path: it verifies the snapshot exists, kills the zmx session, reopens Ghostty, checks the exact restore banner and marker inside `zmx history`, and checks debug evidence for `fresh-session detection ... exists=0` and `zmx print restored scrollback ...`.
- Diagnostic strings used by E2E are stable in the cumulative state. Current `session-manager.zsh` still contains the E2E-observed debug strings for restore-driver election/release, current position, generated session logging, fresh-session detection, zmx print restore, restore-active skip, detach cleanup, and zero-window cleanup. `deferred.md` records no diagnostic-message deviations under `Diagnostic-message deviations — deviate-with-rationale entries`.
- All Phase 2 adversarial findings are properly tracked as deferred hardening items in `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md:35` through `:38`: `R2-E2E-ADV-1` through `R2-E2E-ADV-4`. The `fix-now` section remains `None` in `deferred.md:3` through `:5`.
- Static shell checks were rerun in this cumulative pass, without broad live Ghostty E2E:

  ```sh
  zsh -n session-manager.zsh install.sh uninstall.sh
  zsh tests/install-uninstall.zsh
  zsh tests/snapshot-scrollback.zsh
  zsh tests/restore-id-map.zsh
  zsh tests/release-control.zsh
  ```

  All completed successfully.

## Summary

Cumulative Phase 2 E2E status is release-ready from the E2E lens. The branch has supervised evidence that all eight required E2E fixtures pass, the user's real Ghostty config was restored byte-for-byte after the temporary `confirm-close-surface = false` test override, installed files were also restored byte-for-byte, diagnostic strings used by E2E have no recorded deviations, and all E2E fix-now findings are resolved. Remaining E2E/adversarial concerns are explicitly deferred and tracked for v0.2; no new fix-now findings were found in this cumulative review.
