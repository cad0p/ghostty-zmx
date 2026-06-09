## Findings

### C-01 (medium) — private manager helpers remain in the sourced shell namespace
**Where:** `session-manager.zsh:859-860`
**What:** The sourced startup file calls `_ghostty_zmx_auto_attach`, then only unfunctions that one entry point. The many `_ghostty_zmx_*` helper functions remain callable in the user's shell after startup, even though the README describes them as private implementation details.
**Recommendation:** Wrap the one-shot startup path in a local function and unfunction/remove all `_ghostty_zmx_*` helpers after the call, or otherwise ensure the sourced file leaves no private helpers in the interactive shell namespace.

### C-02 (medium) — test-only Ghostty config override is part of the public script surface
**Where:** `install.sh:24`, `uninstall.sh:25`, `README.md:101`
**What:** `GHOSTTY_ZMX_TEST_GHOSTTY_CONFIG` is implemented directly in install/uninstall and documented in the README. This is useful for harnesses, but it reads like a user-facing configuration knob and expands the public environment surface for a v0.1 package.
**Recommendation:** Treat it as an internal test harness variable only, or rename it to an explicitly supported install-time override such as `GHOSTTY_ZMX_CONFIG_PATH`. If kept internal, remove the README exposure and keep it exercised only by tests.

### C-03 (medium) — installer performs experimental setup cleanup by default
**Where:** `install.sh:133-155`, `README.md:70-74`
**What:** The installer automatically removes or skips stale `/tmp/zmx-*` runtime flags and advertises that as part of the install plan. The design and README frame the earlier experimental setup as manual/out-of-band cleanup, so this adds an implicit migration side effect to the default installer.
**Recommendation:** Remove this cleanup from the default install path, or make it an explicit opt-in maintainer/user command. If kept, document the exact scope and rationale separately from the normal install flow.

### C-04 (low) — unused installer variable
**Where:** `install.sh:25`
**What:** `data_home` is assigned but not used by the installer. It looks like a public path override but does not affect behavior.
**Recommendation:** Remove the variable unless it is intentionally used for validation or future installer behavior.

### C-05 (low) — README lists too many runtime internals as user-facing paths
**Where:** `README.md:103-115`
**What:** The README says runtime files are not a public API, then lists lock/reaper files and describes their cleanup behavior. This duplicates implementation detail in the main user-facing documentation and can make the runtime layout feel more stable than intended.
**Recommendation:** Keep the README statement that runtime files are internal, but move the file list and cleanup details to a maintainer/test note or reduce it to a one-line implementation note.

### C-06 (low) — duplicated standalone helper logic in generated reaper script
**Where:** `session-manager.zsh:20-37`, `session-manager.zsh:250-259`
**What:** Session validation and hex/terminal hashing logic is duplicated between the sourced manager and the generated reaper script. The duplication is understandable because the reaper must run standalone, but it makes the API/implementation boundary less obvious.
**Recommendation:** Add a short comment near the generated script explaining that the standalone copy is intentional and should not be sourced, or generate it from a shared template if the duplication grows.

## Well-maintained areas

- Installed file layout matches the design: `~/.config/ghostty-zmx/session-manager.zsh` and `uninstall.sh`, with a single guarded `.zshrc` source line.
- Installer and uninstaller are idempotent and conservative: backups are made before edits, conflicts outside the managed Ghostty block are warned but preserved, and destructive data/state removal requires explicit flags.
- Public environment variables are mostly coherent and v0.1-shaped: data/state homes, reaper timing, restore delay, and scrollback limit are documented together with defaults.
- Runtime path handling is careful: the runtime directory is per-user, mode-checked, owner-checked, and symlink refusal is built into uninstall.
- Release documentation is clear that `package.json` is a SemVer source only and the v0.1 shell package is not npm-published.
- The README aligns with the design on Ghostty version, zsh-only scope, managed Ghostty block, working-directory inheritance knobs, close semantics, reboot scrollback limits, and known limitations.

## Summary

The diff is broadly clean for a zsh-only v0.1 surface: the install layout, guarded source line, managed Ghostty block, conservative uninstall flags, and release-control docs are coherent. The main cleanness/API-surface issues are that private startup helpers remain callable after sourcing, a test-only config override is exposed in runtime scripts and README, and the installer performs experimental cleanup by default despite the design saying experimental migration is manual.
