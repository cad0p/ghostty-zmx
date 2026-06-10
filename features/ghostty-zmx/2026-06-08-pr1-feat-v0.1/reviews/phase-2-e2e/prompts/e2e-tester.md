# E2E Tester Lens — Phase 2 (E2E)

## Canonical spec
`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/design.md` — READ IT IN FULL FIRST. Pay attention to:
- "Manual E2E scenarios" section (8 scenarios)
- "E2E automation configuration" section
- "Release readiness criteria" section

## PR / branch under review
Branch: `feat/v0.1` (draft PR #1)
Base: `main`
Expected commits: all implementation-phase commits through convergence

## Focus dimensions
- Execute all 8 manual E2E scenarios from `docs/manual-e2e.md` against the real implementation
- Verify automated test override: temporary `confirm-close-surface = false` in managed block, restore exact user config afterward
- Capture diagnostic message strings for byte-identical check
- Run from iTerm2 or terminal outside Ghostty and outside any managed zmx session
- Use disposable marker text for every scenario (e.g., `ghostty-zmx-e2e-$(date +%s)`)
- Verify reboot scrollback simulation: `zmx run "$session" true` + `zmx print` + banner + marker in `zmx history`

## Deliverable
Write to: `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/r1-e2e-tester.md`

Structured format:
```
## Findings
### ID (severity) — title
**Where:** file:line
**What:** description
**Recommendation:** concrete fix, "defer", or "decline"

## Well-maintained areas

## Summary
```

## Commands
```sh
# Run syntax checks
cd /Users/piercarlocadoppi/Documents/open-source/github/cad0p/ghostty-zmx
zsh -n session-manager.zsh install.sh uninstall.sh

# Run automated test suite
zsh tests/install-uninstall.zsh
zsh tests/snapshot-scrollback.zsh
zsh tests/restore-id-map.zsh
zsh tests/release-control.zsh
```

## Exit criteria
- All 8 manual E2E scenarios executed and documented PASS/FAIL
- Automated test with temporary `confirm-close-surface = false` runs and restores user config byte-for-byte
- Diagnostic message strings captured for byte-identical check
- No fix-now findings block E2E convergence