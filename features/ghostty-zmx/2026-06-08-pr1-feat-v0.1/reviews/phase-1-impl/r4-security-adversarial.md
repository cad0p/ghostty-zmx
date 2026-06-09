## Findings

### SA-1 (Medium) — Malformed managed Ghostty block can truncate user config
**Where:** `install.sh`:82-96, `install.sh`:119-129, `uninstall.sh`:140-147
**What:** Both installer and uninstaller use `awk` to skip everything from the first `# BEGIN ghostty-zmx` to the next `# END ghostty-zmx`. If a config contains an unmatched `BEGIN`, the script drops the remainder of the file while rewriting it. This can turn a malformed or partially edited Ghostty config into unintended data loss.
**Recommendation:** Add a preflight that detects unmatched `BEGIN`/`END` pairs and refuses to rewrite the file, or safely repairs only the managed block while preserving all non-managed content. Add malformed-config fixtures for install and uninstall.

### SA-2 (Medium) — Install directory symlink/race check is not atomic with install
**Where:** `install.sh`:60-65, `install.sh`:185-187
**What:** `refuse_symlinked_install_dir` checks `$HOME/.config/ghostty-zmx` before `mkdir -p`, then `install` writes into the same path afterward. A local attacker or racing process that can modify `$HOME/.config` could replace the directory with a symlink between the check and copy, causing installed files to land outside the intended directory.
**Recommendation:** Re-check `$install_dir` after `mkdir -p` and immediately before copying: refuse symlinks, require current-user ownership, and consider requiring safe mode/ownership on parent path. Keep the existing pre-existing symlink refusal, but close the TOCTOU window.

### SA-3 (Medium) — Destructive uninstall checks are separated from `rm -rf`
**Where:** `uninstall.sh`:49-69, `uninstall.sh`:73-94, `uninstall.sh`:175-188
**What:** `safe_remove_tree` and `safe_remove_runtime_dir` validate path shape, ownership, and symlink status, then call `rm -rf` on the resolved path. Between validation and removal, a local attacker with write access to the parent could swap the path, potentially causing deletion of an unintended user-owned directory.
**Recommendation:** Make removals non-racy where possible: revalidate immediately before removal, avoid `rm -rf` on validated variables that can be swapped, and consider using `find -P` with owner/base checks before unlinking individual children. Keep refusing symlinks and unsafe base names.

### SA-4 (Medium) — User-controlled XDG/TMP roots can redirect runtime, state, and map files
**Where:** `session-manager.zsh`:65-79, `session-manager.zsh`:122-136, `session-manager.zsh`:521-534, `session-manager.zsh`:571-572
**What:** Runtime, data, and state paths are derived from `XDG_RUNTIME_DIR`, `TMPDIR`, `XDG_DATA_HOME`, and `XDG_STATE_HOME`. The per-user runtime directory is chmod 700 after creation, but the root path and data/state roots are not fully validated for symlink ownership. State history, `sessions`, and `id-map` writes can follow symlinked roots and write outside the expected user-local locations.
**Recommendation:** Validate each configurable root and critical parent path before use: reject symlinked roots, require current-user ownership, and fail closed if ownership or permissions are unsafe. At minimum, reject symlinked `GHOSTTY_ZMX_DATA_HOME` and `GHOSTTY_ZMX_STATE_HOME`.

### SA-5 (Medium) — Reaper may miscount attached managed sessions and delay cleanup
**Where:** `session-manager.zsh`:418-424
**What:** The attached-session count is updated inside a pipeline `managed_sessions_from_log | while ...`. In zsh pipeline semantics, the counter update can occur in a subshell, leaving `attached` at zero even when managed sessions are attached. The reaper then treats the Ghostty process as all-detached, snapshots preserved sessions, and delays cleanup decisions instead of killing intentionally detached managed sessions promptly.
**Recommendation:** Avoid mutating shell state across a pipeline. Use a temp file, process substitution, or zsh-specific pipeline semantics to count attached sessions in the current shell. Add a regression test that proves the attached count is nonzero when a managed session reports `clients=1`.

### SA-6 (Low) — Release workflow grants `pull-requests: read`
**Where:** `.github/workflows/release.yml`:9-11
**What:** The release workflow grants `contents: write` and `pull-requests: read`. If the release action only needs to create/update GitHub releases, the extra `pull-requests: read` permission is broader than necessary.
**Recommendation:** Confirm whether `cad0p/semver-calver-release/release@v1` requires PR metadata. If not, remove `pull-requests: read` so the workflow token is limited to release contents writes.

### SA-7 (Low) — Debug log path metadata is user-controlled and state dir permissions are not hardened
**Where:** `session-manager.zsh`:106, `session-manager.zsh`:120
**What:** Debug logs include data/state paths supplied through environment variables. The code does not log terminal history content, but it can log paths that contain sensitive directory names if users set unusual XDG paths. `GHOSTTY_ZMX_STATE_HOME` is created with `mkdir -p` but not explicitly chmod 700 like the runtime directory.
**Recommendation:** Validate and chmod state/data directories on first use, and consider redacting or normalizing path metadata in debug logs.

## Well-maintained areas

- Managed session names are regex-validated before `zmx attach`, `zmx history`, `zmx kill`, `zmx print`, and logging decisions.
- The reaper only considers sessions present in ghostty-zmx's managed `sessions` file before killing or unlogging them.
- The generated reaper script is written with a quoted here-doc and receives environment-derived values as positional arguments, avoiding shell interpolation of untrusted values.
- AppleScript IDs are parsed through hex-suffix extraction before being used in generated AppleScript.
- Reboot scrollback restore follows the designed `zmx run "$session" true` then `zmx print` flow and does not log saved history contents.
- Uninstall refuses symlinked install/data/state/runtime targets and refuses unsafe deletion bases such as `/`, `$HOME`, and parent directories.
- The release workflow does not request broad secret permissions such as `id-token`; it is limited to contents write and, currently, pull-requests read.
- Syntax and included zsh tests passed locally.

## Summary

The diff has a strong adversarial baseline: session names are constrained, zmx commands are mostly quoted, reaper scope is limited to managed sessions, and scrollback restoration avoids logging history contents. The main security risks are filesystem path safety around user-controlled XDG/TMP roots, non-atomic install/delete operations, and a malformed Ghostty config edge case that can truncate user configuration. The release workflow is close to minimal but should remove `pull-requests: read` unless the release action proves it needs PR metadata.
