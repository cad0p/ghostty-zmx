## Findings

### S1 (high) — Predictable `/tmp` reaper script path can be symlink-clobbered
**Where:** `session-manager.zsh`:84-89, `session-manager.zsh`:207-208
**What:** `_ghostty_zmx_start_reaper` atomically creates a directory flag with `mkdir`, but then writes executable code to a separate predictable path, `/tmp/ghostty-zmx-reaper-${ghosttyPID}.zsh`, using `cat > "$script"`. A local adversary can predict or race Ghostty PIDs and pre-create that script path as a symlink to any file writable by the user (for example shell startup files or Ghostty config). When a managed Ghostty shell starts, the redirect follows the symlink and overwrites the target with the generated reaper script; `chmod +x` and the `nohup` invocation then operate on that path. The log redirect to `/tmp/ghostty-zmx-reaper-${ghosttyPID}.log` has the same predictable-path issue for clobbering writable files.
**Recommendation:** Do not write scripts/logs directly to predictable `/tmp` filenames. Create a private runtime directory with `mktemp -d` or `mkdir` using a sufficiently random suffix, set restrictive permissions, and place the script/log inside it. Alternatively avoid the on-disk script entirely by invoking `/bin/zsh -c` with a static installed helper. If `/tmp` files remain, open them with no-follow/exclusive semantics and verify ownership/type before writing.

### S2 (medium) — Persisted session names are not validated before path construction and destructive zmx operations
**Where:** `session-manager.zsh`:50-52, `session-manager.zsh`:63-74, `session-manager.zsh`:123-135, `session-manager.zsh`:335-349, `install.sh`:145-155
**What:** Session names are treated as trusted once read from `sessions` or migrated from the old experimental state. They are used directly as path components for scrollback snapshots (`history/${session}.txt`) and for deletion (`rm -f "$stateHome/history/${session}.txt"`), and they drive `zmx kill`, `zmx attach`, `zmx run`, and `zmx print`. Quoting prevents shell metacharacter injection, but malformed names containing `/`, `..`, whitespace, tabs, or unexpected delimiters can still cause path traversal outside the intended `history/` directory and can make the reaper act on arbitrary `zmx-*` sessions listed in the managed file. Migration copies the old sessions file without filtering, so malformed experimental state is enough to enter this trust boundary.
**Recommendation:** Validate every session name at read/migration boundaries and before filesystem or `zmx` operations. Accept only the canonical shape, e.g. `zmx-<window-hex>-<tab-hex>-<terminal-hex8>` with a conservative character class and no slashes/control characters; skip and log invalid lines. Build snapshot paths only after validation, and consider writing sanitized snapshot filenames or mapping session names to encoded filenames.

### S3 (medium) — `--yes` uninstall can recursively delete arbitrary env-selected directories
**Where:** `uninstall.sh`:20-21, `uninstall.sh`:86-95
**What:** `GHOSTTY_ZMX_DATA_HOME` and `GHOSTTY_ZMX_STATE_HOME` are honored by uninstall and later removed with `rm -rf` after confirmation. In `--yes` mode, those confirmations are automatically accepted, so a mistyped or hostile environment such as `GHOSTTY_ZMX_DATA_HOME=$HOME` or `GHOSTTY_ZMX_STATE_HOME=/tmp` can delete broad user-controlled trees. The script also does not canonicalize, check ownership, or enforce that the deletion targets end in the expected `ghostty-zmx` component.
**Recommendation:** Before any recursive deletion, resolve the path and require it to be non-empty, owned by the current user, not `$HOME`, not `/`, not a parent directory, and either the default XDG ghostty-zmx directory or a path containing a marker file created by ghostty-zmx. In `--yes` mode, still refuse unsafe targets rather than treating environment-selected paths as confirmed.

### S4 (medium) — Restore-driver election uses non-atomic predictable `/tmp` flag
**Where:** `session-manager.zsh`:492-498
**What:** Restore election checks `[[ ! -f "$restoreFlag" ]]` and then `touch`es `/tmp/ghostty-zmx-restore-${ghosttyPID}`. This is a time-of-check/time-of-use race between concurrently starting Ghostty shells, so more than one shell can elect itself restore driver and concurrently rewrite restore state. A pre-existing file or symlink at the predictable path can also suppress restore for that Ghostty PID. This is mostly integrity/availability rather than code execution, but it is in a critical path that rewrites queues and creates/kills terminal surfaces.
**Recommendation:** Use an atomic lock directory (`mkdir`) or `noclobber` file creation for restore election, verify ownership/type, and clean up via the elected driver. Prefer placing the flag in the same private runtime directory approach recommended for the reaper rather than directly under predictable `/tmp` names.

### S5 (low) — Release workflow grants write credentials to a mutable external action reference
**Where:** `.github/workflows/release.yml`:8-13, `.github/workflows/release.yml`:22-24
**What:** The release job gives `contents: write` to `cad0p/semver-calver-release/release@v1`. The permission is expected for release publication, but `@v1` is a mutable tag reference; if that tag is moved or the action is compromised, the workflow runs changed code with repository write credentials on `main` pushes and manual dispatches.
**Recommendation:** Pin the action to an audited commit SHA, or enforce protected/immutable tags for the action repository. Keep `contents: write` scoped only to this release job and avoid adding broader default permissions.

## Well-maintained areas

- Shell command arguments that include session names are generally quoted, which avoids the most direct shell metacharacter injection paths around `zmx attach`, `zmx kill`, `zmx run`, and `zmx print`.
- The reaper cross-checks detached `zmx-*` sessions against the managed `sessions` file before killing, which is the right basic boundary once the managed file is validated.
- Installer edits are scoped to a guarded `.zshrc` source line and a clearly delimited Ghostty managed block rather than wholesale config replacement.
- Debug logging records event names, paths, PIDs, and session identifiers, and does not intentionally dump terminal scrollback into `debug.log`.

## Summary

The main adversarial risk is predictable `/tmp` usage, especially the generated reaper script path, which can clobber arbitrary user-writable files through symlinks. The next highest risks are trusting persisted/migrated session names as both filesystem path components and reaper authority, and allowing `--yes` uninstall to recursively delete environment-selected directories. Addressing those with private runtime directories, atomic locks, strict session-name validation, and guarded deletion checks would materially improve the security posture for v0.1.
