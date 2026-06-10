# Real config baseline for E2E regression gate

Captured: 2026-06-10T15:22:02Z

## Files

d973fbe7bff3e640e7f6a582dabdfcfcd9ddf5f42b4707d83265a844781a9125  features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/real-config-baseline/config.ghostty.snapshot
ead161c8cb4fbc34c785e4751a2bfcd1c95a1d2b708da228a56e8b84905fa634  features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/reviews/phase-2-e2e/real-config-baseline/zshrc.snapshot

## Notes

- Snapshot is for byte-for-byte restore/regression checks during E2E.
- The real config currently includes historical experimental zmx integration and the packaged ghostty-zmx source line; tests must not leave unplanned changes.
