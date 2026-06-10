# Phase 3 bloat-docs review — r1

Scope reviewed in full:

- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/design.md`
- `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md`
- `README.md`
- `RELEASE.md`
- `docs/manual-e2e.md`
- `.github/workflows/release.yml`

I did not treat durable review/design artifacts under `features/...` as bloat merely for being verbose. Findings below focus on user-facing and release-facing docs.

## Findings

### BLOAT-DOCS-1 — README exposes internal runtime files as user-facing documentation

- **Severity:** medium
- **Where:** `README.md:88` through `README.md:121`
- **Issue:** The `State and data paths` section starts with useful supported environment knobs, then drifts into implementation internals: `restore-queue`, `restore-first`, `id-map`, private `_ghostty_zmx_*` helper behavior, and internal runtime-file lifecycle. This duplicates design-level details and makes non-API files look like stable user-operable state.
- **Recommendation:** Keep only supported knobs and user-actionable persistent paths, e.g. data dir, state dir, debug log, and history snapshot directory. Remove the `restore-queue`, `restore-first`, `id-map`, runtime-file lifecycle, and private-helper paragraphs from README or replace them with one sentence: “Other files under these directories are internal and may change.”
- **Risk / LOC saved estimate:** Low functional risk; medium documentation/API risk if users script against internal files. Saves roughly 10-16 README lines and reduces implied public surface.

### BLOAT-DOCS-2 — README documents an internal test harness variable

- **Severity:** medium
- **Where:** `README.md:101`
- **Issue:** `GHOSTTY_ZMX_INTERNAL_TEST_GHOSTTY_CONFIG` is explicitly described in the README. Even with the `INTERNAL_TEST` name, listing it in user docs turns it into a discoverable support surface. This also conflicts with the tracker rationale in `deferred.md:49`, which says the README no longer documents it as user-facing.
- **Recommendation:** Remove this line from README. Keep the variable only in tests or an internal contributor note if needed. If a real user override is desired later, expose a deliberately named install option rather than an internal environment variable.
- **Risk / LOC saved estimate:** Medium support/API risk; users can accidentally redirect production config edits. Saves 1-2 lines, but more importantly removes an accidental public API.

### BLOAT-DOCS-3 — README release-control section is unnecessary for users and duplicates RELEASE.md/design

- **Severity:** low
- **Where:** `README.md:173` through `README.md:175`
- **Issue:** The README explains the release-control implementation, `package.json` version-source rationale, npm non-publishing, and deferred package-version validation. This is maintainer/release process material, not user install/usage documentation, and it repeats `RELEASE.md` plus the design spec.
- **Recommendation:** Remove the `Release control` section from README, or replace it with a short badge/link only if users need release provenance. Keep release mechanics in `RELEASE.md`.
- **Risk / LOC saved estimate:** Low risk; saves 3 lines now and prevents stale release-process notes from lingering in public docs.

### BLOAT-DOCS-4 — RELEASE.md contains a stale and over-specific smoke-test paragraph

- **Severity:** medium
- **Where:** `RELEASE.md:20`
- **Issue:** The paragraph is a long checklist of implementation-test internals and includes stale naming: it says `GHOSTTY_ZMX_TEST_GHOSTTY_CONFIG`, while the actual scripts/tests use `GHOSTTY_ZMX_INTERNAL_TEST_GHOSTTY_CONFIG`. It also mentions “stale runtime flag cleanup,” which reads like historical migration/reviewer residue rather than a release operator action.
- **Recommendation:** Replace the paragraph with a compact, current instruction such as: “Installer/uninstaller tests run under temporary HOME with stubbed external commands and the internal test Ghostty config override; keep coverage for interactive, `--yes`, idempotency, conflict warnings, symlink refusal, runtime cleanup, and destructive deletion flags.” Avoid listing every assertion in prose; let the test names and test code carry that detail.
- **Risk / LOC saved estimate:** Medium process risk because a maintainer following the stale variable name will run the wrong verification path. Saves about 4-8 wrapped lines worth of prose and removes stale history wording.

### BLOAT-DOCS-5 — Manual E2E duplicates unmanaged-session coverage inside pane-close scenario

- **Severity:** low
- **Where:** `docs/manual-e2e.md:53` through `docs/manual-e2e.md:64`, duplicated by `docs/manual-e2e.md:114` through `docs/manual-e2e.md:128`
- **Issue:** The pane-close scenario embeds creation/verification/cleanup of an unmanaged zmx session, then the checklist repeats a standalone “Unmanaged sessions are not reaped” scenario later. This increases manual test length without adding distinct coverage.
- **Recommendation:** Keep unmanaged-session verification as its own scenario and remove steps 5-6 from pane-close cleanup, or replace them with “Unmanaged-session preservation is covered in the scenario below.”
- **Risk / LOC saved estimate:** Low risk; saves roughly 8-12 lines and reduces repeated manual setup/cleanup work.

### BLOAT-DOCS-6 — Automated-test config override section is too detailed for a manual E2E checklist

- **Severity:** low
- **Where:** `docs/manual-e2e.md:130` through `docs/manual-e2e.md:147`
- **Issue:** The final section is automation harness policy, not manual E2E. It repeats design-level guidance about temporarily disabling `confirm-close-surface` and contains a five-step backup/trap/diff procedure that belongs in an automated test harness or contributor testing doc.
- **Recommendation:** Condense to 2-3 lines: automated tests may temporarily set `confirm-close-surface = false` in a disposable/temporary Ghostty config and must restore the real config byte-for-byte. Move the detailed safe pattern into the harness implementation if needed.
- **Risk / LOC saved estimate:** Low risk; saves roughly 10-14 lines and keeps the manual checklist focused on human-run scenarios.

## Non-findings / notes

- `.github/workflows/release.yml` is already minimal; I found no documentation bloat there.
- `design.md` is intentionally comprehensive and suitable as a canonical implementation spec.
- `deferred.md` is a durable review/finding tracker. It contains history by design; I did not flag its verbosity as public documentation bloat.
