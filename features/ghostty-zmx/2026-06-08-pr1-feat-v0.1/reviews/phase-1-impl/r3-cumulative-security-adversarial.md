# Phase 1 implementation review: cumulative security/adversarial

## Findings

### SA-01 (Medium) — Installer removes non-managed `confirm-close-surface = false`
**Where:** `install.sh:106-117`
**What:** `strip_managed_block_and_experimental_env` deletes every exact `confirm-close-surface = false` line after removing the managed block, not only the documented experimental config entry. If a user intentionally has that setting elsewhere in Ghostty config, the installer silently changes it. This conflicts with the design invariant that conflicting settings outside the managed block should be left untouched and warned about.
**Recommendation:** Remove only the documented experimental env line and old experimental block. For any remaining `confirm-close-surface = false`, warn and leave it untouched. Add a regression test for a non-experimental false line outside the managed block.

### SA-02 (Medium) — Deletion helpers follow symlinks for install/data/state targets
**Where:** `uninstall.sh:49-66`, `uninstall.sh:131-144`
**What:** `safe_remove_tree` resolves the target with `:A` and then runs `rm -rf "$resolved"`. If an install/data/state target is a symlink to a `ghostty-zmx` directory outside the expected parent, uninstall deletes the symlink target, not the symlink. That could delete an unexpected user-owned directory if an attacker can arrange a symlink in one of those configured paths.
**Recommendation:** Refuse symlink targets (`[[ -L "$target" ]]`) or remove only the symlink after verifying the symlink path itself has the expected base and parent. Add symlink-target fixtures for install/data/state deletion.

### SA-03 (Medium) — External commands are resolved through mutable `PATH`
**Where:** `session-manager.zsh:47-48`, `session-manager.zsh:78`, `session-manager.zsh:122-124`, `session-manager.zsh:403`; `install.sh:42-47`, `install.sh:70-83`, `install.sh:204-211`; `uninstall.sh:32-37`, `uninstall.sh:97-110`, `uninstall.sh:127-144`
**What:** The sourced manager, installer, and uninstaller invoke many external commands through `PATH`: `stat`, `date`, `ps`, `awk`, `grep`, `tail`, `mv`, `rm`, `install`, `cp`, `chmod`, `mkdir`, `zmx`, `osascript`, and `nohup`. Because Ghostty environment/config can set `PATH` and the manager is sourced during shell startup, a hostile environment can redirect file edits, backups, runtime writes, and cleanup.
**Recommendation:** Use absolute paths or a sanitized lookup such as zsh `command -p` for file-editing and cleanup commands. At minimum, document that `PATH` and Ghostty environment are trusted, and validate critical command paths before editing user files.

### SA-04 (Medium) — Install writes through a symlinked install directory
**Where:** `install.sh:204-206`
**What:** `mkdir -p "$install_dir"` and `install` follow symlinks. If `~/.config/ghostty-zmx` is a symlink to another directory, the installer writes `session-manager.zsh` and `uninstall.sh` into the symlink target rather than the expected install directory.
**Recommendation:** Refuse a symlinked install directory, or replace it only after verifying the symlink path itself. Add a symlink fixture to install tests.

### SA-05 (Medium) — Broad `/tmp` cleanup patterns can delete unintended prefixed files
**Where:** `install.sh:172-174`; `uninstall.sh:127-129`
**What:** Migration and uninstall cleanup use broad `rm -rf /tmp/zmx-*` and `/tmp/ghostty-zmx-*` patterns. The prefixes are predictable and the scripts do not check ownership or file type before deletion. In `/tmp`, this can delete unexpected user/runtime files that happen to share those prefixes.
**Recommendation:** Scope migration cleanup to the expected UID-owned runtime directory or to exact legacy flag names, refuse symlinks, and test with decoy files that share the prefixes.

### SA-06 (Low) — Backup filenames can collide and overwrite prior backups
**Where:** `install.sh:35-47`; `uninstall.sh:30-37`
**What:** Backup filenames use second-resolution timestamps. Re-running install/uninstall twice in the same second against the same file can overwrite an earlier backup.
**Recommendation:** Include a process ID, random component, or higher-resolution timestamp, and avoid overwriting an existing backup path.

### SA-07 (Low) — Debug logging can expose user-controlled paths
**Where:** `session-manager.zsh:75-78`, `session-manager.zsh:125`, `session-manager.zsh:163`, `session-manager.zsh:165`; `README.md:144-149`
**What:** Debug logging is opt-in and does not log terminal history contents, but it records data/state home paths and history file paths. If users set those homes to sensitive path names, `debug.log` can leak path information.
**Recommendation:** Keep debug opt-in, but redact full path values or log only basenames/session metadata.

### SA-08 (Low) — Release workflow action is not pinned by SHA
**Where:** `.github/workflows/release.yml:9-24`
**What:** The release job grants `contents: write` to an unpinned third-party release action. If the action changes maliciously or is compromised, it can publish releases.
**Recommendation:** Pin the release action to a reviewed commit SHA and keep release permissions scoped to what the action requires.

### SA-09 (Low) — Atomic edit helpers do not check all command failures
**Where:** `install.sh:67-83`, `install.sh:106-117`; `uninstall.sh:94-110`
**What:** Several edits pipe `awk`/`grep` output to a temp file and then `mv` it into place. With `set -u` but not `set -e`, failures from `awk` or `grep` can still be followed by a move, potentially leaving empty or partially updated files.
**Recommendation:** Check command status before moving temp files into place, use `cmp -s` before replacement, and clean up temp files on failure.

## Well-maintained areas

- Managed session names are validated before logging, snapshotting, restore queue use, scrollback restore, and reaper kill decisions.
- The reaper kills only sessions listed in the managed `sessions` file and validates those names; unmanaged sessions are not targeted.
- Runtime directory creation checks for non-directory paths, sets `umask 077`, creates mode `0700`, and verifies ownership before use.
- Restore-driver election uses a `mkdir` lock, and restore queue pop uses a lock directory.
- Reaper startup snapshots existing managed sessions on Ghostty exit/PID-reuse checks, skips cleanup while restore files are active, and snapshots before cleanup decisions.
- Installer and uninstaller back up `.zshrc` and Ghostty config before edits.
- Installer filters invalid migrated session names and preserves an existing `ghostty-zmx/sessions` file.
- Uninstall preserves data/state/install directories by default and refuses unsafe deletion targets such as `/`, `$HOME`, parent directories, and paths not owned by the current user.
- Snapshot-scrollback tests verify truncation, failure preservation, banner injection, and that saved history content is not leaked to debug logs.

## Summary

The implementation has strong core adversarial controls around managed session-name validation, managed-session-only reaping, runtime-directory ownership checks, restore locking, backups, and non-destructive default uninstall behavior. I did not find a high-confidence critical/high issue showing arbitrary shell injection through session names or reaping of unmanaged zmx sessions.

The main release-blocking risks are medium-severity config/file-system boundary issues: non-managed Ghostty config mutation, symlink-following install/delete behavior, mutable-`PATH` command resolution, and broad `/tmp` cleanup patterns. Addressing those, plus the low-severity backup/logging/release-pinning nits, would make the v0.1 implementation materially safer.
