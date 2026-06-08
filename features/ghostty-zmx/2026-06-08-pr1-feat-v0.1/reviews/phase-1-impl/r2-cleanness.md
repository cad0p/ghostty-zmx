## Findings

### CLEAN-R2-1 (high) — Installed `.zshrc` source line contains literal escaped quotes
**Where:** `install.sh`:27, `README.md`:37
**What:** The installer and README use `[[ -r \"$HOME/.config/ghostty-zmx/session-manager.zsh\" ]] && source \"$HOME/.config/ghostty-zmx/session-manager.zsh\"`. In an actual `.zshrc`, those backslashes are literal shell syntax, not Markdown escaping, so the test/source operands include quote characters in the path. This makes the main public installation API look correct in docs while installing a line that will not source the manager normally.
**Recommendation:** Change the installed and documented line to the normal zsh form: `[[ -r "$HOME/.config/ghostty-zmx/session-manager.zsh" ]] && source "$HOME/.config/ghostty-zmx/session-manager.zsh"`. Keep installer, uninstaller, README, and tests using the same unescaped source-line constant.

### CLEAN-R2-2 (medium) — Runtime file layout is implicit and uninstaller targets stale paths
**Where:** `session-manager.zsh`:30, `session-manager.zsh`:129, `session-manager.zsh`:704, `uninstall.sh`:102
**What:** Runtime artifacts now live under a per-user runtime directory such as `${TMPDIR:-/tmp}/ghostty-zmx-$UID/reaper-${pid}.zsh` and `restore-${pid}.lock`, while the uninstaller removes only top-level `/tmp/ghostty-zmx-restore-*`, `/tmp/ghostty-zmx-restoring-*`, and `/tmp/ghostty-zmx-reaper-*` patterns. README also documents data/state paths but not the generated runtime directory. The per-user directory is a cleaner/security-improving shape, but the public file layout and cleanup story no longer line up.
**Recommendation:** Either document the per-user runtime directory as internal implementation state and teach `uninstall.sh` to safely remove `${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/ghostty-zmx-$UID` artifacts, or align runtime names with the documented/design top-level `/tmp/ghostty-zmx-*` shape. Prefer one canonical runtime layout before v0.1.

### CLEAN-R2-3 (medium) — Installer deletes an unmanaged Ghostty setting despite promising to leave conflicts alone
**Where:** `install.sh`:106, `install.sh`:112, `install.sh`:113, `README.md`:56
**What:** `strip_managed_block_and_experimental_env` removes every exact `confirm-close-surface = false` line outside the managed block. The README/API promise says conflicting `env`, `window-save-state`, or `confirm-close-surface` settings outside the managed section are left untouched and only warned about. This broad removal makes installer ownership of Ghostty config larger and less predictable than documented.
**Recommendation:** Keep automatic edits confined to the managed block. For legacy migration, either warn and ask for explicit confirmation before removing the old `confirm-close-surface = false`, or only treat it as experimental when accompanied by the known legacy `env = ZMX_AUTO_ATTACH=1` migration context and disclose that in the printed plan.

### CLEAN-R2-4 (low) — Conflict warning treats all `env =` lines as ghostty-zmx conflicts
**Where:** `install.sh`:122, `install.sh`:128, `README.md`:56
**What:** Ghostty can have unrelated `env = ...` lines. Warning on any `env` key outside the managed section makes the installer feel noisier and more intrusive than necessary, and it blurs which public configuration keys ghostty-zmx actually cares about.
**Recommendation:** Warn only for `env` entries that affect ghostty-zmx or its legacy migration path, such as `GHOSTTY_ZMX_AUTO_ATTACH` and `ZMX_AUTO_ATTACH`, or reword the warning to say unrelated env lines are expected and left alone.

### CLEAN-R2-5 (low) — `--yes` uninstaller behavior is not explicit about Ghostty config removal
**Where:** `uninstall.sh`:95, `README.md`:168
**What:** The README says uninstall “optionally removes the managed Ghostty block,” but `--yes` answers yes to that prompt and removes it automatically. That is a reasonable non-interactive behavior, but it is part of the public CLI contract and should be spelled out.
**Recommendation:** Document that `--yes` removes the managed Ghostty block while preserving install/data/state directories unless destructive flags are passed, or add a `--keep-ghostty-config`/`--remove-ghostty-config` flag pair for a clearer non-interactive API.

### CLEAN-R2-6 (low) — Internal helper functions remain in the interactive shell namespace
**Where:** `session-manager.zsh`:19, `session-manager.zsh`:80, `session-manager.zsh`:121, `session-manager.zsh`:750
**What:** Only `_ghostty_zmx_auto_attach` is removed after sourcing; the rest of the `_ghostty_zmx_*` helpers remain defined in the user’s interactive zsh after the manager runs. The underscore prefix is good, but for a sourced shell package this still expands the visible API surface and exposes internals that are not documented as stable.
**Recommendation:** If the helpers are not needed after startup, unset them after auto-attach completes. If retaining them is useful for diagnostics/tests, explicitly treat them as private implementation details and consider a single cleanup/debug entrypoint rather than leaving many helpers in the shell.

## Well-maintained areas

- Public package naming is now consistently `ghostty-zmx`, with XDG data/state defaults using `ghostty-zmx` rather than the old experimental `zmx` paths.
- The README’s main user-facing sections are concise and align with the design’s zsh/macOS/Ghostty 1.3.1 scope, known limitations, release-control expectations, and no-npm-publishing constraint.
- Installer and uninstaller flags are intentionally small: `--yes` for automation and explicit destructive removal flags for install/data/state cleanup.
- The managed Ghostty config block is clearly delimited and uses the locked production settings: `GHOSTTY_ZMX_AUTO_ATTACH=1`, `window-save-state = never`, and `confirm-close-surface = true`.
- Runtime constants for timing and scrollback limits are named near the top of `session-manager.zsh`, making the important magic numbers easier to audit.
- Release docs avoid overpromising npm publishing and correctly note that package-version validation is deferred until `package.json` exists on `main`.

## Summary

The implementation is largely clean for a shell-only v0.1 surface, but a few pre-v1 API hygiene issues should be tightened: fix the literal-escaped installed source line, choose/document one runtime artifact layout and make uninstall clean it, and keep installer ownership of Ghostty config strictly aligned with the “managed block only” promise. The remaining items are low-severity CLI/documentation polish around warning specificity, `--yes` behavior, and private helper namespace cleanup.
