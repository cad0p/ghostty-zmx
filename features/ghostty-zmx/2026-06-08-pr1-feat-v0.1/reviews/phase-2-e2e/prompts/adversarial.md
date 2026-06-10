# Adversarial Lens — Phase 2 (E2E)

## Canonical spec
`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/design.md` — READ IT IN FULL FIRST. Pay attention to:
- "Manual E2E scenarios" section (8 scenarios)
- "Known limitations" section
- "Locked decisions before implementation" section

## PR / branch under review
Branch: `feat/v0.1` (draft PR #1)
Base: `main`
Expected commits: all implementation-phase commits through convergence

## Focus dimensions
- Probe for what breaks the running system during real Ghostty + zmx interaction:
  - Malformed input / edge cases in session naming, ID parsing, restore grouping
  - Race conditions in restore driver election, queue locking, reaper PID reuse
  - Partial failures: AppleScript timeouts, zmx daemon unavailability, kill -9 during restore
  - Hostile config: user-controlled XDG/TMP roots, symlinked install dirs, permission edge cases
  - State leakage between Ghostty processes: id-map corruption, queue cross-contamination
  - Reboot scrollback: missing session + missing snapshot, zmx run failure, zmx print failure
  - Unmanaged session protection: can reaper accidentally reap unmanaged sessions?
  - Close-all-windows vs Cmd-Q indistinguishability when Ghostty stays alive with windows=0
  - Debug log path disclosure / injection via crafted session names
- Verify all diagnostic message strings from the converged implementation are byte-identical to what the e2e-tester captured

## Deliverable
Write to: `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/r1-adversarial.md`

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
# Run from iTerm2/outside Ghostty
cd /Users/piercarlocadoppi/Documents/open-source/github/cad0p/ghostty-zmx

# Test with GHOSTTY_ZMX_DEBUG=1
GHOSTTY_ZMX_DEBUG=1 zsh -c 'source session-manager.zsh'

# Check for byte-identical diagnostic strings
grep -oP '(?<=debug_log ").*?(?=")' session-manager.zsh | sort -u
# Also check generated reaper template for diagnostic strings
```

## Exit criteria
- Adversarial probes documented with concrete reproduction steps or code citations
- No fix-now findings that block E2E convergence
- Diagnostic message strings verified byte-identical against e2e-tester capture