# Cumulative E2E Lens — Phase 2 (E2E)

## Canonical spec
`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/design.md` — READ IT IN FULL FIRST.

## PR / branch under review
Branch: `feat/v0.1` (draft PR #1)
Base: `main`

## Focus dimensions
Review the cumulative state of the diff against the base branch for:
- All 8 manual E2E scenarios PASS (e2e-tester findings)
- No adversarial probes found real breakage (adversarial findings)
- Diagnostic message strings byte-identical across the converged implementation
- No regression in the user's actual Ghostty config (captured at step-1 prep)
- Fixture-shape: automated test with temporary `confirm-close-surface = false` restores exact user config byte-for-byte

## Deliverable
Write to: `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/rN-cumulative-e2e-tester.md` (or rN-cumulative-adversarial.md)

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

## Exit criteria
- Cumulative round uses full E2E lens set (e2e-tester + adversarial)
- No fix-now findings from cumulative review
- Empirical evidence of substantive review (multi-lens exercised)