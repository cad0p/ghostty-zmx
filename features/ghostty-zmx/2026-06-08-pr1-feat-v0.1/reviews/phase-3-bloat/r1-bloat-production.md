# Phase 3 bloat-production review — r1

Scope: cumulative diff against `main`, with production bloat lens only. Required release-grade artifacts under `features/.../reviews` were treated as in-scope for review context but not flagged for removal merely because they are review artifacts.

## Findings

### P3-BLOAT-1 — Medium — generated reaper mirrors too much manager logic

- Location: `session-manager.zsh:296`
- Evidence: the generated `nohup` reaper heredoc redefines helper logic already present in the sourced manager: session-name validation, history-file derivation, debug logging, elapsed parsing, snapshotting, and zmx session enumeration (`session-manager.zsh:298`, `session-manager.zsh:303`, `session-manager.zsh:309`, `session-manager.zsh:315`, `session-manager.zsh:360`, `session-manager.zsh:396`).
- Why this is bloat: v0.1 needs a standalone background process, but the current implementation keeps two copies of policy-heavy logic in one production file. The duplication has already required bug-fix attention and makes future fixes easy to apply to one copy only.
- Recommendation: either install/generate a minimal private reaper script from a single maintained template, or reduce the generated reaper to the smallest independent loop and keep shared policies out of the heredoc. At minimum, centralize the duplicated validation/history/snapshot/elapsed code before adding more reaper behavior.
- Risk / LOC estimate: medium maintenance risk; likely saves or de-duplicates ~80-140 lines of shell logic in `session-manager.zsh` depending on extraction shape.

### P3-BLOAT-2 — Medium — README exposes internal/test-only configuration as user-facing surface

- Location: `README.md:101`
- Evidence: the public README documents `GHOSTTY_ZMX_INTERNAL_TEST_GHOSTTY_CONFIG` for “Advanced installer/uninstaller test harnesses”.
- Why this is bloat: the variable is explicitly internal/test-only, but documenting it in the main README turns it into a production-facing knob users may rely on. That expands support/API surface without improving normal v0.1 usage.
- Recommendation: remove this line from the public README. Keep the variable discoverable only in tests or maintainer-facing E2E docs if needed.
- Risk / LOC estimate: low-to-medium API-surface risk; saves 1 README paragraph and prevents accidental dependency on an internal override.

### P3-BLOAT-3 — Low — README lists internal queue/map files as if they are stable user data

- Location: `README.md:107`
- Evidence: the README enumerates `restore-queue`, `restore-first`, and `id-map` (`README.md:111`-`README.md:113`) immediately after saying runtime files are internal (`README.md:103`). It also describes private helper names at `README.md:105`.
- Why this is bloat: `sessions`, history snapshots, and debug logs are useful support paths; restore queues, first-session markers, id maps, and helper names are implementation details. Publishing exact filenames encourages users/scripts to inspect or mutate them and constrains v0.2 refactors.
- Recommendation: collapse this section to “data lives under `~/.local/share/ghostty-zmx/`; state/log/history lives under `~/.local/state/ghostty-zmx/`”, optionally naming only `sessions`, `debug.log`, and `history/<session>.txt` as support/debug artifacts. Remove the private helper-name paragraph.
- Risk / LOC estimate: low public-contract risk; saves ~8-12 README lines and narrows the supported surface.

### P3-BLOAT-4 — Low — uninstall contains stale flat-runtime cleanup paths no current code creates

- Location: `uninstall.sh:98`
- Evidence: `safe_remove_runtime_globs` scans `${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}` for flat names like `ghostty-zmx-restore-*`, `ghostty-zmx-restoring-*`, and `ghostty-zmx-reaper-*` (`uninstall.sh:101`). Current runtime files are instead created inside the per-user directory returned by `_ghostty_zmx_runtime_dir` (`session-manager.zsh:72`) with names like `restore-${ghosttyPID}.lock`, `restoring-${ghosttyPID}.lock`, and `reaper-${ghosttyPID}.zsh`.
- Why this is bloat: this looks like leftover cleanup for an older naming scheme. It adds root-level scanning, extra safety branches, and a user-facing message about `/tmp` even though the current design only requires deleting the expected per-user runtime directory.
- Recommendation: remove `safe_remove_runtime_globs` and rely on `safe_remove_runtime_dir` for current generated runtime cleanup. If legacy cleanup is intentionally needed, move it to maintainer-only manual cleanup docs rather than production uninstall.
- Risk / LOC estimate: low operational risk; saves ~20-25 lines and removes a speculative cleanup path.

### P3-BLOAT-5 — Low — process-token fallback is more cross-platform/defensive than v0.1 needs

- Location: `session-manager.zsh:128`
- Evidence: `_ghostty_zmx_ghostty_process_token` prefers `ps -o lstart` but falls back to elapsed-time parsing (`session-manager.zsh:128`-`session-manager.zsh:136`), while the generated reaper duplicates a full elapsed parser and PID-reuse check (`session-manager.zsh:315`-`session-manager.zsh:345`, `session-manager.zsh:448`-`session-manager.zsh:456`).
- Why this is bloat: v0.1 is macOS-only, and macOS `ps` supports `lstart`. Carrying a fallback elapsed parser in both the manager and reaper broadens complexity for an unsupported environment and duplicates parsing logic.
- Recommendation: for v0.1, use one macOS process-start identity path consistently, preferably `lstart`, and drop the elapsed fallback/parser unless a tested macOS failure requires it. If elapsed parsing is retained, keep a single implementation rather than duplicating it in the reaper heredoc.
- Risk / LOC estimate: low-to-medium maintenance risk; potential savings ~25-50 lines and one class of parser edge cases.

## Non-findings / intentionally not flagged

- Release workflow, package metadata, design/review files, and E2E evidence under `features/.../reviews` are release-grade artifacts requested by the methodology and were not treated as removable production bloat.
- Serial AppleScript restore and close/reaper behavior are larger than ideal, but they are directly tied to locked v0.1 behavior and passing live E2E; I only flagged duplicated/speculative portions, not the core feature path.
